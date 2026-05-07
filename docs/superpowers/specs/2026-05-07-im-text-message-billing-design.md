# IM 文字消息计费设计

最后更新：2026-05-07

## 背景

欢喜 App 当前普通 IM 聊天页通过腾讯云 IM Flutter SDK 直接发送文本消息。后端仅负责签发 `UserSig`，没有文字消息计费接口。项目已有金币/钻石双币种模型：用户消费金币，主播收益以钻石入账；礼物和通话链路已经采用类似的扣费与分成规则。

本功能为普通文字聊天增加可配置计费能力：文字聊天消息可按条消耗发送方金币，接收方主播按后台配置比例获得钻石。视频通话页面不需要文字聊天扣费。

## 目标

- 后台可配置是否开启普通文字聊天扣费。
- 后台可配置每条文字消息扣费金币数。
- 后台可配置主播分成比例。
- App 普通 IM 聊天页发送文字消息时按配置扣费。
- 视频通话页面不接入该扣费逻辑。
- 扣费消耗发送方金币，主播收益以钻石入账。
- 后端记录文字聊天扣费流水，方便钱包账单和运营追踪。

## 非目标

- 不改造腾讯云 IM 服务端代发消息。
- 不对图片、语音、礼物通知、通话轨迹等非普通文本消息计费。
- 不改变视频通话计费逻辑。
- 不实现复杂的“IM 发送失败自动退款”补偿链路。本期保留扣费记录和 `request_id` 便于追踪与幂等。

## 业务规则

采用“每条普通文字消息发送前扣费授权”的规则：

1. 仅普通 IM 聊天页发送普通文本消息时调用扣费接口。
2. 后台配置关闭时，不扣费，客户端继续发送消息。
3. 接收方不是主播时，不扣费，客户端继续发送消息。
4. 发送方是主播时，不扣费，客户端继续发送消息。
5. 发送方和接收方相同时，接口返回业务错误。
6. 配置开启、发送方为非主播、接收方为主播时：
   - 发送方金币余额必须大于等于每条扣费金额。
   - 后端在事务内扣发送方金币。
   - 后端按 `anchor_share_bps` 计算主播收益钻石。
   - 主播收益钻石为 `price * anchor_share_bps // 10000`。
   - 分成比例允许 `0` 到 `10000`，超出范围由后端校验拒绝或钳制到合法范围，优先采用接口校验拒绝。
7. 余额不足返回业务码 `501`，客户端不发送消息并提示充值。
8. 同一发送方同一 `request_id` 只能成功扣费一次，重复请求返回已有扣费结果，避免网络重试重复扣费。

默认配置：

```json
{
  "enabled": false,
  "price": 0,
  "anchor_share_bps": 5000
}
```

## 后端设计

### 配置存储

复用 `system_config` 表，新增配置项：

- `im_text_message_billing_enabled`：`"true"` 或 `"false"`。
- `im_text_message_price`：每条普通文字消息扣费金币数，整数。
- `im_text_message_anchor_share_bps`：主播分成比例，万分比整数。

后台通过专用接口对上述三项进行读写，运营不直接编辑裸配置键。

### 管理端接口

新增管理端专用接口：

- `GET /api/v1/apis/system/im-text-billing-config`
- `PUT /api/v1/apis/system/im-text-billing-config`

请求/响应结构：

```json
{
  "enabled": true,
  "price": 20,
  "anchor_share_bps": 5000
}
```

校验规则：

- `enabled` 为布尔值。
- `price` 为整数，关闭时允许 `0`，开启时必须大于 `0`。
- `anchor_share_bps` 为 `0` 到 `10000` 的整数。
- 更新成功后清除 `SYSTEM_CONFIG_CACHE_KEY`。

### App 扣费接口

新增 App 接口：

- `POST /api/v1/app/im/text-charge`

请求结构：

```json
{
  "receiver_user_id": 123,
  "request_id": "client-generated-id"
}
```

成功响应数据：

```json
{
  "charged": true,
  "price": 20,
  "anchor_income_diamonds": 10,
  "coins": 980,
  "diamonds": 0,
  "receiver_user_id": 123,
  "request_id": "client-generated-id"
}
```

无需扣费时：

```json
{
  "charged": false,
  "price": 0,
  "anchor_income_diamonds": 0,
  "coins": 1000,
  "diamonds": 0,
  "receiver_user_id": 123,
  "request_id": "client-generated-id"
}
```

