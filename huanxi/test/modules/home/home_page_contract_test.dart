import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home keeps PageView mounted while category data is loading', () {
    final text = File('lib/modules/home/home_page.dart').readAsStringSync();
    final expandedStart = text.indexOf('// 认证用户列表 - PageView 支持左右滑动');
    final pageViewStart = text.indexOf('PageView.builder', expandedStart);
    final firstLoadingBeforePageView = text.indexOf(
      'StatusView.loading(message:',
      expandedStart,
    );

    expect(pageViewStart, greaterThan(expandedStart));
    expect(
      firstLoadingBeforePageView == -1 ||
          firstLoadingBeforePageView > pageViewStart,
      isTrue,
    );
  });

  test('home uses one category selection path for tap and page swipe', () {
    final text = File('lib/modules/home/home_page.dart').readAsStringSync();

    expect(text, contains('void _selectCategory('));
    expect(text, contains('_selectCategory(index, animatePage: false)'));
    expect(text, contains('_selectCategory(index, animatePage: true)'));
  });

  test('home aligns provider section before initial certified user refresh', () {
    final text = File('lib/modules/home/home_page.dart').readAsStringSync();

    expect(text, contains('notifier.setSection(_sectionForIndex(_currentIndex));'));
    expect(text, contains('notifier.fetchCertifiedUsers(refresh: true);'));
  });

  test(
    'home uses lightweight fade transitions for category and cover loading',
    () {
      final text = File('lib/modules/home/home_page.dart').readAsStringSync();

      expect(text, contains('AnimatedSwitcher'));
      expect(text, contains('FadeInImage.memoryNetwork'));
      expect(text, contains('fadeInDuration:'));
      expect(text, contains('fadeOutDuration:'));
      expect(text, isNot(contains('fadeOutDuration: Duration.zero')));
      expect(text, isNot(contains('ImageFilter.blur')));
      expect(text, isNot(contains('ScaleTransition')));
    },
  );

  test('home does not render stale certified users on inactive category pages', () {
    final text = File('lib/modules/home/home_page.dart').readAsStringSync();

    expect(text, contains('final expectedSection = _sectionForIndex(widget.pageIndex);'));
    expect(
      text,
      contains(
        'final isCurrentSection = certifiedUserState.section == expectedSection;',
      ),
    );
    expect(text, contains('if (!isCurrentSection)'));
  });

  test('home gives certified user cards and cover images stable identity', () {
    final text = File('lib/modules/home/home_page.dart').readAsStringSync();

    expect(text, contains('certified_user_card_\${certifiedUser.userId}_'));
    expect(text, contains('certified_user_cover_\${certifiedUser.userId}_\$coverUrl'));
  });

  test('certified user refresh clears stale entries before loading new section data', () {
    final text = File('lib/app/providers/certified_user_provider.dart').readAsStringSync();

    expect(text, contains('if (state.isLoading && !refresh) return;'));
    expect(
      text,
      contains('certifiedUsers: refresh ? const [] : state.certifiedUsers'),
    );
  });

  test('certified user provider ignores stale in-flight responses', () {
    final text = File('lib/app/providers/certified_user_provider.dart').readAsStringSync();

    expect(text, contains('int _requestSerial = 0;'));
    expect(text, contains('final requestId = ++_requestSerial;'));
    expect(text, contains('final requestSection = state.section;'));
    expect(text, contains('if (requestId != _requestSerial || state.section != requestSection)'));
    expect(text, contains("'section': requestSection"));
  });
}
