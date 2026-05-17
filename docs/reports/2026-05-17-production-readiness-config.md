# 生产环境上线配置与运行注意事项

最后更新：2026-05-17

适用范围：`backend/` FastAPI 后端、WebSocket 链路、Redis、MySQL、Nginx/网关、后台任务与本次上线前性能修复后的运行要求。

## 1. 上线前必须确认

- `DEBUG=false`。
- `RELOAD=false` 或不设置，生产环境禁止 Uvicorn reload。
- `SECRET_KEY` 必须配置为生产强密钥，不得使用开发兜底值。
- `DB_PASSWORD` 必须配置为生产数据库密码，不得为空，不得使用 `123456`。
- `AUTO_MIGRATE_ON_STARTUP=false`。
- `AUTO_SEED_ON_STARTUP=false`。
- `ENABLE_MOCK_CALLBACK=false`。
- `CORS_ORIGINS` 必须配置为明确域名列表，生产环境不要留空依赖默认值。
- `TRUSTED_PROXY_IPS` 应配置为内网 Nginx/网关 IP 列表，避免无条件信任客户端伪造的 `X-Forwarded-For`。
- 生产必须使用 Redis；WebSocket 多 worker 推送、在线状态、限流、通话心跳、缓存都依赖 Redis。
- 生产必须执行 Aerich 迁移后再启动服务，不要依赖服务启动时自动迁移。

## 2. 后端环境变量建议

以下是生产环境需要显式配置或重点确认的环境变量。

```env
DEBUG=false
RELOAD=false

SECRET_KEY=<生产强密钥>

DB_HOST=<mysql-host>
DB_PORT=3306
DB_USER=<mysql-user>
DB_PASSWORD=<mysql-password>
DB_DATABASE=huanxi
DB_POOL_MIN=5
DB_POOL_MAX=10

REDIS_HOST=<redis-host>
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=<redis-password>
REDIS_SOCKET_CONNECT_TIMEOUT=2
REDIS_SOCKET_TIMEOUT=2
REDIS_HEALTH_CHECK_INTERVAL=30
REDIS_MAX_CONNECTIONS=100

CORS_ORIGINS=https://<admin-domain>,https://<app-api-domain>
TRUSTED_PROXY_IPS=<nginx-or-gateway-private-ip>

AUTO_MIGRATE_ON_STARTUP=false
AUTO_SEED_ON_STARTUP=false
ENABLE_MOCK_CALLBACK=false

IM_SDKAPPID=<tencent-im-sdkappid>
IM_SECRETKEY=<tencent-im-secretkey>
```

说明：

- `DB_POOL_MAX` 是单进程连接池上限。总 MySQL 连接数约为 `后端进程数 * DB_POOL_MAX`，还要给迁移任务、管理脚本、数据库运维连接留余量。
- `REDIS_MAX_CONNECTIONS` 是单进程 Redis 连接池上限。总 Redis 连接数约为 `后端进程数 * REDIS_MAX_CONNECTIONS`，需要小于 Redis `maxclients` 并留足余量。
- `REDIS_SOCKET_CONNECT_TIMEOUT` 和 `REDIS_SOCKET_TIMEOUT` 当前建议为 `2s`。如果 Redis 跨机房或网络抖动明显，需要压测后调整，但不建议无限等待。
- `HEARTBEAT_INTERVAL` 当前配置用于通话心跳相关业务，默认 `5s`。不要和 WebSocket ping 间隔混淆。

## 3. WebSocket 长连接运行要求

当前 App WebSocket 入口为：

```text
/api/ws/app
```

具体前缀以 `register_routers(app, prefix="/api")` 的注册结果为准。

当前服务端策略：

- 认证首帧超时：`30s`。
- 客户端 ping 间隔约定：`20s`。
- 服务端无消息心跳超时：`75s`。
- 在线租约 TTL：`120s`，Redis key 为 `ws:online_lease:{user_id}`。
- 同账号重复连接时，新连接会替换当前连接，并主动关闭旧 WebSocket。
- 正常断开、发送失败、心跳超时都会清理本 worker 内存连接与 Redis 在线状态。
- 如果进程异常退出导致 `finally` 未执行，在线租约会在 `120s` 后过期；业务在线判断会排除租约过期用户，并惰性清理 Redis 残留在线集合与上线排序集合。

### 3.1 Nginx/网关配置要求

WebSocket 代理必须保留 Upgrade 头，且 idle timeout 必须大于服务端 `75s` 心跳超时。建议 `120s-180s`。

参考 Nginx 配置：

```nginx
location /api/ws/ {
    proxy_pass http://backend_upstream;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_read_timeout 180s;
    proxy_send_timeout 180s;
    proxy_connect_timeout 10s;

    proxy_buffering off;
}
```

如果网关、负载均衡、CDN 或云厂商 API 网关也在链路中，所有层级都要支持 WebSocket，并将 idle timeout 设置到不低于 `120s`。

### 3.2 客户端要求

- 连接建立后首帧必须发送：

```json
{"type":"auth","token":"<jwt>"}
```

- 客户端应每约 `20s` 发送：

