import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/call/call_room_page.dart';

void main() {
  test('call beauty sheet bounds should be inside screen and ordered', () {
    const screenHeight = 800.0;
    final minHeight = computeCallBeautySheetMinHeight(screenHeight);
    final maxHeight = computeCallBeautySheetMaxHeight(screenHeight);

    expect(minHeight, greaterThan(0));
    expect(minHeight, lessThan(maxHeight));
    expect(maxHeight, lessThan(screenHeight));
    expect(minHeight, 260.0);
    expect(maxHeight, 576.0);
  });

  test(
    'call room should not subscribe widgets to per-frame keyboard insets',
    () {
      final source = File(
        'lib/modules/call/call_room_page.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('MediaQuery.of(context)')));
      expect(source, isNot(contains('MediaQuery.viewInsetsOf(context)')));
    },
  );
}
