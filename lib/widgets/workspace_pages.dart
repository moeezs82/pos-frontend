import 'dart:async';

import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens form/detail "pages" that used to be dialogs.
///
/// When called from a screen that lives inside the persistent desktop shell
/// (sidebar + top bar), the page is rendered inside the shell's content area so
/// the sidebar stays visible. Each page runs inside its own small nested
/// [Navigator], so existing widgets keep using `Navigator.pop(context, result)`
/// to return a value exactly like they did as dialogs.
///
/// When there is no shell above [context] (a screen pushed on the root
/// navigator) it falls back to a normal full-screen route.
abstract final class PosWorkspacePages {
  static final Set<WorkspacePageHostState> _hosts = <WorkspacePageHostState>{};

  /// Closes every open in-workspace page (their futures complete with null).
  /// Used when the sidebar is clicked on the module that is already active.
  static void closeAll() {
    for (final host in List<WorkspacePageHostState>.of(_hosts)) {
      host.closeAllPages();
    }
  }

  static Future<T?> open<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    final host = context.findAncestorStateOfType<WorkspacePageHostState>();
    if (host != null) return host.push<T>(builder);
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(builder: builder),
    );
  }
}

class _PageEntry {
  _PageEntry(this.id, this.route, this.completer);

  final int id;
  final Route<dynamic> route;
  final Completer<dynamic> completer;
  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
}

/// Wraps the shell's content area and stacks in-workspace pages on top of it.
class WorkspacePageHost extends StatefulWidget {
  /// Changing this value (the active sidebar route) closes every open page.
  final Object? resetKey;
  final Widget child;

  const WorkspacePageHost({super.key, this.resetKey, required this.child});

  @override
  State<WorkspacePageHost> createState() => WorkspacePageHostState();
}

class WorkspacePageHostState extends State<WorkspacePageHost> {
  final List<_PageEntry> _entries = <_PageEntry>[];
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    PosWorkspacePages._hosts.add(this);
  }

  void closeAllPages() {
    if (_entries.isEmpty) return;
    final stale = List<_PageEntry>.of(_entries);
    _entries.clear();
    for (final entry in stale) {
      if (!entry.completer.isCompleted) entry.completer.complete(null);
    }
    if (mounted) setState(() {});
  }

  Future<T?> push<T>(WidgetBuilder builder) {
    final route = PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 140),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, _, __) => builder(context),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    final completer = Completer<dynamic>();
    final entry = _PageEntry(_nextId++, route, completer);
    setState(() => _entries.add(entry));
    route.popped.then((value) => _close(entry, value));
    return completer.future.then((value) => value as T?);
  }

  void _close(_PageEntry entry, [Object? result]) {
    if (!entry.completer.isCompleted) entry.completer.complete(result);
    if (!mounted) return;
    if (_entries.remove(entry)) setState(() {});
  }

  @override
  void didUpdateWidget(covariant WorkspacePageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey && _entries.isNotEmpty) {
      final stale = List<_PageEntry>.of(_entries);
      _entries.clear();
      for (final entry in stale) {
        if (!entry.completer.isCompleted) entry.completer.complete(null);
      }
    }
  }

  @override
  void dispose() {
    PosWorkspacePages._hosts.remove(this);
    for (final entry in _entries) {
      if (!entry.completer.isCompleted) entry.completer.complete(null);
    }
    _entries.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeFocus(
            excluding: _entries.isNotEmpty,
            child: widget.child,
          ),
        ),
        for (final entry in _entries)
          Positioned.fill(
            key: ValueKey<int>(entry.id),
            child: _PageLayer(entry: entry),
          ),
      ],
    );
  }
}

class _PageLayer extends StatelessWidget {
  final _PageEntry entry;
  const _PageLayer({required this.entry});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            entry.navKey.currentState?.maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: AppTheme.bg,
          // The app-level HeroController can only drive one Navigator.
          child: HeroControllerScope.none(
            child: Navigator(
              key: entry.navKey,
              onGenerateInitialRoutes: (_, __) => <Route<dynamic>>[
                // Placeholder base route so the real page can be popped with a
                // result without emptying this Navigator.
                PageRouteBuilder<void>(
                  opaque: false,
                  pageBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                entry.route,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Page version of an AlertDialog: header with Back, then a centered card with
/// [content] and right-aligned [actions]. The extra AlertDialog-style
/// parameters are accepted (and ignored) so a dialog can be converted by only
/// renaming the widget.
class WorkspaceFormPage extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final double maxWidth;

  // AlertDialog-compatible, intentionally unused.
  final Widget? icon;
  final bool scrollable;
  final EdgeInsetsGeometry? insetPadding;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final Color? surfaceTintColor;
  final MainAxisAlignment? actionsAlignment;

  const WorkspaceFormPage({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.maxWidth = 960,
    this.icon,
    this.scrollable = false,
    this.insetPadding,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
    this.shape,
    this.backgroundColor,
    this.surfaceTintColor,
    this.actionsAlignment,
  });

  @override
  Widget build(BuildContext context) {
    final hasActions = actions != null && actions!.isNotEmpty;
    return Material(
      color: AppTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspacePageHeader(title: title),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  constraints: BoxConstraints(minWidth: 360, maxWidth: maxWidth),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (content != null)
                          DefaultTextStyle(
                            style: Theme.of(context).textTheme.bodyMedium ??
                                const TextStyle(),
                            child: content!,
                          ),
                        if (hasActions) ...[
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: actions!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page version of a custom `Dialog(child: ...)`. [child] fills the available
/// area below the header, so remove any fixed dialog width/height from it.
class WorkspaceDialogPage extends StatelessWidget {
  final Widget? title;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const WorkspaceDialogPage({
    super.key,
    this.title,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspacePageHeader(title: title, actions: actions),
          Expanded(child: Padding(padding: padding, child: child)),
        ],
      ),
    );
  }
}

/// Page version of a custom `Dialog(child: Container(...))` whose body is a
/// self-contained card (it usually draws its own title and close button).
///
/// [scrollable] true: the whole card scrolls (body must not use Expanded/
/// Flexible). false: the card gets the available height (body may use
/// Expanded/Flexible, e.g. a Column with `mainAxisSize: MainAxisSize.min`).
class WorkspaceCardPage extends StatelessWidget {
  final double maxWidth;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const WorkspaceCardPage({
    super.key,
    this.maxWidth = 900,
    this.scrollable = true,
    this.padding = const EdgeInsets.all(24),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: child,
    );
    return Material(
      color: AppTheme.bg,
      child: scrollable
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Align(alignment: Alignment.topCenter, child: card),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Align(alignment: Alignment.topCenter, child: card),
            ),
    );
  }
}

class WorkspacePageHeader extends StatelessWidget {
  final Widget? title;
  final List<Widget> actions;
  const WorkspacePageHeader({super.key, this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DefaultTextStyle(
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: title ?? const SizedBox.shrink(),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
