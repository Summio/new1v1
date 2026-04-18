import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/network/api_exception.dart';
import 'package:huanxi/core/utils/app_toast.dart';

void main() {
  group('AppToast.normalizeMessage', () {
    test('returns api exception message', () {
      const exception = ApiException(code: 400, message: '余额不足');
      expect(AppToast.normalizeMessage(exception), '余额不足');
    });

    test('removes Exception prefix from generic error', () {
      expect(AppToast.normalizeMessage(Exception('网络异常')), '网络异常');
    });

    test('returns fallback message when input text is blank', () {
      expect(AppToast.normalizeMessage('   '), '操作失败，请稍后重试');
    });
  });
}
