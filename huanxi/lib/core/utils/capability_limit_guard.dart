import '../../app/providers/auth_provider.dart';

const certificationClosedMessage = '当前暂未开放真人认证申请';
const certificationMaleOnlyMessage = '当前仅开放男性用户申请真人认证';
const certificationFemaleOnlyMessage = '当前仅开放女性用户申请真人认证';
const profileEditCertifiedOnlyMessage = '通过真人认证后才可以编辑资料';
const momentPublishCertifiedOnlyMessage = '通过真人认证后才可以发布动态';

String? certificationEntryRestrictionMessage(
  AuthState authState,
  AppInitState initState,
) {
  if (authState.isCertifiedUser) return null;

  final limits = initState.capabilityLimits;
  final maleOnly = limits.certificationMaleOnlyEnabled;
  final femaleOnly = limits.certificationFemaleOnlyEnabled;
  if (maleOnly && femaleOnly) return certificationClosedMessage;

  final gender = authState.gender.trim().toLowerCase();
  if (maleOnly && gender != 'male') return certificationMaleOnlyMessage;
  if (femaleOnly && gender != 'female') return certificationFemaleOnlyMessage;
  return null;
}

String? momentPublishRestrictionMessage(
  AuthState authState,
  AppInitState initState,
) {
  if (!initState.capabilityLimits.momentPublishCertifiedOnlyEnabled) {
    return null;
  }
  return authState.isCertifiedUser ? null : momentPublishCertifiedOnlyMessage;
}

String? profileEditRestrictionMessage(
  AuthState authState,
  AppInitState initState,
) {
  if (!initState.capabilityLimits.profileEditCertifiedOnlyEnabled) {
    return null;
  }
  return authState.isCertifiedUser ? null : profileEditCertifiedOnlyMessage;
}
