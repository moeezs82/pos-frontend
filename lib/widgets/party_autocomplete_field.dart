import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:enterprise_pos/theme/app_theme.dart';

/// A fast, instant-suggestion text field for picking a party (customer,
/// vendor, salesman, delivery boy, product — anything that's a list of maps
/// with an id/name).
///
/// Why this exists: opening a full bottom sheet, waiting for a network
/// round trip, and tapping a row is far too slow for a counter sale where
/// staff just want to type 2-3 letters and hit Enter/tap the first match.
/// This widget:
///   - Filters an already-cached in-memory list instantly on every keystroke
///     (zero network wait for the common case).
///   - Optionally also calls a network search (debounced) in the background
///     to surface matches outside the cached page, merging results in
///     without ever blocking typing or showing a spinner over the field.
///   - Always keeps a "Browse all" trailing action so anyone who prefers
///     scrolling a full list (instead of typing) still has that option —
///     it opens the exact same picker sheet as before.
class PartyAutocompleteField<T> extends StatefulWidget {
  /// Current cached items to filter locally, instantly.
  final List<T> Function() getCachedItems;

  /// Pulls a human-searchable label out of an item (name, etc).
  final String Function(T) labelOf;

  /// Optional secondary text shown under each suggestion (phone/email/etc).
  final String Function(T)? subtitleOf;

  /// Optional trailing widget per suggestion row (e.g. balance chip).
  final Widget Function(T)? trailingOf;

  /// Called when the network should be asked for fresh matches for [query]
  /// (debounced internally). Should resolve quickly; result is merged into
  /// the suggestion list by id when it lands. Optional — if null, this
  /// field is purely local-cache-filtered.
  final Future<List<T>> Function(String query)? onSearchRemote;

  /// Stable id extractor, used to de-dupe local + remote results.
  final String Function(T) idOf;

  /// Called when the user picks an item from the dropdown or presses Enter
  /// on the top suggestion.
  final void Function(T item) onSelected;

  /// Called when the user taps "Clear" / the explicit "no party" option.
  final VoidCallback? onCleared;

  /// Opens the full browsable picker sheet (old behavior) as a fallback.
  /// Returning null means "no selection / clear"; a non-null map is treated
  /// like onSelected.
  final Future<T?> Function() onBrowseAll;

  final String hintText;
  final String label;

  /// Text to show in the field when something is already selected.
  final String? selectedLabel;
  final String? selectedSubtitle;
  final VoidCallback? onSelectedTap;

  final bool enabled;
  final bool allowClear;

  const PartyAutocompleteField({
    super.key,
    required this.getCachedItems,
    required this.labelOf,
    required this.idOf,
    required this.onSelected,
    required this.onBrowseAll,
    this.subtitleOf,
    this.trailingOf,
    this.onSearchRemote,
    this.onCleared,
    this.hintText = 'Type to search…',
    this.label = '',
    this.selectedLabel,
    this.selectedSubtitle,
    this.onSelectedTap,
    this.enabled = true,
    this.allowClear = true,
  });

  @override
  State<PartyAutocompleteField<T>> createState() =>
      _PartyAutocompleteFieldState<T>();
}

