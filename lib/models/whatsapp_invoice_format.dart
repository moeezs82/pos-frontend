enum WhatsAppInvoiceFormat { pdf, jpg }

WhatsAppInvoiceFormat whatsAppInvoiceFormatFromValue(String? value) {
  return value?.toLowerCase() == 'jpg'
      ? WhatsAppInvoiceFormat.jpg
      : WhatsAppInvoiceFormat.pdf;
}

extension WhatsAppInvoiceFormatX on WhatsAppInvoiceFormat {
  String get value => this == WhatsAppInvoiceFormat.jpg ? 'jpg' : 'pdf';

  String get label => this == WhatsAppInvoiceFormat.jpg ? 'JPG' : 'PDF';
}
