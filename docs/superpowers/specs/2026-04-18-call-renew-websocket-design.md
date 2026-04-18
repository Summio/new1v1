# 通话续租 WebSocket 化方案

## 扣费原则

- 按分钟计费，不足一分钟按一分钟算
- 前 N 秒免费（可配置，默认 10 秒）
- 余额实时更新，客户端实时显示剩余金币
- 拨打前余额不足一分钟费用，拒绝拨打
- 通话中余额不足下一分钟的费用，立即挂断

## 通话生命周期

### 拨打前（拨号阶段）

1. 用户发起呼叫 → HTTP POST /dialing
2. 服务端检查余额是否 >= 一分钟费用
3. 不足则拒绝，提示充值
4. 足够则创建通话记录（pending），推送来电 WebSocket

### 通话开始（被叫接受）

1. 被叫接受 → HTTP POST /call/accept
2. 服务端标记 status = ongoing，记录 connected_at = 服务端时间
3. 服务端记录 deducted_minutes = 0，last_renew_at = now
4. WebSocket 推送 call_accepted 给主叫
5. 双方进入通话房间

### 通话中（服务端 watchdog 主导）

1. Watchdog 每 5 秒轮询所有 ongoing 通话
2. 对每条通话，根据 connected_at 计算已通话秒数
3. 计算 due_minutes = ceil((duration - free_seconds) / 60)
4. 如果 due_minutes > deducted_minutes：
   - 计算本次应扣分钟数 = due_minutes - deducted_minutes
   - 计算本次扣费金额 = 本次应扣分钟数 × 每分钟价格
   - 扣费（条件更新：coins >= 本次扣费金额）
   - 如果余额不足：标记通话结束，end_reason = balance_empty，推送 call_balance_empty
   - 如果扣费成功：更新 deducted_minutes，推送 balance_updated 给付费方

### 通话结束（主动挂断或被挂断）

1. 任意一方挂断 → HTTP POST /call/end
2. 服务端计算实际费用：actual_minutes = ceil((duration - free_seconds) / 60)
3. 计算实扣：actual_fee = actual_minutes × 每分钟价格
4. 计算退款：refund = deducted_amount - actual_fee（如有多扣则退款）
5. 更新 coins = coins + refund，推送 balance_updated 给付费方
6. WebSocket 推送 call_ended 给对方

## 服务端数据模型

通话记录字段：

- billing_free_seconds（新增，建议命名）：本次通话免费秒数快照（在接听时固化，后续不随系统配置变更）
- deducted_minutes（已有）：已扣费分钟数（计费权威字段）
- deducted_amount（已有）：已扣费总额（分）
- last_renew_at（已有）：上次扣费时间（服务端时钟）

### 数据模型决策

- `paid_seconds` **不新增落库字段**。它是派生值，统一按 `deducted_minutes * 60` 计算，避免双写不一致。
- `billing_free_seconds` **建议落库**。避免通话过程中后台改配置导致同一通话计费口径漂移。
- （可选）`payer_user_id` 落库快照：如果业务允许通话期间主播身份发生变化，建议在接听时固化付费方，避免中途规则变化影响扣费对象。

## WebSocket 推送事件

| 事件 | 触发时机 | 推送对象 | 数据 |
|------|----------|----------|------|
| call_accepted | 被叫接受通话 | 主叫 | {call_id} |
| call_balance_empty | 余额不足挂断 | 双方 | {call_id} |
| balance_updated | 每次扣费后 | 付费方 | {coins, diamonds} |
| call_ended | 通话正常结束 | 双方 | {call_id, end_reason} |

## 客户端改动

1. 移除 _renewLeaseIfNeeded() - 不再主动调用续租接口
2. 保留本地计时器 - 仅用于显示通话时长，不参与任何扣费逻辑
3. 监听 balance_updated - 收到后更新余额显示（实时）
4. 监听 call_balance_empty - 收到后提示余额不足，3 秒后退出通话房间
5. 通话房间心跳 - 每 30 秒发送一次 ping 保持连接即可

## 服务端 watchdog 核心逻辑

每 5 秒轮询所有 ongoing 通话：

for each call in ongoing_calls:
    duration = now - call.connected_at
    due_minutes = ceil((duration - call.billing_free_seconds) / 60)

    if due_minutes > call.deducted_minutes:
        to_charge_minutes = due_minutes - call.deducted_minutes
        to_charge_amount = to_charge_minutes × call.call_price

        updated = UPDATE app_user
                  SET coins = coins - to_charge_amount
                  WHERE id = payer_id AND coins >= to_charge_amount

        if updated == 0:
            # 余额不足，关闭通话
            call.status = 'ended'
            call.end_reason = 'balance_empty'
            push('call_balance_empty', {call_id})
        else:
            call.deducted_minutes = due_minutes
            push('balance_updated', {coins: new_balance})

## 优点

- 服务端是扣费唯一权威，无法伪造
- 余额实时同步，客户端始终显示准确
- 客户端零参与扣费逻辑，代码简化
- 统一扣费时机，无客户端计时漂移

## 改动量

- 后端 watchdog：增加每次扣费后的 balance_updated 推送（本次已完成）
- 后端 call.py：移除客户端续租逻辑改为 watchdog 全权负责（需改动）
- 后端模型与迁移：新增 `billing_free_seconds` 字段，并在 `call/accept` 时写入快照（需改动）
- Flutter 端：移除 _renewLeaseIfNeeded() 和相关 HTTP 调用（需改动）
