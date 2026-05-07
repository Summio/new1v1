import { request } from '@/utils'

export default {
  // 充值配置
  getRechargeConfig: () => request.get('/apis/system/recharge-config'),
  updateRechargeConfig: (data = {}) => request.put('/apis/system/recharge-config', data),
  // 文字聊天计费配置
  getIMTextBillingConfig: () => request.get('/apis/system/im-text-billing-config'),
  updateIMTextBillingConfig: (data = {}) =>
    request.put('/apis/system/im-text-billing-config', data),
}
