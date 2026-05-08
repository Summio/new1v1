import { request } from '@/utils'

export default {
  // 充值配置
  getRechargeConfig: () => request.get('/apis/system/recharge-config'),
  updateRechargeConfig: (data = {}) => request.put('/apis/system/recharge-config', data),
  // 认证用户通话价格档位
  getCertifiedCallPriceConfig: () => request.get('/apis/system/certified-call-price-config'),
  updateCertifiedCallPriceConfig: (data = {}) =>
    request.put('/apis/system/certified-call-price-config', data),
  // 提现配置
  getWithdrawConfig: () => request.get('/apis/system/withdraw-config'),
  updateWithdrawConfig: (data = {}) => request.put('/apis/system/withdraw-config', data),
}