错误响应：

- `400`：参数错误、不能给自己发消息。
- `404`：接收方不存在或状态异常。
- `501`：余额不足。

### 数据模型

新增 `ImTextMessageChargeRecord`：

- `sender_id`：发送方用户 ID。
- `receiver_id`：接收方用户 ID。
- `request_id`：客户端请求 ID。
- `price`：本条消息扣费金币数。
- `anchor_share_bps`：本条消息主播分成比例快照。
- `anchor_income_diamonds`：本条消息主播收益钻石。
- `status`：`charged`。
- `created_at` / `updated_at`：继承现有时间戳模型。

唯一约束：

- `(sender_id, request_id)` 唯一。

需要通过 Aerich 迁移新增表，禁止直接改库。

### 钱包与运营账单

App 钱包账单 `/wallet/transactions` 增加：

- 发送方金币支出：`rec_type = "im_text"`，标题为“文字聊天”。
- 主播钻石收入：`rec_type = "im_text"`，标题为“文字聊天收益”。

后台用户账单 `/app_user/bill/list` 增加同类记录，并允许 `biz_type=im_text` 过滤。

## Flutter 设计

### 配置下发

`GET /api/v1/app/init/bootstrap` 返回：

```json
{
  "im_text_billing": {
    "enabled": true,
    "price": 20,
    "anchor_share_bps": 5000
  }
}
```

Flutter 可用于展示发送成本，但扣费判断仍以后端扣费接口为准，避免前端固化业务规则。

### 普通 IM 页发送流程

修改 `huanxi/lib/modules/im/im_page.dart` 的 `_sendMessage()`：

1. 读取输入文本并去空。
2. 生成本次发送的 `request_id`。
3. 调用 `POST /app/im/text-charge`，传入接收方 App 用户 ID 和 `request_id`。
4. 若返回 `501`，提示余额不足，不调用腾讯 IM SDK。
5. 若返回成功，继续调用 `IMService.sendTextMessage()`。
6. SDK 发送成功后按现有逻辑追加本地消息并清空输入框。
7. SDK 发送失败时提示“消息发送失败”，扣费记录保留，便于运营追踪。

不修改视频通话页。通话轨迹、礼物通知等自定义消息不调用该扣费接口。

## 后台前端设计

新增独立页面“文字聊天计费”：

- 开关：是否开启文字聊天扣费。
- 数字输入：每条扣费金币数。
- 数字输入：主播分成比例，可用百分比展示，提交时转换为万分比。
- 保存按钮：调用专用配置接口。

页面风格参考现有 `backend/web/src/views/system/recharge-config/index.vue`，保持 Naive UI 组件与当前后台风格一致。

## 测试计划

后端优先测试：

- 配置接口读取默认值。
- 配置接口拒绝开启但价格为 `0`。
- 配置接口拒绝非法分成比例。
- 扣费配置关闭时不扣费。
- 接收方不是主播时不扣费。
- 发送方是主播时不扣费。
- 普通用户给主播发文字时扣金币并给主播加钻石。
- 余额不足返回 `501` 且不产生扣费记录。
- 相同 `request_id` 重试不会重复扣费。
- 钱包账单包含文字聊天支出和主播收益。

Flutter 测试或手动验证：

- 余额不足时不发送腾讯 IM 文本。
- 扣费成功后仍按现有方式发送文本并展示消息。
- 配置关闭时发送流程保持原样。
- 视频通话页面不受影响。

## 风险与回滚

- 风险：后端扣费成功但腾讯 IM SDK 发送失败，用户会被扣费但消息未发出。
  - 缓解：保留扣费记录和 `request_id`，错误提示明确；后续如接入腾讯服务端回执，可升级为确认后结算或失败退款。
- 风险：客户端绕过扣费接口直接调用 SDK。
  - 缓解：当前客户端可控，但腾讯 IM SDK 直发天然无法由业务后端强制拦截。本期实现客户端约束；若需要强一致，可后续改为后端代发或接入服务端回调审计。
- 风险：配置开启后价格误填过高。
  - 缓解：后台表单显示单位与范围校验，后端限制最大值。

回滚方式：

- 后台关闭 `im_text_message_billing_enabled` 即可停止文字聊天扣费。
- 如需彻底回滚，移除 Flutter 扣费接口调用后恢复为直接 SDK 发送。