```json
{"type":"ping"}
```

- 客户端收到断开或认证失败后，应做指数退避重连，避免全量用户同时重连打爆服务。
- 客户端进入后台、弱网恢复、网络切换时，应重新建立 WebSocket，并重新认证。

### 3.3 WebSocket 观测指标

上线后至少观察：

- 当前在线用户数：`SCARD ws:online`，以及租约存在数量。
- 租约缺失但仍在 `ws:online` 的用户数量，正常应很低，并在访问在线接口时逐步下降。
- WebSocket 连接数与后端进程内存。
- WebSocket 断开原因日志：认证超时、心跳超时、发送失败、旧连接关闭。
- Redis Pub/Sub 发布失败次数。
- 关键事件推送失败次数：`call_ended`、`call_timeout`、`call_balance_empty`、`balance_updated`。

## 4. Redis 运行注意事项

Redis 当前承担：

- WebSocket 在线状态：`ws:online`、`ws:online_lease:*`、`ws:user:*:pid`、`ws:pid:*:users`。
- WebSocket Pub/Sub：`ws:broadcast`。
- 手动离线状态：`ws:manual_offline:{user_id}`，TTL 24 小时。
- 通话心跳与 presence：`call:presence:{call_id}`，TTL 10 分钟。
- 推荐用户缓存：`moment:recommended_user_ids`，TTL 45 秒。
- 黑名单排除缓存：`user:block:exclude_ids:{user_id}`，TTL 45 秒。
- 业务限流 Lua 脚本与相关限流 key。

必须确认：

- Redis 开启持久化或至少有可靠高可用方案。WebSocket 在线状态可丢，但通话心跳、限流与缓存异常会影响业务体验。
- Redis `maxclients` 大于 `后端进程数 * REDIS_MAX_CONNECTIONS + 运维/监控连接余量`。
- Redis 网络延迟稳定，P99 命令耗时建议低于 `20ms`。
- Redis 内存策略不要轻易使用会随机淘汰关键业务 key 的策略；如果必须设置 `maxmemory-policy`，需评估通话和限流 key 的风险。
- 对 Redis 慢日志和连接数做监控。

## 5. MySQL 运行注意事项

必须确认：

- 发布前已执行 Aerich 迁移。
- `AUTO_MIGRATE_ON_STARTUP=false`，生产多进程启动时禁止自动迁移。
- `AUTO_SEED_ON_STARTUP=false`，生产启动禁止自动种子数据。
- MySQL 最大连接数大于 `后端进程数 * DB_POOL_MAX + 管理任务/迁移/运维余量`。
- 慢查询日志开启，建议阈值先设 `500ms`，压测后再调整。
- 确认核心热路径索引已存在，尤其是：
  - 通话记录状态、双方用户、创建时间相关索引。
  - 动态 feed 的用户、审核状态、置顶、创建时间相关索引。
  - 通知/弹窗 receipt 的用户与任务/通知关联索引。
  - 黑名单关系的 blocker/blocked 组合查询索引。

## 6. 后台任务与多进程部署注意事项

当前 `backend/app/__init__.py` 的 lifespan 会在每个后端进程启动：

- `run_call_watchdog(stop_event)`
- `run_auditlog_cleanup(stop_event)`
- `run_system_notification_scheduler(stop_event)`
- `run_system_popup_scheduler(stop_event)`

其中通话 watchdog 已有 leader 选举相关逻辑。上线前必须重点确认：

- 如果使用多个 Uvicorn/Gunicorn worker，通知调度器、弹窗调度器、审计日志清理是否具备任务级幂等和并发保护。
- 如果不确定，保守做法是：API 服务多进程运行，调度任务拆为单独一个 worker/进程运行，或者先以单进程后端启动，待压测确认后再扩 worker。
- 通知/弹窗发布本次已加单次目标上限和分批写入，但定时调度并发仍应通过 run key、状态机、数据库唯一约束或分布式锁确认不会重复发布。

## 7. 本次性能保护相关上线参数

这些参数当前是代码常量，不是环境变量。上线前需要按业务预期确认是否合适：

- 系统通知单次目标用户上限：`5000`。
- 系统通知 receipt 批量写入大小：`500`。
- 系统通知未读推送并发：`20`。
- 在线弹窗单次目标用户上限：`5000`。
- 在线弹窗 receipt 批量写入大小：`1000`。
- 在线弹窗推送并发：`20`。
- App 启动弹窗扫描 running 任务数：`5`。
- App 启动弹窗最多返回：`3`。
- 单次搭讪目标上限：`100`。
- 搭讪 TIM 发送并发：`10`。
- 推荐用户缓存 TTL：`45s`。
- 黑名单排除缓存 TTL：`45s`。
- WebSocket 在线租约 TTL：`120s`。

如果预期峰值用户数、运营通知规模或弹窗活动规模超过这些上限，应先做压测，再决定是否改常量或改为后台分批任务。

## 8. 反向代理、上传与静态文件

