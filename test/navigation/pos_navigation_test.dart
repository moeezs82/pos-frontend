import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enterprise_pos/services/app_navigator.dart';

/// Simple named module screens for the stack assertions.
class _ScreenA extends StatelessWidget {
  const _ScreenA();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('A')));
}

class _ScreenB extends StatelessWidget {
  const _ScreenB();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('B')));
}

Widget _app() => MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [posNavObserver],
      home: const Scaffold(body: Center(child: Text('Home'))),
    );

void main() {
  setUp(posNavObserver.reset);

  testWidgets('opens one instance, returns to it instead of duplicating',
      (tester) async {
    await tester.pumpWidget(_app());

    // Open A (module) — pushes a new route.
    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);

    // Open B above A.
    PosNavigation.openSingleton(routeId: '/b', builder: (_) => const _ScreenB());
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);

    // Re-invoking A must REVEAL the existing A (pop B), not push a 2nd A.
    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    expect(posNavObserver.isTop('/a'), isTrue);
    expect(posNavObserver.routeFor('/b'), isNull);
  });

  testWidgets('re-invoking the visible target does nothing (no duplicate)',
      (tester) async {
    await tester.pumpWidget(_app());

    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    await tester.pumpAndSettle();

    // Press again while A is on top — should be a no-op.
    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    await tester.pumpAndSettle();

    // One back reaches Home (proving there was only ever one A route).
    final nav = appNavigatorKey.currentState!;
    expect(nav.canPop(), isTrue);
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('rapid repeats push only one route', (tester) async {
    await tester.pumpWidget(_app());

    // Fire several times before pumping — the in-flight guard must dedupe.
    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    PosNavigation.openSingleton(routeId: '/a', builder: (_) => const _ScreenA());
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    final nav = appNavigatorKey.currentState!;
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget); // only one A existed
  });
}
