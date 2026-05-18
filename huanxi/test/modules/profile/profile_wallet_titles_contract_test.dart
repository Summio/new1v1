import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recharge and withdraw app bar titles use dynamic token names', () {
    final rechargePage = File(
      'lib/modules/profile/recharge_page.dart',
    ).readAsStringSync();
    final withdrawPage = File(
      'lib/modules/profile/withdraw_page.dart',
    ).readAsStringSync();

    expect(rechargePage, contains("title: Text('\${tokenNames.coinName}充值')"));
    expect(rechargePage, isNot(contains("title: const Text('充值')")));

    expect(withdrawPage, contains('_appBar(tokenNames.diamondName)'));
    expect(withdrawPage, contains("Text('\$diamondName提现')"));
    expect(withdrawPage, isNot(contains("title: const Text('钻石提现')")));
  });
}
