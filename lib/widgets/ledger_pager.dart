import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:enterprise_pos/theme/app_theme.dart';

/// Shared pagination control for every party/account ledger surface.
///
/// Shows `Total N • Page X of Y`, First / Previous / Next / Last, and a
/// validated "go to page" input (integers only, clamped to 1..lastPage,
/// Enter navigates). A single [onGoToPage] callback handles every target so
/// each ledger screen wires it once. Boundary buttons and the input are
/// disabled while [loading] to prevent duplicate in-flight requests.
class LedgerPager extends StatefulWidget {
  const LedgerPager({
    super.key,
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onGoToPage,
    this.loading = false,
  });

  final int page;
  final int lastPage;
  final int total;
  final bool loading;
  final ValueChanged<int> onGoToPage;

  @override
  State<LedgerPager> createState() => _LedgerPagerState();
}

class _LedgerPagerState extends State<LedgerPager> {
  final _goCtrl = TextEditingController();
  final _goFocus = FocusNode();

  @override
  void dispose() {
    _goCtrl.dispose();
    _goFocus.dispose();
    super.dispose();
  }

  int get _last => widget.lastPage < 1 ? 1 : widget.lastPage;

  void _go(int target) {
    if (widget.loading) return;
    final clamped = target.clamp(1, _last);
    if (clamped == widget.page) return;
    widget.onGoToPage(clamped);
  }

  void _submitJump() {
    final raw = _goCtrl.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      _goCtrl.clear();
      return;
    }
    _goCtrl.clear();
    _goFocus.unfocus();
    _go(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page < 1 ? 1 : widget.page;
    final atFirst = page <= 1 || widget.loading;
    final atLast = page >= _last || widget.loading;
    final multiPage = _last > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.loading) ...[
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                'Total ${widget.total}  •  Page $page of $_last',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _navBtn(
                icon: Icons.first_page_rounded,
                tooltip: 'First page',
                onTap: atFirst ? null : () => _go(1),
              ),
              OutlinedButton.icon(
                onPressed: atFirst ? null : () => _go(page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Previous'),
              ),
              if (multiPage) _goToField(),
              FilledButton.icon(
                onPressed: atLast ? null : () => _go(page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Next'),
              ),
              _navBtn(
                icon: Icons.last_page_rounded,
                tooltip: 'Last page (latest)',
                onTap: atLast ? null : () => _go(_last),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navBtn({required IconData icon, required String tooltip, VoidCallback? onTap}) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.surfaceSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _goToField() {
    return SizedBox(
      width: 132,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 74,
            child: TextField(
              controller: _goCtrl,
              focusNode: _goFocus,
              enabled: !widget.loading,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submitJump(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Go to',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Go',
            onPressed: widget.loading ? null : _submitJump,
            icon: const Icon(Icons.subdirectory_arrow_left_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
