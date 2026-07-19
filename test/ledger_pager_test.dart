import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enterprise_pos/widgets/ledger_pager.dart';

/// Behavioural tests for the shared jump-to-page control used on every ledger
/// surface. Validates boundary disabling, direct jump, and invalid-input
/// handling without touching the network.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int page,
    required int lastPage,
    int total = 100,
    bool loading = false,
    required void Function(int) onGo,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LedgerPager(
          page: page,
          lastPage: lastPage,
          total: total,
          loading: loading,
          onGoToPage: onGo,
        ),
      ),
    ));
  }

  testWidgets('shows Page X of Y', (tester) async {
    await pump(tester, page: 3, lastPage: 7, onGo: (_) {});
    expect(find.textContaining('Page 3 of 7'), findsOneWidget);
  });

  testWidgets('Previous disabled on first page, Next disabled on last', (tester) async {
    final taps = <int>[];
    await pump(tester, page: 1, lastPage: 3, onGo: taps.add);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
    await tester.pump();
    expect(taps, isEmpty); // disabled, no callback

    await pump(tester, page: 3, lastPage: 3, onGo: taps.add);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();
    expect(taps, isEmpty);
  });

  testWidgets('Next / Previous move by one', (tester) async {
    final taps = <int>[];
    await pump(tester, page: 2, lastPage: 5, onGo: taps.add);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
    await tester.pump();
    expect(taps, [3, 1]);
  });

  testWidgets('jump input clamps above-range to last page', (tester) async {
    final taps = <int>[];
    await pump(tester, page: 1, lastPage: 5, onGo: taps.add);
    await tester.enterText(find.byType(TextField), '99');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(taps, [5]); // clamped to lastPage
  });

  testWidgets('jump to a valid middle page works', (tester) async {
    final taps = <int>[];
    await pump(tester, page: 1, lastPage: 9, onGo: taps.add);
    await tester.enterText(find.byType(TextField), '4');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(taps, [4]);
  });

  testWidgets('jumping to the current page is a no-op', (tester) async {
    final taps = <int>[];
    await pump(tester, page: 3, lastPage: 9, onGo: taps.add);
    await tester.enterText(find.byType(TextField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(taps, isEmpty);
  });

  testWidgets('loading disables navigation callbacks', (tester) async {
    final taps = <int>[];
    await pump(tester, page: 2, lastPage: 5, loading: true, onGo: taps.add);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();
    expect(taps, isEmpty);
  });
}
