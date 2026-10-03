import 'package:enterprise_pos/services/whatsapp_invoice_service.dart';
import 'package:enterprise_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';

class PendingWhatsAppTask {
  final String id;
  final String receiptNo;
  final WhatsAppInvoicePreparation prepared;
  final String message;
  bool opening;

  PendingWhatsAppTask({
    required this.id,
    required this.receiptNo,
    required this.prepared,
    required this.message,
    this.opening = false,
  });
}

class SalePostTaskPanel extends StatelessWidget {
  final List<PendingWhatsAppTask> tasks;
  final ValueChanged<PendingWhatsAppTask> onOpenTask;
  final ValueChanged<PendingWhatsAppTask> onDismissTask;
  final ValueChanged<String>? onOpenFolder;

  const SalePostTaskPanel({
    super.key,
    required this.tasks,
    required this.onOpenTask,
    required this.onDismissTask,
    this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final visible = tasks.take(3).toList(growable: false);
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 250),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 7),
              child: Row(
                children: [
                  const Icon(Icons.chat_rounded, size: 17, color: Color(0xFF128C7E)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      tasks.length == 1
                          ? 'WhatsApp invoice ready'
                          : '${tasks.length} WhatsApp invoices ready',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                  if (tasks.length > 3)
                    Text(
                      '+${tasks.length - 3} more',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),
            ...visible.map(
              (task) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.receiptNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '+${task.prepared.normalizedPhone} • ${task.prepared.attachmentDescription}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: task.opening ? null : () => onOpenTask(task),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      ),
                      icon: task.opening
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new_rounded, size: 14),
                      label: const Text('Open', style: TextStyle(fontSize: 10.5)),
                    ),
                    IconButton(
                      tooltip: 'Open attachment folder',
                      visualDensity: VisualDensity.compact,
                      onPressed: task.opening
                          ? null
                          : () {
                              if (onOpenFolder != null) {
                                onOpenFolder!(task.prepared.primaryPath);
                              } else {
                                WhatsAppInvoiceService.instance
                                    .openInvoiceFolder(task.prepared.primaryPath);
                              }
                            },
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      visualDensity: VisualDensity.compact,
                      onPressed: task.opening ? null : () => onDismissTask(task),
                      icon: const Icon(Icons.close_rounded, size: 16),
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

class SalePostTaskManager {
  final List<PendingWhatsAppTask> tasks = [];
  int _sequence = 0;

  void addTask({
    required String receiptNo,
    required WhatsAppInvoicePreparation prepared,
    required String message,
  }) {
    tasks.insert(
      0,
      PendingWhatsAppTask(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
        receiptNo: receiptNo,
        prepared: prepared,
        message: message,
      ),
    );
    if (tasks.length > 8) {
      tasks.removeRange(8, tasks.length);
    }
  }

  Future<void> openTask(
    BuildContext context,
    PendingWhatsAppTask task, {
    required VoidCallback notify,
  }) async {
    if (task.opening) return;
    task.opening = true;
    notify();
    try {
      final copied = await WhatsAppInvoiceService.instance
          .copyFilesToClipboard(task.prepared.attachmentPaths);
      await WhatsAppInvoiceService.instance.openChat(
        phone: task.prepared.normalizedPhone,
        message: task.message,
      );
      if (copied) {
        tasks.removeWhere((t) => t.id == task.id);
      } else {
        task.opening = false;
      }
      notify();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            copied
                ? '${task.receiptNo}: WhatsApp opened. Press Ctrl+V, then Send.'
                : '${task.receiptNo}: WhatsApp opened. Clipboard copy failed; use the folder button on the ready task to attach the ${task.prepared.attachmentDescription}.',
          ),
        ),
      );
    } catch (e) {
      task.opening = false;
      notify();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open WhatsApp for ${task.receiptNo}: $e'),
        ),
      );
    }
  }

  void dismissTask(PendingWhatsAppTask task) {
    tasks.removeWhere((t) => t.id == task.id);
  }
}

