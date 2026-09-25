import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/employee_directory.dart';
import '../models/scan_result.dart';

/// A request HRMS answered with an error (message is user-presentable).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// HRMS machine reason, when sent (e.g. no_face, not_recognized, geofence).
  final String? reason;

  ApiException(this.message, {this.statusCode, this.reason});

  @override
  String toString() => message;
}

/// The server could not be reached or did not answer in time.
class NetworkException extends ApiException {
  NetworkException(super.message);
}

/// The admin session (bearer token) is no longer valid — the UI must log out.
class SessionExpired implements Exception {
  final String message;
  SessionExpired([this.message = 'Your session has expired. Please sign in again.']);

  @override
  String toString() => message;
}

/// The face engine could not use the capture (no face / blurry / spoof) — retake it.
class NeedsLiveCapture implements Exception {
  final String message;
  NeedsLiveCapture(this.message);

  @override
  String toString() => message;
}

/// Result of `POST /auth/login`.
class LoginPayload {
  final String token;
  final Map<String, dynamic> user;

  LoginPayload({required this.token, required this.user});

  String get role => (user['role'] ?? '').toString().trim().toLowerCase();
  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'staff';
  String get name => (user['name'] ?? user['firstName'] ?? '').toString();
  String get email => (user['email'] ?? '').toString();
  String? get id => user['id']?.toString() ?? user['_id']?.toString();
  String? get adminId => user['adminId']?.toString();
}

class _Resp {
  final int status;
  final Map<String, dynamic> body;
  _Resp(this.status, this.body);

  bool get ok => status >= 200 && status < 300 && body['success'] != false;
  String? get reason => body['reason']?.toString();

  /// Consistent error extraction: `message`, then `detail`, then `error`.
  String message(String fallback) {
    for (final key in const ['message', 'detail', 'error']) {
      final v = body[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map && v['message'] is String && (v['message'] as String).trim().isNotEmpty) {
        return (v['message'] as String).trim();
      }
    }
    return fallback;
  }
}

/// All kiosk traffic goes to the HRMS backend ([kApiBase]).
class ApiService {
  /// Bearer token of the signed-in kiosk admin. Set by AppState on
  /// login / auto-login and cleared on logout.
  static String? authToken;

  static const Duration _defaultTimeout = Duration(seconds: 25);
  // The face engine may be cold on the first request, so scans/enrolls get longer.
  static const Duration _faceTimeout = Duration(seconds: 30);

  /// Shared HTTP helper: JSON in/out, timeout, network-error mapping and (for admin
  /// calls) 401 → [SessionExpired].
  static Future<_Resp> _send(
    String method,
    String path, {
    Object? body,
    String? token,
    bool adminAuth = true,
    Duration timeout = _defaultTimeout,
  }) async {
    final uri = Uri.parse('$kApiBase$path');
    final bearer = token ?? (adminAuth ? authToken : null);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (bearer != null && bearer.isNotEmpty) 'Authorization': 'Bearer $bearer',
    };

