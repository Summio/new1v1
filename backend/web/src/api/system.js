import { request } from '@/utils'

export default {
  // 充值配置
  getRechargeConfig: () => request.get('/apis/system/recharge-config'),
  updateRechargeConfig: (data = {}) => request.put('/apis/system/recharge-config', data),
}
