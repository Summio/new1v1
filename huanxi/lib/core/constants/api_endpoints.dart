/// API 接口路径
/// 与后端 app/api/v1/app/ 路由保持一致
class ApiEndpoints {
  ApiEndpoints._();

  // ========== 用户模块 ==========
  /// App 登录（手机号+密码）
  static const String appLogin = 'app/login';

  /// App 注册（手机号+密码）
  static const String appRegister = 'app/register';

  /// 初始资料可选项
  static const String initialProfileOptions =
      'app/register/initial-profile/options';

  /// 初始资料随机头像
  static const String initialProfileRandomAvatar =
      'app/register/initial-profile/random-avatar';

  /// 初始资料随机昵称
  static const String initialProfileRandomNickname =
      'app/register/initial-profile/random-nickname';

  /// 完成初始资料
  static const String initialProfileComplete =
      'app/register/initial-profile/complete';

  /// 获取当前用户信息
  static const String userInfo = 'app/user/info';

  /// 中国省市所在地选项
  static const String chinaLocations = 'app/location/china';

  /// 勿扰设置
  static const String doNotDisturbSettings = 'app/user/dnd-settings';

  /// 更新当前用户资料
  static const String userProfileUpdate = 'app/user/profile/update';

  /// 上传资料图片
  static const String userUploadImage = 'app/user/upload-image';

  /// 按 user_id 获取公开用户资料
  static const String userPublic = 'app/user/public';

  /// 查询用户关注状态
  static const String userFollowStatus = 'app/user/follow/status';

  /// 关注 / 取消关注
  static const String userFollow = 'app/user/follow';

  /// 我的关注列表
  static const String userFollowingList = 'app/user/follow/list';

  /// 我的粉丝列表
  static const String userFansList = 'app/user/fans/list';

  /// 拉黑 / 解除拉黑
  static const String userBlock = 'app/user/block';

  /// 黑名单状态
  static const String userBlockStatus = 'app/user/block/status';

  /// 我的黑名单列表
  static const String userBlockList = 'app/user/block/list';

  /// 提交用户投诉
  static const String complaintCreate = 'app/complaint/create';

  // ========== 认证用户模块 ==========
  /// 认证用户推荐列表（分页）
  static const String certifiedUserList = 'app/certified-user/list';

  /// 搭讪用户列表（分页）
  static const String flirtUserList = 'app/flirt/list';

  /// 搭讪打招呼额度
  static const String flirtGreetQuota = 'app/flirt/greet/quota';

  /// 搭讪打招呼
  static const String flirtGreet = 'app/flirt/greet';

  /// 活跃页置顶
  static const String certifiedUserActivePin = 'app/certified-user/active-pin';

  /// 提交真人认证
  static const String certificationApply = 'app/certification/apply';

  /// 上传真人认证正面照
  static const String certificationApplyUploadFacePhoto =
      'app/certification/apply/upload-face-photo';

  /// 查询真人认证状态
  static const String certificationApplyStatus =
      'app/certification/apply/status';

  /// 获取认证用户通话价格档位
  static const String certifiedCallPriceTiers =
      'app/certification/call-price/tiers';

  /// 更新认证用户通话价格
  static const String certifiedCallPriceUpdate = 'app/certification/call-price';

  /// 认证用户常用语
  static const String certifiedCommonPhrases =
      'app/certification/common-phrases';

  // ========== 通话模块 ==========
  /// 发起呼叫（余额预检）
  static const String dialing = 'app/dialing';

  /// 通话结束结算
  static const String callEnd = 'app/call/end';

  /// 获取 RTC Token
  static const String rtcToken = 'app/rtc/token';

  /// 接听来电
  static const String callAccept = 'app/call/accept';

  /// 拒绝来电
  static const String callReject = 'app/call/reject';

  /// 取消呼叫
  static const String callCancel = 'app/call/cancel';

  // ========== 礼物模块 ==========
  /// 礼物列表
  static const String giftList = 'app/gift/list';

  /// 发送礼物
  static const String giftSend = 'app/gift/send';

  // ========== 钱包模块 ==========
  /// 余额查询
  static const String walletBalance = 'app/wallet/balance';

  /// 账单明细
  static const String walletTransactions = 'app/wallet/transactions';

  /// 创建充值订单
  static const String rechargeCreate = 'app/recharge/create';

  /// 创建VIP订单
  static const String vipOrderCreate = 'app/vip/order/create';

  /// VIP订单支付回调（仅Mock回调开关开启时可用）
  static const String vipOrderCallback = 'app/vip/order/callback';

  /// 申请提现
  static const String withdrawApply = 'app/withdraw/apply';

  /// 获取提现账户
  static const String withdrawAccount = 'app/withdraw/account';

  /// 上传提现收款码
  static const String withdrawUploadQrCode = 'app/withdraw/upload-qr-code';

  // ========== 初始化模块 ==========
  /// 获取 App 初始化配置（第三方 SDK + 通用配置）
  static const String appBootstrap = 'app/init/bootstrap';

  // ========== 设置模块 ==========
  /// 用户协议
  static const String agreement = 'app/agreement';

  /// 隐私政策
  static const String privacy = 'app/privacy';

  /// 修改密码
  static const String changePassword = 'app/change_password';

  // ========== IM 模块 ==========
  /// 获取 IM UserSig
  static const String imUserSig = 'app/im/usersig';

  /// 文字消息发送前扣费
  static const String imTextCharge = 'app/im/text-charge';

  // ========== 动态模块 ==========
  /// 上传动态媒体（图片/视频）
  static const String momentUpload = 'app/moment/upload';

  /// 发布动态
  static const String momentCreate = 'app/moment/create';

  /// 全局动态列表
  static const String momentFeed = 'app/moment/feed';

  /// 排行榜
  static const String rankingList = 'app/ranking/list';

  /// 我的动态列表
  static const String momentMine = 'app/moment/mine';

  /// 指定用户动态列表
  static const String momentUser = 'app/moment/user';

  /// 删除动态
  static const String momentDelete = 'app/moment'; // DELETE /app/moment/{id}

  // ========== 审核入口状态 ==========
  /// 查询资料编辑与动态发布入口状态
  static const String reviewEntryStatus = 'app/review/entry-status';

  // ========== 反馈模块 ==========
  /// 提交意见反馈
  static const String feedbackCreate = 'app/feedback/create';

  // ========== 系统通知模块 ==========
  /// 系统通知列表
  static const String systemNotifications = 'app/notifications';

  /// 全部系统通知已读
  static const String systemNotificationReadAll = 'app/notifications/read-all';

  // ========== 在线弹窗模块 ==========
  /// App启动弹窗
  static const String systemPopupStartup = 'app/popups/startup';

  /// 待展示弹窗
  static const String systemPopupPending = 'app/popups/pending';

  /// 在线弹窗确认
  static const String systemPopupAckBase = 'app/popups';
}
