import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/wallet_provider.dart';

void main() {
  group('TransactionRecord.fromJson', () {
    test('parses id from int and amount from string', () {
      final record = TransactionRecord.fromJson({
        'id': 123,
        'type': 'gift',
        'title': '礼物收入',
        'amount': '88',
        'is_income': true,
        'created_at': '2026-01-01 10:00:00',
      });

      expect(record.id, '123');
      expect(record.amount, 88);
      expect(record.isIncome, isTrue);
    });
  });
}
