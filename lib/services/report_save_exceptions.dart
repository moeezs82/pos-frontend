/// Thrown when the user cancels the native "Save As" dialog during a
/// report/export save. Callers should treat this as a silent no-op rather
/// than an error.
class ReportSaveCancelledException implements Exception {
  const ReportSaveCancelledException();

  @override
  String toString() => 'Save cancelled by the user.';
}
