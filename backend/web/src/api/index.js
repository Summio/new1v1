import { request } from '@/utils'
import systemApi from './system'

export default {
  login: (data) => request.post('/base/access_token', data, { noNeedToken: true }),
  getUserInfo: () => request.get('/base/userinfo'),
  getUserMenu: () => request.get('/base/usermenu'),
  getUserApi: () => request.get('/base/userapi'),
  // profile
  updateProfile: (data = {}) => request.post('/base/profile/update', data),
  uploadUserAvatar: (data) =>
    request.post('/base/profile/upload-avatar', data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  updatePassword: (data = {}) => request.post('/base/update_password', data),
  // users
  getUserList: (params = {}) => request.get('/user/list', { params }),
  getUserById: (params = {}) => request.get('/user/get', { params }),
  createUser: (data = {}) => request.post('/user/create', data),
  updateUser: (data = {}) => request.post('/user/update', data),
  deleteUser: (params = {}) => request.delete(`/user/delete`, { params }),
  resetPassword: (data = {}) => request.post(`/user/reset_password`, data),
  // app users
  getAppUserList: (params = {}) => request.get('/app_user/list', { params }),
  getAppUserById: (params = {}) => request.get('/app_user/get', { params }),
  adjustAppUserBalance: (data = {}) => request.post('/app_user/balance/adjust', data),
  updateAppUser: (data = {}) => request.post('/app_user/update', data),
  getAppUserBillList: (params = {}) => request.get('/app_user/bill/list', { params }),
  reviewCertification: (data = {}) => request.post('/app_user/certification/review', data),
  getProfileReviewList: (params = {}) => request.get('/app_user/profile-review/list', { params }),
  getProfileReviewById: (params = {}) => request.get('/app_user/profile-review/get', { params }),
  reviewProfileReviewItem: (data = {}) =>
    request.post('/app_user/profile-review/item/review', data),
  approveAllProfileReviewItems: (data = {}) =>
    request.post('/app_user/profile-review/approve-all', data),
  rejectAllProfileReviewItems: (data = {}) =>
    request.post('/app_user/profile-review/reject-all', data),
  completeProfileReview: (data = {}) => request.post('/app_user/profile-review/complete', data),
  uploadAppUserImage: (data) =>
    request.post('/app_user/upload-image', data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  // call record
  getCallRecordList: (params = {}) => request.get('/call_record/list', { params }),
  // moment manage
  getMomentList: (params = {}) => request.get('/moment/list', { params }),
  deleteMoment: (params = {}) => request.delete('/moment/delete', { params }),
  pinMoment: (params = {}) => request.post('/moment/pin', null, { params }),
  unpinMoment: (params = {}) => request.post('/moment/unpin', null, { params }),
  recommendMoment: (params = {}) => request.post('/moment/recommend', null, { params }),
  unrecommendMoment: (params = {}) => request.post('/moment/unrecommend', null, { params }),
  clearMomentRecommendOverride: (params = {}) =>
    request.post('/moment/clear-recommend-override', null, { params }),
  reviewMoment: (data = {}) => request.post('/moment/review', data),
  // gift manage
  getGiftList: (params = {}) => request.get('/gift/list', { params }),
  getGiftById: (params = {}) => request.get('/gift/get', { params }),
  createGift: (data = {}) => request.post('/gift/create', data),
  updateGift: (data = {}) => request.post('/gift/update', data),
  deleteGift: (params = {}) => request.delete('/gift/delete', { params }),
  uploadGiftResource: (data, params = {}) =>
    request.post('/gift/upload-resource', data, {
      params,
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  // recharge manage
  getRechargeList: (params = {}) => request.get('/recharge/list', { params }),
  reviewRechargeOrder: (data = {}) => request.post('/recharge/review', data),
  // withdraw manage
  getWithdrawList: (params = {}) => request.get('/withdraw/list', { params }),
  reviewWithdrawApply: (data = {}) => request.post('/withdraw/review', data),
  getWithdrawAccountList: (params = {}) => request.get('/withdraw/account/list', { params }),
  reviewWithdrawAccount: (data = {}) => request.post('/withdraw/account/review', data),
  // ranking manage
  getRankingList: (params = {}) => request.get('/ranking/list', { params }),
  refreshRanking: (data = {}) => request.post('/ranking/refresh', data),
  getRankingConfig: () => request.get('/ranking/config'),
  updateRankingConfig: (data = {}) => request.put('/ranking/config', data),
  // role
  getRoleList: (params = {}) => request.get('/role/list', { params }),
  createRole: (data = {}) => request.post('/role/create', data),
  updateRole: (data = {}) => request.post('/role/update', data),
  deleteRole: (params = {}) => request.delete('/role/delete', { params }),
  updateRoleAuthorized: (data = {}) => request.post('/role/authorized', data),
  getRoleAuthorized: (params = {}) => request.get('/role/authorized', { params }),
  // menus
  getMenus: (params = {}) => request.get('/menu/list', { params }),
  createMenu: (data = {}) => request.post('/menu/create', data),
  updateMenu: (data = {}) => request.post('/menu/update', data),
  deleteMenu: (params = {}) => request.delete('/menu/delete', { params }),
  // apis
  getApis: (params = {}) => request.get('/api/list', { params }),
  createApi: (data = {}) => request.post('/api/create', data),
  updateApi: (data = {}) => request.post('/api/update', data),
  deleteApi: (params = {}) => request.delete('/api/delete', { params }),
  refreshApi: (data = {}) => request.post('/api/refresh', data),
  // depts
  getDepts: (params = {}) => request.get('/dept/list', { params }),
  createDept: (data = {}) => request.post('/dept/create', data),
  updateDept: (data = {}) => request.post('/dept/update', data),
  deleteDept: (params = {}) => request.delete('/dept/delete', { params }),
  // auditlog
  getAuditLogList: (params = {}) => request.get('/auditlog/list', { params }),
  // feedback manage
  getFeedbackList: (params = {}) => request.get('/feedback/list', { params }),
  deleteFeedback: (params = {}) => request.delete('/feedback/delete', { params }),
  // complaint manage
  getComplaintList: (params = {}) => request.get('/complaint/list', { params }),
  getComplaintDetail: (params = {}) => request.get('/complaint/detail', { params }),
  handleComplaint: (data = {}) => request.put('/complaint/handle', data),
  // system config
  getSystemConfigList: (params = {}) => request.get('/system_config/list', { params }),
  createSystemConfig: (data = {}) => request.post('/system_config/create', data),
  updateSystemConfig: (data = {}) => request.post('/system_config/update', data),
  deleteSystemConfig: (params = {}) => request.delete('/system_config/delete', { params }),
  // system - recharge config
  ...systemApi,
}
