import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/auth_provider.dart';
import 'package:huanxi/core/utils/capability_limit_guard.dart';

AuthState _authState({String gender = 'male', bool isCertifiedUser = false}) {
  return AuthState(gender: gender, isCertifiedUser: isCertifiedUser);
}

void main() {
  test('bootstrap parser exposes capability limits with defaults', () {
    final state = AppInitState.fromBootstrapMap(const {});

    expect(state.capabilityLimits.certificationMaleOnlyEnabled, isFalse);
    expect(state.capabilityLimits.certificationFemaleOnlyEnabled, isFalse);
    expect(state.capabilityLimits.profileEditCertifiedOnlyEnabled, isFalse);
    expect(state.capabilityLimits.momentPublishCertifiedOnlyEnabled, isFalse);
  });

  test('bootstrap parser exposes profile edit capability limit', () {
    final state = AppInitState.fromBootstrapMap({
      'capability_limits': {'profile_edit_certified_only_enabled': true},
    });

    expect(state.capabilityLimits.profileEditCertifiedOnlyEnabled, isTrue);
  });

  test('certification entry guard respects gender limits', () {
    final maleOnly = AppInitState.fromBootstrapMap({
      'capability_limits': {
        'certification_male_only_enabled': true,
        'certification_female_only_enabled': false,
      },
    });
    final femaleOnly = AppInitState.fromBootstrapMap({
      'capability_limits': {
        'certification_male_only_enabled': false,
        'certification_female_only_enabled': true,
      },
    });

    expect(
      certificationEntryRestrictionMessage(
        _authState(gender: 'male'),
        maleOnly,
      ),
      isNull,
    );
    expect(
      certificationEntryRestrictionMessage(
        _authState(gender: 'female'),
        maleOnly,
      ),
      certificationMaleOnlyMessage,
    );
    expect(
      certificationEntryRestrictionMessage(
        _authState(gender: 'female'),
        femaleOnly,
      ),
      isNull,
    );
    expect(
      certificationEntryRestrictionMessage(
        _authState(gender: 'male'),
        femaleOnly,
      ),
      certificationFemaleOnlyMessage,
    );
  });

  test('certification entry guard blocks when both gender limits are on', () {
    final state = AppInitState.fromBootstrapMap({
      'capability_limits': {
        'certification_male_only_enabled': true,
        'certification_female_only_enabled': true,
      },
    });

    expect(
      certificationEntryRestrictionMessage(_authState(gender: 'male'), state),
      certificationClosedMessage,
    );
    expect(
      certificationEntryRestrictionMessage(_authState(gender: 'female'), state),
      certificationClosedMessage,
    );
  });

  test('moment publish guard blocks non-certified users only', () {
    final state = AppInitState.fromBootstrapMap({
      'capability_limits': {'moment_publish_certified_only_enabled': true},
    });

    expect(
      momentPublishRestrictionMessage(
        _authState(isCertifiedUser: false),
        state,
      ),
      momentPublishCertifiedOnlyMessage,
    );
    expect(
      momentPublishRestrictionMessage(_authState(isCertifiedUser: true), state),
      isNull,
    );
  });

  test('profile edit guard blocks non-certified users only', () {
    final state = AppInitState.fromBootstrapMap({
      'capability_limits': {'profile_edit_certified_only_enabled': true},
    });

    expect(
      profileEditRestrictionMessage(_authState(isCertifiedUser: false), state),
      profileEditCertifiedOnlyMessage,
    );
    expect(
      profileEditRestrictionMessage(_authState(isCertifiedUser: true), state),
      isNull,
    );
  });
}
