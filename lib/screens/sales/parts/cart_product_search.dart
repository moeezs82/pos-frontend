import 'package:enterprise_pos/screens/sales/parts/create_sale_items_section.dart';
import 'dart:async' show Timer;
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/services/app_currency.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Overlay-based product search dropdown for the cart.
/// Adds product to cart on selection.
class CartProductSearch extends StatefulWidget {
  final FocusNode focusNode;
  final TextEditingController controller;
  final Future<List<ProductRef>> Function(String q) onQuery;
  final void Function(ProductRef ref) onSelected;

  /// Scanner support: called with the typed text when Enter is pressed on a
  /// single code-like token. Return true when it was a barcode and the product
  /// was added to the cart.
  final Future<bool> Function(String code)? onSubmitText;

  const CartProductSearch({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.onQuery,
    required this.onSelected,
    this.onSubmitText,
  });

  @override
  State<CartProductSearch> createState() => _CartProductSearchState();
}

class _CartProductSearchState extends State<CartProductSearch> {
  final LayerLink _layerLink = LayerLink();

  /// Binds the field and its dropdown into one tap region so a click on the
  /// dropdown is not treated as a tap outside this widget.
  final Object _tapGroup = Object();
  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  List<ProductRef> _suggestions = [];
  int _highlightIndex = -1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _onTextChanged() {
    final q = widget.controller.text.trim();
    if (q.isEmpty) {
      _debounce?.cancel();
      _removeOverlay();
      if (mounted) {
        setState(() {
          _suggestions = [];
          _highlightIndex = -1;
          _loading = false;
        });
      }
      return;
    }
    // Show loading immediately, debounce the actual fetch.
    if (mounted) setState(() => _loading = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final results = await widget.onQuery(q);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _highlightIndex = results.isNotEmpty ? 0 : -1;
      _loading = false;
    });
    if (results.isEmpty) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    // Refresh in place rather than tearing down and re-inserting: destroying
    // the entry mid-gesture cancels a click that is already in progress.
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: (_) => _buildDropdown());
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Scanner flow: a scanner types the code and presses Enter before any
  /// suggestion can load. Try the code as a barcode first; if it is not one,
  /// fall back to the normal Enter behaviour.
  Future<void> _submitScanCode(String code) async {
    _debounce?.cancel();
    final fallback = (_highlightIndex >= 0 && _highlightIndex < _suggestions.length)
        ? _suggestions[_highlightIndex]
        : null;
    // Clear immediately so an instant second scan starts from an empty field.
    widget.controller.clear();
    _removeOverlay();
    var handled = false;
    try {
      handled = await widget.onSubmitText!(code);
    } catch (_) {
      handled = false;
    }
    if (!mounted) return;
    setState(() {
      _suggestions = [];
      _highlightIndex = -1;
      _loading = false;
    });
    if (!handled) {
      if (fallback != null) {
        widget.onSelected(fallback);
      } else if (widget.controller.text.isEmpty) {
        widget.controller.text = code;
        widget.controller.selection =
            TextSelection.collapsed(offset: code.length);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  void _selectIndex(int i) {
    if (i < 0 || i >= _suggestions.length) return;
    final ref = _suggestions[i];
    widget.controller.clear();
    _removeOverlay();
    setState(() {
      _suggestions = [];
      _highlightIndex = -1;
    });
    widget.onSelected(ref);
  }

  void _moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      _highlightIndex =
          (_highlightIndex + delta).clamp(0, _suggestions.length - 1);
    });
    _overlayEntry?.markNeedsBuild();
  }

  Widget _buildDropdown() {
    // TextFieldTapRegion == TapRegion(groupId: EditableText). On desktop,
    // EditableText's default onTapOutside unfocuses the field on pointer-DOWN
    // for any tap outside its own group. This dropdown lives in the root
    // Overlay, so it counted as "outside": the field blurred, _onFocusChanged
    // tore the overlay down, and the tap died before pointer-UP reached the
    // row — which is why only Enter could select. Joining the EditableText
    // group is the only thing that prevents that blur. The inner TapRegion
    // keeps our own outside-tap dismissal working.
    return TextFieldTapRegion(
      child: TapRegion(
        groupId: _tapGroup,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 38),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 420,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (ctx, i) {
                      final ref = _suggestions[i];
                      final highlighted = i == _highlightIndex;
                      final sub = [
                        if (ref.sku != null && ref.sku!.isNotEmpty)
                          'SKU: ${ref.sku}',
                        if (ref.barcode != null && ref.barcode!.isNotEmpty)
                          ref.barcode!,
                      ].join('  ');
                      return GestureDetector(
                        onTap: () => _selectIndex(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: highlighted
                                ? AppTheme.primarySoft
                                : Colors.transparent,
                            border: const Border(
                              bottom: BorderSide(color: AppTheme.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ref.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: highlighted
                                            ? AppTheme.primary
                                            : AppTheme.navy,
                                      ),
                                    ),
                                    if (sub.isNotEmpty)
                                      Text(
                                        sub,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    AppCurrency.format(ref.tp),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                  if (ref.stock != null)
                                    Text(
                                      'Stock: ${ref.stock!.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) => _removeOverlay(),
      child: CompositedTransformTarget(
        link: _layerLink,
        // Focus wraps the TextField so onKeyEvent fires while the TextField has focus.
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _moveHighlight(1);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _moveHighlight(-1);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              if (event is KeyDownEvent) {
                final code = widget.controller.text.trim();
                if (widget.onSubmitText != null &&
                    code.length >= 3 &&
                    !RegExp(r'\s').hasMatch(code)) {
                  _submitScanCode(code);
                  return KeyEventResult.handled;
                }
              }
              if (_highlightIndex >= 0) {
                _selectIndex(_highlightIndex);
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              _removeOverlay();
              setState(() {
                _suggestions = [];
                _highlightIndex = -1;
              });
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              decoration: InputDecoration(
                hintText: 'Search product… (name / SKU / barcode)',
                prefixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      )
                    : const Icon(Icons.search, size: 16),
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          widget.controller.clear();
                          _removeOverlay();
                          setState(() {
                            _suggestions = [];
                            _highlightIndex = -1;
                          });
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: AppTheme.surfaceSoft,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
