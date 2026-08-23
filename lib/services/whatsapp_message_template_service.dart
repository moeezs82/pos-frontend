/// Branch-configured WhatsApp invoice message templating.
///
/// The template is deliberately small and deterministic: CounterIQ only
/// substitutes documented placeholders and never executes user-provided text.
/// Missing values are removed safely, and balance lines can be suppressed by
/// policy even when the saved template still contains {{customer_balance}}.
class WhatsAppMessageTemplateService {
  WhatsAppMessageTemplateService._();

  static const String defaultTemplate = '''Thank you for your purchase.

Invoice: {{invoice_no}}
Total: {{invoice_amount}} {{currency}}

Your invoice is attached as {{attachment_format}}.''';

  static const List<WhatsAppMessageField> supportedFields = [
    WhatsAppMessageField('Customer name', 'customer_name'),
    WhatsAppMessageField('Customer code', 'customer_code'),
    WhatsAppMessageField('Invoice number', 'invoice_no'),
    WhatsAppMessageField('Invoice amount', 'invoice_amount'),
    WhatsAppMessageField('Amount paid', 'amount_paid'),
    WhatsAppMessageField('Invoice balance', 'invoice_balance'),
    WhatsAppMessageField('Customer balance', 'customer_balance'),
    WhatsAppMessageField('Business name', 'business_name'),
    WhatsAppMessageField('Date', 'date'),
    WhatsAppMessageField('Currency', 'currency'),
    WhatsAppMessageField('Attachment format', 'attachment_format'),
  ];

  static String render({
    required String template,
    required Map<String, String> values,
    required bool showCustomerBalance,
  }) {
    final source = template.trim().isEmpty ? defaultTemplate : template;
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final placeholder = RegExp(r'\{\{\s*([a-zA-Z0-9_]+)\s*\}\}');
    final output = <String>[];

    for (final rawLine in normalized.split('\n')) {
      final matches = placeholder.allMatches(rawLine).toList(growable: false);
      final keys = matches
          .map((m) => (m.group(1) ?? '').trim())
          .where((key) => key.isNotEmpty)
          .toList(growable: false);

      // Customer balance is a branch privacy choice. Suppress the entire line
      // rather than leaving labels such as "Balance:" behind.
      if (!showCustomerBalance && keys.contains('customer_balance')) {
        continue;
      }

      var hasNonEmptyDynamicValue = false;
      var line = rawLine.replaceAllMapped(placeholder, (match) {
        final key = (match.group(1) ?? '').trim();
        final value = values[key]?.trim() ?? '';
        if (value.isNotEmpty) hasNonEmptyDynamicValue = true;
        return value;
      });

      // If a line was purely describing unavailable dynamic data, remove it.
      // Example: "Customer Code: {{customer_code}}" for a walk-in customer.
      if (keys.isNotEmpty && !hasNonEmptyDynamicValue) {
        continue;
      }

      line = line.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      if (line.isEmpty) {
        if (output.isNotEmpty && output.last.isNotEmpty) output.add('');
        continue;
      }
      output.add(line);
    }

    while (output.isNotEmpty && output.first.isEmpty) {
      output.removeAt(0);
    }
    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }

    return output.join('\n');
  }
}

class WhatsAppMessageField {
  final String label;
  final String key;

  const WhatsAppMessageField(this.label, this.key);

  String get placeholder => '{{${key}}}';
}
