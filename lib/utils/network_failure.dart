import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// True when [e] indicates the app simply couldn't reach the backend
/// (Wi-Fi down, backend down, DNS issue, connection refused, timeout —
/// "anything", per the handover doc) as opposed to a real validation error
/// like HTTP 422, which surfaces through ApiClient as a plain [Exception]
/// carrying the server's message and should still reach the cashier
/// normally so they can fix the actual problem.
bool isNetworkFailure(Object e) {
  return e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException ||
      e is HandshakeException;
}
