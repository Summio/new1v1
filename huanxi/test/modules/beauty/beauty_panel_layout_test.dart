import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:huanxi/modules/beauty/beauty_panel.dart';

void main() {
  testWidgets('BeautyPanel should not overflow on compact height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 260,
                child: BeautyPanel(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