    http.Response res;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      final Future<http.Response> req;
      switch (method) {
        case 'GET':
          req = http.get(uri, headers: headers);
          break;
        case 'DELETE':
          req = http.delete(uri, headers: headers, body: encoded);
          break;
        default:
          req = http.post(uri, headers: headers, body: encoded);
      }
      res = await req.timeout(timeout);
    } on TimeoutException {
      throw NetworkException('The server took too long to respond. Please try again.');
    } catch (_) {
      throw NetworkException('Could not reach the server. Check your connection and try again.');
    }

    Map<String, dynamic> decoded;
    try {
      final d = jsonDecode(res.body);
      decoded = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{'data': d};
    } catch (_) {
      decoded = <String, dynamic>{};
    }

    final r = _Resp(res.statusCode, decoded);
    if (res.statusCode == 401 && adminAuth && token == null) {
      throw SessionExpired();
    }
    return r;
  }

  static String _dataUrl(String b64) =>
      b64.startsWith('data:') ? b64 : 'data:image/jpeg;base64,$b64';

  static Map<String, dynamic> _m(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static int? _i(dynamic v) => v is num ? v.toInt() : null;
  static num? _n(dynamic v) => v is num ? v : null;
  static String? _s(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  // ---------------------------------------------------------------- auth

  /// `POST /auth/login`. Throws [ApiException] with the server message on failure.
  /// Role checks are the caller's job.
  static Future<LoginPayload> login(String email, String password) async {
    final r = await _send(
      'POST',
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
      adminAuth: false,
    );
    final token = _s(r.body['token']);
    if (!r.ok || token == null) {
      throw ApiException(r.message('Incorrect email or password.'), statusCode: r.status);
    }
    return LoginPayload(token: token, user: _m(r.body['user']));
  }

  // ---------------------------------------------------------------- scan

  static const _legacyActions = {
    'in': 'punch_in',
    'out': 'punch_out',
    'break': 'break_start',
    'break_in': 'break_start',
    'break_out': 'break_end',
  };

  /// Face scan → punch/break via `POST /admin/face-kiosk/scan`.
  /// [action] is 'auto' | 'punch_in' | 'punch_out' | 'break_start' | 'break_end'.
  static Future<ScanResult> scanAttendance({
    required String imageBase64,
    required String action,
    required double? latitude,
    required double? longitude,
    double? accuracy,
    String? locationName,
  }) async {
    final act = _legacyActions[action] ?? action;
    final r = await _send(
      'POST',
      '/admin/face-kiosk/scan',
      body: {
        'image': _dataUrl(imageBase64),
        'action': act,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'accuracy': ?accuracy,
        if (locationName != null && locationName.trim().isNotEmpty) 'locationName': locationName.trim(),
      },
      timeout: _faceTimeout,
    );

    if (!r.ok) {
      final reason = r.reason ?? (r.status == 503 ? 'engine_unavailable' : null);
      var fallback = 'Face not recognized. Align your face inside the guide.';
      if (reason == 'no_face') fallback = 'No face detected. Align your face inside the guide.';
      if (reason == 'engine_unavailable') fallback = 'Face recognition is temporarily unavailable. Please try again.';
      throw ApiException(r.message(fallback), statusCode: r.status, reason: reason);
    }
    return _mapScan(r.body);
  }

  static ScanResult _mapScan(Map<String, dynamic> b) {
    final action = (b['action'] ?? '').toString();
    final staff = _m(b['staff']);
    final state = _m(b['state']);
    final result = _m(b['result']);
    final options = (b['options'] is List)
        ? (b['options'] as List).map((e) => e.toString()).toList()
        : <String>[];

    String label;
    switch (action) {
      case 'punch_in':
        label = 'Check-In';
        break;
      case 'punch_out':
        label = 'Check-Out';
        break;
      case 'break_start':
        label = 'Break-In';
        break;
      case 'break_end':
        label = 'Break-Out';
        break;
      case 'choose':
        label = options.contains('break_end') ? 'On-Break-Scan' : 'Already-Checked-In';
        break;
      case 'completed':
        label = 'Punch-Completed';
        break;
      default:
        label = 'Punch-Completed';
    }

    final lateMinutes = action == 'punch_in' ? _i(result['lateMinutes']) : null;
    final earlyMinutes = action == 'punch_out' ? _i(result['earlyExitMinutes']) : null;

    String status = 'Present';
    if (action == 'punch_in' && (lateMinutes ?? 0) > 0) status = 'Punched Late';
    if (action == 'punch_out' && (earlyMinutes ?? 0) > 0) status = 'Punched Out Early';

    num? fine;
    if (action == 'punch_in') {
      fine = _n(result['totalFine']) ?? _n(result['lateFineAmount']);
    } else if (action == 'punch_out') {
      fine = _n(result['totalFine']) ?? _n(result['earlyExitFineAmount']);
    } else if (action == 'break_end') {
      // Only the fine for exceeding the break allowance belongs on a break result.
      fine = _n(result['breakFineAmount']);
    }

    int? breakTotal, breakAllowed, breakRemaining;
    bool breakOver = false;
    String? notice;
    if (action == 'break_start') {
      breakTotal = _i(result['usedMinutes']);
      breakAllowed = _i(result['allowedMinutes']);
      breakRemaining = _i(result['remainingMinutes']);
    } else if (action == 'break_end') {
      breakTotal = _i(result['totalBreakMinutes']) ?? _i(result['usedMinutes']);
      breakAllowed = _i(result['allowedMinutes']);
      breakRemaining = _i(result['remainingMinutes']);
      breakOver = (_i(result['excessMinutes']) ?? 0) > 0;
      if (breakOver) notice = _s(result['message']) ?? _s(b['message']);
    }
    if (breakAllowed == 0) {
      breakAllowed = null;
      breakRemaining = null;
    }

    final conf = b['confidence'];
    return ScanResult(
      employeeId: (staff['id'] ?? staff['_id'] ?? '').toString(),
      employeeCode: _s(staff['employeeId']),
      employeeName: (staff['name'] ?? '').toString(),
      department: _s(staff['department']),
      action: label,
      status: status,
      confidence: conf is num ? conf.toDouble() : 0.0,
      checkInTime: _s(result['checkInTime']) ?? _s(state['checkInTime']),
      checkOutTime: _s(result['checkOutTime']) ?? _s(state['checkOutTime']),
      breakTotalMin: breakTotal,
      breakAllowedMin: breakAllowed,
      breakRemainingMin: breakRemaining,
      breakOver: breakOver,
      notice: notice,
      lateMinutes: lateMinutes,
      earlyMinutes: earlyMinutes,
      fineAmount: fine,
      options: options,
    );
  }

  // ---------------------------------------------------------------- enrollment

  /// Employee self-enroll at the kiosk: the EMPLOYEE signs in with their own
  /// account (proves identity), then their live captures are registered via
  /// `POST /staff/face/enroll` with THEIR token. Nothing is stored. Returns the
  /// employee name. Throws [NeedsLiveCapture] when the capture was unusable.
  static Future<String> selfEnroll({
    required String email,
    required String password,
    required List<String> images,
  }) async {
    final who = await login(email, password);
    if (!who.isStaff) {
      throw ApiException('Use your employee account to register your face.');
    }

    final r = await _send(
      'POST',
      '/staff/face/enroll',
      body: {'selfies': images.map(_dataUrl).toList()},
      token: who.token,
      adminAuth: false,
      timeout: _faceTimeout,
    );
    if (r.ok) return who.name.isNotEmpty ? who.name : 'employee';
    _throwEnrollError(r, 'Enrollment failed. Please try again.');
  }

  /// Admin enroll from the Admin Panel: `POST /admin/face-kiosk/enroll`.
  /// Returns the server message.
  static Future<String> adminEnroll({required String staffId, required List<String> images}) async {
    final r = await _send(
      'POST',
      '/admin/face-kiosk/enroll',
      body: {'staffId': staffId, 'images': images.map(_dataUrl).toList()},
      timeout: _faceTimeout,
    );
    if (r.ok) return r.message('Face registered successfully.');
    _throwEnrollError(r, 'Enrollment failed. Please try again.');
  }

  static Never _throwEnrollError(_Resp r, String fallback) {
    if (r.status == 422) {
      throw NeedsLiveCapture(r.message('No usable face was captured. Please try again.'));
    }
    if (r.status == 503) {
      throw ApiException(
        r.message('Face recognition is temporarily unavailable. Please try again.'),
        statusCode: 503,
        reason: 'engine_unavailable',
      );
    }
    throw ApiException(r.message(fallback), statusCode: r.status, reason: r.reason);
  }

  // ---------------------------------------------------------------- roster

  /// Company employees (deactivated excluded) with their face-registration flag.
  static Future<List<EnrolledEmployee>> fetchKioskStaff({String? query}) async {
    final q = (query ?? '').trim();
    final path = q.isEmpty
        ? '/admin/face-kiosk/staff'
        : '/admin/face-kiosk/staff?q=${Uri.encodeQueryComponent(q)}';
    final r = await _send('GET', path);
    if (!r.ok) throw ApiException(r.message('Could not load employees.'), statusCode: r.status);
    final list = r.body['data'] is List ? r.body['data'] as List : const [];
    return list
        .whereType<Map>()
        .map((e) => EnrolledEmployee.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Employees with a registered face (dashboard / registry).
  static Future<List<EnrolledEmployee>> fetchEnrolledEmployees() async {
    final all = await fetchKioskStaff();
    return all.where((e) => e.enrolled).toList();
  }

  /// Profile + face registration + today's state for one employee.
  static Future<EmployeeDetail> fetchEmployeeDetail(String staffId) async {
    final r = await _send('GET', '/admin/face-kiosk/staff/${Uri.encodeComponent(staffId)}');
    if (!r.ok) throw ApiException(r.message('Could not load employee detail.'), statusCode: r.status);
    return EmployeeDetail.fromJson(_m(r.body['data']));
  }

  /// Clear an employee's registered face so they can enroll again.
  /// Callers must re-verify the admin password first.
  static Future<String> resetFace(String staffId) async {
    final r = await _send('DELETE', '/admin/face-recognition/${Uri.encodeComponent(staffId)}');
    if (!r.ok) throw ApiException(r.message('Could not reset the face.'), statusCode: r.status);
    return r.message('Face registration reset.');
  }
}
