import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/constants/app_constants.dart';

void main() {
  group('AppConstants.apiBaseUrl', () {
    test('requires explicit API_BASE_URL configuration', () {
      expect(() => AppConstants.apiBaseUrl, throwsA(isA<StateError>()));
    });

    test('error message explains dart-define configuration', () {
      expect(
        () => AppConstants.apiBaseUrl,
        throwsA(
          predicate<StateError>(
            (error) => error.message.contains('--dart-define=API_BASE_URL='),
          ),
        ),
      );
    });
  });
}
