import 'package:flutter/material.dart';

class CBPagination extends StatelessWidget {
  final int currentPage;
  final int lastPage;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const CBPagination({
    super.key,
    required this.currentPage,
    required this.lastPage,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(onPressed: onPrev, child: const Text("Previous")),
          const SizedBox(width: 16),
          Text("Page $currentPage of $lastPage"),
          const SizedBox(width: 16),
          ElevatedButton(onPressed: onNext, child: const Text("Next")),
        ],
      ),
    );
  }
}
