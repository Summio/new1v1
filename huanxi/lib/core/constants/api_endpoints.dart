/// API 接口路径
/// 与后端 app/api/v1/app/ 路由保持一致
class ApiEndpoints {
  ApiEndpoints._();

  // ========== 用户模块 ==========
  /// App 登录（手机号+密码）
  static const String appLogin = 'app/login';
  /// App 注册（手机号+密码）
  static const String appRegister = 'app/register';
  /// 获取当前用户信息
  static const String userInfo = 'app/user/info';
  /// 按 user_id 获取公开用户资料
  static const String userPublic = 'app/user/public';

  // ========== 主播模块 ==========
  /// 主播推荐列表（分页）
  static const String anchorList = 'app/anchor/list';
  /// 申请成为主播
  static const String anchorApply = 'app/anchor/apply';
  /// 查询主播申请状态
  static const String anchorApplyStatus = 'app/anchor/apply/status';

  // ========== 通话模块 ==========
  /// 发起呼叫（余额预检）
  static const String dialing = 'app/dialing';
  /// 通话续租扣费
  static const String callRenew = 'app/call/renew';
  /// 通话结束结算
  static const String callEnd = 'app/call/end';
  /// 获取 RTC Token
  static const String rtcToken = 'app/rtc/token';
  /// 查询通话状态
  static const String callStatus = 'app/call/status';
  /// 查询来电
  static const String callIncoming = 'app/call/incoming';
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
  /// 申请提现
  static const String withdrawApply = 'app/withdraw/apply';

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
}
