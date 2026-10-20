import 'package:enterprise_pos/widgets/workspace_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required void Function(BuildContext) onOpen, bool withHost = true}) {
  final content = Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        onPressed: () => onOpen(context),
        child: const Text('open'),
      ),
    ),
  );
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          const SizedBox(width: 80, child: Text('SIDEBAR')),
          Expanded(
            child: withHost ? WorkspacePageHost(child: content) : content,
          ),
        ],
      ),
    ),
  );
}

Widget _savePage(BuildContext ctx) => WorkspaceFormPage(
      title: const Text('Edit thing'),
      content: const Text('body'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save'),
        ),
      ],
    );

void main() {
  testWidgets('page opens beside the sidebar and returns its result', (tester) async {
    bool? result;
    var done = false;
    await tester.pumpWidget(_app(onOpen: (context) async {
      result = await PosWorkspacePages.open<bool>(context, builder: _savePage);
      done = true;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit thing'), findsOneWidget);
    expect(find.text('SIDEBAR'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(result, isTrue);
    expect(find.text('Edit thing'), findsNothing);
  });

  testWidgets('Back button closes the page with a null result', (tester) async {
    bool? result = true;
    var done = false;
    await tester.pumpWidget(_app(onOpen: (context) async {
      result = await PosWorkspacePages.open<bool>(context, builder: _savePage);
      done = true;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(result, isNull);
    expect(find.text('Edit thing'), findsNothing);
  });

  testWidgets('closeAll dismisses open pages', (tester) async {
    var done = false;
    await tester.pumpWidget(_app(onOpen: (context) async {
      await PosWorkspacePages.open<bool>(context, builder: _savePage);
      done = true;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit thing'), findsOneWidget);

    PosWorkspacePages.closeAll();
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(find.text('Edit thing'), findsNothing);
  });

  testWidgets('without a shell it falls back to a full-screen route', (tester) async {
    bool? result;
    await tester.pumpWidget(_app(
      withHost: false,
      onOpen: (context) async {
        result = await PosWorkspacePages.open<bool>(context, builder: _savePage);
      },
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Edit thing'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
