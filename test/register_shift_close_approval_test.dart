import 'package:enterprise_pos/api/register_shift_service.dart';
import 'package:enterprise_pos/providers/register_shift_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRegisterShiftService extends RegisterShiftService {
  _FakeRegisterShiftService() : super('test-token');

  Map<String, dynamic>? activePayload;
  Map<String, dynamic> closePayload = const {};
  Map<String, dynamic>? lastCloseBody;

  @override
  Future<Map<String, dynamic>?> active() async => activePayload;

  @override
  Future<Map<String, dynamic>> close(
    int id,
    Map<String, dynamic> body,
  ) async {
    lastCloseBody = Map<String, dynamic>.from(body);
    return Map<String, dynamic>.from(closePayload);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('cashier close keeps shift open when manager approval is required', () async {
    final service = _FakeRegisterShiftService();
    final pendingShift = <String, dynamic>{
      'id': 9,
      'status': 'open',
      'branch_id': 3,
      'close_request': <String, dynamic>{
        'id': 41,
        'status': 'pending',
        'expected_cash': 1000,
        'counted_cash': 200,
        'variance': -800,
      },
    };
    service.activePayload = <String, dynamic>{
      'shift': pendingShift,
      'summary': <String, dynamic>{'expected_cash': 1000},
      'activity': <String, dynamic>{'items': <Object>[]},
      'occupied_shifts': <Object>[],
    };
    service.closePayload = <String, dynamic>{
      'approval_required': true,
      'shift': pendingShift,
      'close_request': pendingShift['close_request'],
    };

    final provider = RegisterShiftProvider(serviceFactory: (_) => service);
    await provider.initialize('token', userId: '7', branchId: 3);

    final approvalRequired = await provider.close(
      countedCash: 200,
      pendingSyncCount: 0,
      note: 'Physical drawer count',
    );

    expect(approvalRequired, isTrue);
    expect(provider.hasActiveShift, isTrue);
    expect(provider.hasPendingCloseRequest, isTrue);
    expect(provider.closeRequest?['variance'], -800);
    expect(service.lastCloseBody?['accept_pending_sync'], isFalse);
  });

  test('successful normal close clears the active shift', () async {
    final service = _FakeRegisterShiftService();
    service.activePayload = <String, dynamic>{
      'shift': <String, dynamic>{'id': 9, 'status': 'open', 'branch_id': 3},
      'summary': <String, dynamic>{'expected_cash': 1000},
      'activity': <String, dynamic>{'items': <Object>[]},
      'occupied_shifts': <Object>[],
    };
    service.closePayload = <String, dynamic>{
      'id': 9,
      'status': 'closed',
      'counted_cash': 1000,
      'variance': 0,
    };

    final provider = RegisterShiftProvider(serviceFactory: (_) => service);
    await provider.initialize('token', userId: '7', branchId: 3);

    final approvalRequired = await provider.close(
      countedCash: 1000,
      pendingSyncCount: 0,
    );

    expect(approvalRequired, isFalse);
    expect(provider.hasActiveShift, isFalse);
    expect(provider.shift, isNull);
  });
}