- `/uploads` 当前由 FastAPI `StaticFiles` 挂载。生产建议由 Nginx 或对象存储/CDN 承担静态文件分发，避免大文件下载占用 API worker。
- 如果存在用户上传图片/视频，Nginx 需要设置合理的 `client_max_body_size`，并和后端上传接口限制保持一致。
- 不建议让 API worker 承担大文件长时间传输；大文件应走对象存储直传或后端签名上传。

参考：

```nginx
client_max_body_size 20m;

location /uploads/ {
    alias /path/to/backend/uploads/;
    expires 7d;
    add_header Cache-Control "public";
}
```

具体大小需要按产品实际上传限制确认。

## 9. 第三方服务

腾讯 IM：

- 生产必须配置 `IM_SDKAPPID` 与 `IM_SECRETKEY`。
- 搭讪批量 TIM 发送已限制并发并复用 HTTP client；仍需要监控 TIM 接口失败率、超时率、限频错误。
- TIM 发送失败不会阻断整个搭讪后台任务，但会造成部分用户收不到消息，需要通过日志或业务统计观察。

支付：

- `ENABLE_MOCK_CALLBACK=false`。
- 生产必须接入微信/支付宝真实回调，回调接口必须校验签名。
- 支付回调必须具备幂等保护，避免重复加币。

WebRTC/音视频：

- 当前仓库说明中真实 WebRTC 能力尚未完全落地。上线前必须确认 RTC 房间、Token、断线重连、计费停止和通话结束事件链路已经压测。

## 10. 日志与监控

必须监控：

- API P50/P95/P99 延迟。
- HTTP 5xx、4xx 比例。
- WebSocket 当前连接数、断开数、认证失败数、心跳超时数。
- Redis 连接数、命令耗时、慢日志、Pub/Sub publish 失败。
- MySQL 连接数、慢查询、锁等待、事务耗时。
- 后端进程 CPU、内存、文件句柄数。
- 后台任务执行耗时和失败次数。
- 通话 watchdog leader 获取/续期失败次数。
- 通话心跳处理耗时和失败次数。
- TIM、支付、RTC 等第三方调用超时率和失败率。

日志注意：

- 生产日志不要输出 token、手机号、身份证、支付密钥、IM 密钥等敏感信息。
- WebSocket 高频 ping/pong 不应写 INFO 级别日志，否则高并发下日志 IO 会放大。
- 关键业务事件可以保留结构化日志：通话开始/结束、余额不足、支付回调、提现、IM 发送失败。

## 11. 上线前压测建议

至少压测以下链路：

- App 登录后建立 WebSocket：持续连接 30 分钟，观察连接数、内存、Redis 租约与断开回收。
- WebSocket ping：模拟客户端每 20 秒 ping，观察服务端是否稳定刷新租约。
- 异常断网：模拟客户端直接断网或杀进程，确认 `120s` 后业务在线判断不再返回该用户。
- 同账号多端/重复连接：确认旧连接被关闭，新连接可正常收到事件。
- 通话心跳：持续通话 30 分钟以上，观察计费、余额推送、断线检测和通话结束事件。
- 推荐动态 feed：压测 `category=recommend`，观察 Redis 命中率和 MySQL 查询下降。
- 黑名单过滤 feed：压测存在大量拉黑关系的用户，观察缓存命中后延迟。
- 系统通知发布：分别用 100、1000、5000 用户目标压测，观察 receipt 写入耗时和 WebSocket 推送耗时。
- 在线弹窗发布：分别用 100、1000、5000 在线用户压测，观察写入和推送耗时。
- App 启动弹窗：构造多条 running app_start 任务，确认接口延迟稳定且最多返回 3 条。
- 搭讪打招呼：模拟 100 个在线目标，观察 TIM 并发、失败隔离和接口响应。

建议通过标准：

- 常规 App API P95 < 300ms，P99 < 800ms，具体以机器规格和业务目标校准。
- WebSocket ping/pong P95 < 100ms。
- 通话心跳接口/消息处理 P95 < 200ms。
- MySQL 慢查询无持续增长。
- Redis P99 命令耗时稳定，无连接耗尽。
- 后端进程内存无持续爬升。
- 异常断开后，业务在线状态在约 `120s` 后自动收敛。

## 12. 发布与回滚

发布前：

- 执行后端测试与 lint。
- 执行 Aerich 迁移。
- 确认 `.env` 已按生产配置填充。
- 确认 Redis、MySQL、Nginx、证书、域名、CORS、TRUSTED_PROXY_IPS 配置。
- 确认管理后台构建产物与 API 域名。
- 确认 Flutter 构建时显式传入 `API_BASE_URL`，客户端不得内置默认后端地址。

回滚建议：

- 代码回滚必须和数据库迁移兼容性一起评估。
- 若 Redis 配置导致连接异常，优先回滚 Redis 连接参数或降低 worker 数，而不是关闭 Redis。
- 若 WebSocket 大面积断连，优先检查 Nginx/网关 idle timeout、Upgrade 头、Redis Pub/Sub 和后端 worker 重启情况。
- 若通知/弹窗发布压力过大，先降低运营单次目标规模，必要时暂停相关调度任务。

