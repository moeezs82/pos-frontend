import 'package:flutter/material.dart';

/// Global navigation hooks used by app-wide keyboard shortcuts.
///
/// Keeping this in one file prevents passing BuildContext through every screen
/// and makes shortcut navigation work from dialogs, lists, and nested pages.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Stable route identities for the singleton module screens that global
/// shortcuts (and Home tiles) open. Using one central source lets navigation
/// recognise an already-open module and return to it instead of pushing a
/// duplicate. Anything NOT listed here (detail screens, pickers, dialogs)
/// keeps its normal anonymous-route behaviour.
abstract final class PosRouteIds {
  static const home = '/home';
  static const createSale = '/sales/create';
  static const sales = '/sales';
  static const createPurchase = '/purchases/create';
  static const purchases = '/purchases';
  static const registerShift = '/register-shift';
  static const products = '/products';
  static const stock = '/stock';
  static const customers = '/customers';
  static const customerCreate = '/customers/create';
  static const backupRestore = '/settings/backup-restore';
  static const offlineSync = '/sync/offline-sales';
  static const vendors = '/vendors';
  static const partyPayments = '/party-payments';
  static const cashLedger = '/cash-ledger';
  static const cashLedgerCreate = '/cash-ledger/create';
  static const expenseCreate = '/expenses/create';
  static const reports = '/reports';
  static const users = '/users';
  static const saleReturns = '/sale-returns';
  static const branchControl = '/branch-control';
}

/// Tracks the ACTUAL routes currently in the Navigator so navigation can ask
/// "is module X already open, and which Route object is it?". This stays correct
/// across push / pop / remove / replace — not a fragile boolean flag.
///
/// Dialogs / bottom sheets are routes too; they simply carry no [PosRouteIds]
/// name, so they never match a module id (and are popped through when we return
/// to a module below them, which is the intended behaviour).
class PosNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }

  /// Topmost route carrying [routeId], or null if that module isn't open.
  Route<dynamic>? routeFor(String routeId) {
    for (var i = _stack.length - 1; i >= 0; i--) {
      if (_stack[i].settings.name == routeId) return _stack[i];
    }
    return null;
  }

  /// Whether the current top-of-stack route is [routeId].
  bool isTop(String routeId) =>
      _stack.isNotEmpty && _stack.last.settings.name == routeId;

  /// Drop every tracked route. Called on logout so we never return focus to a
  /// route belonging to a previous session. The Navigator's own callbacks keep
  /// the list accurate afterwards.
  void reset() => _stack.clear();
}

/// The single observer instance. Register it in `MaterialApp.navigatorObservers`.
final PosNavigatorObserver posNavObserver = PosNavigatorObserver();

/// Open-or-focus navigation for singleton module screens.
class PosNavigation {
  PosNavigation._();

  /// Guards against key-repeat / rapid double taps pushing several routes
  /// before the observer records the first one. Keyed by route id.
  static final Set<String> _inFlight = <String>{};

  /// Reveal [routeId] if it already exists, otherwise push a fresh instance.
  ///
  /// - Already the top route  → do nothing (keep its state).
  /// - Exists lower in stack  → popUntil that exact route (reveals it with all
  ///   of its unfinished state intact).
  /// - Not in the stack       → push a new MaterialPageRoute named [routeId].
  ///
  /// The [builder] is lazy so a screen is only constructed when a push actually
  /// happens.
  static void openSingleton({
    required String routeId,
    required WidgetBuilder builder,
  }) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    // Already visible — nothing to do, and never rebuild/replace it.
    if (posNavObserver.isTop(routeId)) return;

    // Re-entrancy / key-repeat guard.
    if (_inFlight.contains(routeId)) return;
    _inFlight.add(routeId);

    try {
      final existing = posNavObserver.routeFor(routeId);
      if (existing != null) {
        // Reveal the existing route (and pop any dialogs/routes above it).
        nav.popUntil((r) => identical(r, existing));
      } else {
        nav.push(
          MaterialPageRoute(
            settings: RouteSettings(name: routeId),
            builder: builder,
          ),
        );
      }
    } finally {
      // Clear after this frame, by which point the observer has processed the
      // push/pop and isTop() reflects reality for the next key event.
      WidgetsBinding.instance.addPostFrameCallback((_) => _inFlight.remove(routeId));
    }
  }
}