class _PartyAutocompleteFieldState<T> extends State<PartyAutocompleteField<T>> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _debounce;

  List<T> _suggestions = [];
  int _highlightedIndex = -1;
  bool _remoteSearching = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _runLocalFilter(_controller.text);
    } else {
      // Slight delay so a tap on a suggestion (which also briefly steals
      // focus) isn't cancelled by the field losing focus first.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || !_focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _runLocalFilter(String query) {
    final q = query.trim().toLowerCase();
    final all = widget.getCachedItems();

    List<T> matches;
    if (q.isEmpty) {
      matches = all.take(25).toList();
    } else {
      matches = all
          .where((item) => widget.labelOf(item).toLowerCase().contains(q))
          .take(25)
          .toList();
    }

    setState(() {
      _suggestions = matches;
      _highlightedIndex = matches.isNotEmpty ? 0 : -1;
    });
    _showOverlay();

    if (widget.onSearchRemote != null && q.isNotEmpty) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _runRemoteSearch(q);
      });
    }
  }

  Future<void> _runRemoteSearch(String query) async {
    if (!mounted) return;
    setState(() => _remoteSearching = true);
    try {
      final remote = await widget.onSearchRemote!(query);
      if (!mounted || _controller.text.trim().toLowerCase() != query) return;

      // Merge remote results into local matches, de-duped by id, remote
      // items appended after local so already-visible rows don't jump.
      final seen = _suggestions.map(widget.idOf).toSet();
      final merged = [..._suggestions];
      for (final r in remote) {
        if (seen.add(widget.idOf(r))) merged.add(r);
      }

      setState(() {
        _suggestions = merged.take(30).toList();
        if (_highlightedIndex == -1 && _suggestions.isNotEmpty) {
          _highlightedIndex = 0;
        }
      });
      _showOverlay();
    } catch (_) {
      // Silent — local suggestions still stand; network search is a bonus,
      // not a requirement, for instant feel.
    } finally {
      if (mounted) setState(() => _remoteSearching = false);
    }
  }

  void _showOverlay() {
    _removeOverlay();
    if (!_focusNode.hasFocus) return;

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 48),
            child: SizedBox(
              width: _fieldWidth,
              child: _SuggestionsPanel<T>(
                suggestions: _suggestions,
                highlightedIndex: _highlightedIndex,
                labelOf: widget.labelOf,
                subtitleOf: widget.subtitleOf,
                trailingOf: widget.trailingOf,
                searching: _remoteSearching,
                query: _controller.text,
                onTap: (item) {
                  _select(item);
                },
                onBrowseAll: () async {
                  _focusNode.unfocus();
                  _removeOverlay();
                  final picked = await widget.onBrowseAll();
                  if (picked != null) {
                    widget.onSelected(picked);
                    _controller.clear();
                  } else {
                    widget.onCleared?.call();
                  }
                },
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _select(T item) {
    widget.onSelected(item);
    _controller.clear();
    _focusNode.unfocus();
    _removeOverlay();
  }

  double get _fieldWidth {
    final box = context.findRenderObject() as RenderBox?;
    return box?.size.width ?? 280;
  }

  void _handleSubmitted(String _) {
    if (_highlightedIndex >= 0 && _highlightedIndex < _suggestions.length) {
      _select(_suggestions[_highlightedIndex]);
    }
  }

  void _moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      _highlightedIndex =
          (_highlightedIndex + delta).clamp(0, _suggestions.length - 1);
    });
    _showOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.selectedLabel != null && widget.selectedLabel!.isNotEmpty;

    if (hasSelection) {
      return _SelectedChipField<T>(
        label: widget.selectedLabel!,
        subtitle: widget.selectedSubtitle,
        fieldLabel: widget.label,
        enabled: widget.enabled,
        allowClear: widget.allowClear,
        onTap: widget.onSelectedTap,
        onClear: widget.onCleared,
        onBrowseAll: widget.onBrowseAll,
        onSelected: widget.onSelected,
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveHighlight(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveHighlight(-1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          onChanged: _runLocalFilter,
          onSubmitted: _handleSubmitted,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label.isNotEmpty ? widget.label : null,
            hintText: widget.hintText,
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              tooltip: 'Browse all',
              icon: const Icon(Icons.list_alt_rounded, size: 20),
              onPressed: () async {
                _focusNode.unfocus();
                _removeOverlay();
                final picked = await widget.onBrowseAll();
                if (picked != null) {
                  widget.onSelected(picked);
                  _controller.clear();
                } else {
                  widget.onCleared?.call();
                }
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.border),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _SuggestionsPanel<T> extends StatelessWidget {
  final List<T> suggestions;
  final int highlightedIndex;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final Widget Function(T)? trailingOf;
  final bool searching;
  final String query;
  final void Function(T) onTap;
  final VoidCallback onBrowseAll;

  const _SuggestionsPanel({
    required this.suggestions,
    required this.highlightedIndex,
    required this.labelOf,
    required this.onTap,
    required this.onBrowseAll,
    required this.query,
    this.subtitleOf,
    this.trailingOf,
    this.searching = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (searching)
              const LinearProgressIndicator(minHeight: 2),
            if (suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                child: Text(
                  query.trim().isEmpty
                      ? 'Start typing to search…'
                      : (searching ? 'Searching…' : 'No matches found.'),
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = suggestions[i];
                    final selected = i == highlightedIndex;
                    return InkWell(
                      onTap: () => onTap(item),
                      child: Container(
                        color: selected ? AppTheme.primarySoft : null,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    labelOf(item),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                  ),
                                  if (subtitleOf != null && subtitleOf!(item).isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        subtitleOf!(item),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (trailingOf != null) trailingOf!(item),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            InkWell(
              onTap: onBrowseAll,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.list_alt_rounded, size: 16, color: AppTheme.primary),
                    SizedBox(width: 8),
                    Text(
                      'Browse full list…',
                      style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "pill" shown once something is selected — name + quick clear +
/// tap-to-change (re-opens browse-all by default, matching old tap-to-pick
/// behavior on the field).
class _SelectedChipField<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String fieldLabel;
  final bool enabled;
  final bool allowClear;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final Future<T?> Function() onBrowseAll;
  final void Function(T) onSelected;

  const _SelectedChipField({
    required this.label,
    required this.fieldLabel,
    required this.onBrowseAll,
    required this.onSelected,
    this.subtitle,
    this.enabled = true,
    this.allowClear = true,
    this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled
          ? (onTap ??
              () async {
                final picked = await onBrowseAll();
                if (picked != null) {
                  onSelected(picked);
                } else {
                  onClear?.call();
                }
              })
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
          color: AppTheme.surfaceSoft,
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: AppTheme.success),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fieldLabel.isNotEmpty)
                    Text(fieldLabel, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                ],
              ),
            ),
            if (allowClear)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: enabled ? onClear : null,
              ),
          ],
        ),
      ),
    );
  }
}
