import 'package:enterprise_pos/widgets/credit_limit_override_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'credit-limit approval keeps field resources alive through route dismissal',
    (tester) async {
      String? result;
      final issue = CreditLimitIssue(
        partyType: 'customer',
        partyId: 7,
        limit: 150,
        balanceBefore: 100,
        projectedBalance: 600,
        exceededBy: 450,
        mode: 'block',
        canOverride: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCreditLimitOverrideDialog(context, issue);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Approved after manager review',
      );
      await tester.tap(find.text('Approve Override'));

      // The dialog result completes before its reverse transition necessarily
      // finishes. Pump that intermediate state to catch premature controller
      // or focus-node disposal during route deactivation.
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result, 'Approved after manager review');
    },
  );

  testWidgets(
    'offline credit approval closes cleanly through route dismissal',
    (tester) async {
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showOfflineCreditDataOverrideDialog(
                    context,
                    message: 'Cached balance is unavailable.',
                  );
                },
                child: const Text('Open offline'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open offline'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Approved while backend was unreachable',
      );
      await tester.tap(find.text('Approve Offline Credit'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result, 'Approved while backend was unreachable');
    },
  );
}
