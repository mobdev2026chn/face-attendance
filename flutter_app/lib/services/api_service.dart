import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/attendance_record.dart';
import '../models/scan_result.dart';
import '../models/ehrms_overview.dart';
import '../models/employee_directory.dart';
import '../models/month_attendance.dart';
import 'ehrms_direct.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Thrown when enroll-and-link found no usable EHRMS face image (B failed) and a
/// live kiosk capture is required to enroll (A).
class NeedsLiveCapture implements Exception {
  final String message;
  NeedsLiveCapture(this.message);
  @override
  String toString() => message;
}

class EnrolledUser {
  final String id;
  final String name;
  final String date;
  final int punches;

  EnrolledUser({required this.id, required this.name, required this.date, required this.punches});
}

class EnrolledFace {
  final String employeeId;
  final String fullName;
  final bool ehrmsLinked;
  final String? ehrmsEmail;

  EnrolledFace({required this.employeeId, required this.fullName, required this.ehrmsLinked, this.ehrmsEmail});

  factory EnrolledFace.fromJson(Map<String, dynamic> json) {
    return EnrolledFace(
      employeeId: (json['employeeId'] ?? '').toString(),
      fullName: (json['fullName'] ?? '').toString(),
      ehrmsLinked: json['ehrmsLinked'] == true,
      ehrmsEmail: json['ehrmsEmail']?.toString(),
    );
  }
}

/// A real employee from the dev EHRMS staff directory (for the link picker).
class DevEmployee {
  final String? employeeId;
  final String name;
  final String email;

  DevEmployee({this.employeeId, required this.name, required this.email});

  factory DevEmployee.fromJson(Map<String, dynamic> json) {
    return DevEmployee(
      employeeId: json['employeeId']?.toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}

class DashboardStats {
  final int totalEnrolled;
  final int presentToday;

  DashboardStats({required this.totalEnrolled, required this.presentToday});

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalEnrolled: (json['total_enrolled'] ?? 0) as int,
      presentToday: (json['present_today'] ?? 0) as int,
    );
  }
}

class ApiService {
  /// Face scan → punch/break. The face backend only matches the face and returns the
  /// linked employee's EHRMS token; the punch/break get+post then go DIRECTLY to
  /// https://ehrms.askeva.net/api from the app. Unlinked faces fall back to the local flow.
  static Future<ScanResult> scanAttendance({
    required String imageBase64,
    required String action,
    required double gpsLat,
    required double gpsLon,
    String address = '',
    String area = '',
    String city = '',
    String pincode = '',
  }) async {
    // 1. Resolve WHO via the face backend (biometric match) + get their EHRMS token.
    final resolveRes = await http.post(
      Uri.parse('$kBackendUrl/attendance/resolve-face'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image_base64': imageBase64}),
    );
    final rdata = jsonDecode(resolveRes.body) as Map<String, dynamic>;

    if (resolveRes.statusCode == 200 && rdata['linked'] == true) {
      // 2. Punch/break straight against EHRMS (ehrms.askeva.net/api) from the app.
      final face = FaceResolve.fromJson(rdata);
      return EhrmsDirect(face).punch(
        requestedAction: action,
        latitude: gpsLat,
        longitude: gpsLon,
        selfie: imageBase64,
        address: address,
        area: area,
        city: city,
        pincode: pincode,
      );
    }
    // Recognized but NOT linked to EHRMS (409) → no local fallback (EHRMS/dev only).
    // The detail ("… is recognized but not linked …") routes the scanner to the
    // link/enroll flow, which links the live capture to a dev account.
    throw ApiException(rdata['detail']?.toString() ?? 'Face scanning failed.');
  }

  static Future<void> addEmployee({
    required String id,
    required String fullName,
    required String department,
    required String designation,
    required String phone,
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/register-mobile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
        'full_name': fullName,
        'department': department,
        'designation': designation,
        'phone_number': phone,
        'email': email,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Failed to register employee.');
    }
  }

  static Future<void> enrollFace({required String employeeId, required String imageBase64}) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/enroll-face-mobile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'image_base64': imageBase64,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Error connecting to server.');
    }
  }

  /// One month of attendance + break details for a linked employee (from EHRMS).
  /// [year] full year, [month] 1-12; omit for the current month.
  static Future<MonthAttendance> fetchEhrmsMonth({
    required String employeeId,
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final y = year ?? now.year;
    final m = month ?? now.month;
    final uri = Uri.parse(
        '$kBackendUrl/employees/$employeeId/ehrms-month?year=$y&month=$m');
    final response = await http.get(uri);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(
          data['detail']?.toString() ?? 'Could not load monthly attendance.');
    }
    return MonthAttendance.fromJson(data);
  }

  static Future<DashboardStats> fetchMetrics() async {
    final response = await http.get(Uri.parse('$kBackendUrl/employees/metrics'));
    if (response.statusCode != 200) {
      throw ApiException('Could not load dashboard metrics.');
    }
    return DashboardStats.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Enrolled faces + their EHRMS link status (drives the link picker).
  static Future<List<EnrolledFace>> fetchEnrolledFaces() async {
    final response = await http.get(Uri.parse('$kBackendUrl/employees/list'));
    if (response.statusCode != 200) {
      throw ApiException('Could not load enrolled faces.');
    }
    final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => EnrolledFace.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Dev EHRMS employee directory (admin-scoped, via the backend service account).
  static Future<List<DevEmployee>> fetchDevDirectory() async {
    final response = await http.get(Uri.parse('$kBackendUrl/employees/dev-directory'));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Could not load dev employee directory.');
    }
    final list = (data['employees'] as List<dynamic>? ?? []);
    return list.map((e) => DevEmployee.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Link an enrolled face to an EHRMS account (logs into EHRMS, stores the token).
  static Future<void> linkEhrms({
    required String employeeId,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/link-ehrms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'employee_id': employeeId, 'ehrms_email': email, 'ehrms_password': password}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Could not link to EHRMS.');
    }
  }

  /// Enroll + link in one step. With [imageBase64] (live capture) it enrolls from that
  /// face (A). Without it, the backend enrolls from the staff's EHRMS punch selfie (B);
  /// if none is usable it throws [NeedsLiveCapture]. Returns the enrolled employee name.
  static Future<String> enrollAndLink({
    required String email,
    required String password,
    String? imageBase64,
  }) async {
    final body = <String, dynamic>{'ehrms_email': email, 'ehrms_password': password};
    if (imageBase64 != null && imageBase64.isNotEmpty) body['image_base64'] = imageBase64;
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/enroll-and-link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return (data['employee_name'] ?? data['employee_id'] ?? 'employee').toString();
    }
    if (response.statusCode == 422 && data['needs_live_capture'] == true) {
      throw NeedsLiveCapture(data['detail']?.toString() ?? 'A live photo is required to enroll.');
    }
    throw ApiException(data['detail']?.toString() ?? 'Enroll + link failed.');
  }

  /// Kiosk self-enrollment for an UNRECOGNIZED person. They authenticate with their
  /// EHRMS email+password; the live capture(s) are registered as their canonical face
  /// in EHRMS (the store the kiosk identifies against). The backend rejects a face that
  /// already belongs to another user. Returns the enrolled employee name.
  /// Throws [NeedsLiveCapture] when no face was detected (retry the capture).
  static Future<String> kioskEnroll({
    required String email,
    required String password,
    required List<String> images,
  }) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/kiosk-enroll'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'ehrms_email': email,
        'ehrms_password': password,
        'image_base64': images,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      return (data['employee_name'] ?? data['employee_id'] ?? 'employee').toString();
    }
    if (response.statusCode == 422 && data['needs_live_capture'] == true) {
      throw NeedsLiveCapture(data['detail']?.toString() ?? 'No face detected. Please try again.');
    }
    throw ApiException(data['detail']?.toString() ?? 'Enrollment failed.');
  }

  /// Clear a staff member's enrolled face + profile image (canonical, in EHRMS) so
  /// they can re-enroll. Identified by [employeeId] (external HR id). Requires
  /// [adminEmail]/[adminPassword] — the backend re-verifies them as an Admin / Super
  /// Admin before clearing. After this the employee drops out of recognition until
  /// they enroll again.
  static Future<void> clearEnrolledFace({
    required String employeeId,
    required String adminEmail,
    required String adminPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/clear-face'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': employeeId,
        'admin_email': adminEmail,
        'admin_password': adminPassword,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Could not clear enrolled face.');
    }
  }

  /// Add the live punch face as another enrollment sample (continuous, interlinked
  /// enrollment → robust recognition, no daily re-link). Fire-and-forget / best-effort.
  static Future<void> addFaceSample({required String employeeId, required String imageBase64}) async {
    try {
      await http.post(
        Uri.parse('$kBackendUrl/employees/add-face-sample'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'employee_id': employeeId, 'image_base64': imageBase64}),
      );
    } catch (_) {/* best-effort; never affects the punch */}
  }

  /// Bulk: enroll+link every dev directory employee sharing the password (default: the
  /// backend's configured dev password). Returns {total, linked, failed, results}.
  static Future<Map<String, dynamic>> linkAllDev({String? password}) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/link-all-dev'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(password != null ? {'password': password} : {}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Bulk link failed.');
    }
    return data;
  }

  /// Remove an EHRMS link (reverts that face to local-only attendance).
  static Future<void> unlinkEhrms(String employeeId) async {
    final response = await http.post(
      Uri.parse('$kBackendUrl/employees/unlink-ehrms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'employee_id': employeeId}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Could not unlink.');
    }
  }

  /// Live EHRMS attendance snapshot for all linked employees (single source of truth).
  static Future<EhrmsOverview> fetchEhrmsOverview() async {
    final response = await http.get(Uri.parse('$kBackendUrl/attendance/ehrms-overview'));
    if (response.statusCode != 200) {
      throw ApiException('Could not load EHRMS attendance.');
    }
    return EhrmsOverview.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// EHRMS-enrolled employees for the dashboard (proxied to EHRMS).
  static Future<List<EnrolledEmployee>> fetchEnrolledEmployees() async {
    final response = await http
        .get(Uri.parse('$kBackendUrl/employees/enrolled'))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw ApiException('Could not load enrolled employees.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['employees'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(EnrolledEmployee.fromJson)
        .toList();
  }

  /// Full detail (profile + today + month) for one enrolled employee.
  static Future<EmployeeDetail> fetchEmployeeDetail(String employeeId) async {
    final response = await http
        .get(Uri.parse('$kBackendUrl/employees/${Uri.encodeComponent(employeeId)}/detail'))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw ApiException('Could not load employee detail.');
    }
    return EmployeeDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<AttendanceRecord>> fetchAttendanceRecords() async {
    final response = await http.get(Uri.parse('$kBackendUrl/attendance/records'));
    if (response.statusCode != 200) {
      throw ApiException('Could not load attendance records.');
    }
    final List<dynamic> records = jsonDecode(response.body) as List<dynamic>;
    return records.map((r) => AttendanceRecord.fromJson(r as Map<String, dynamic>)).toList();
  }

  static Future<List<EnrolledUser>> fetchRegistry() async {
    final records = await fetchAttendanceRecords();
    final seen = <String>{};
    final users = <EnrolledUser>[];
    for (final r in records) {
      if (!seen.contains(r.employeeId)) {
        seen.add(r.employeeId);
        users.add(EnrolledUser(
          id: r.id.isNotEmpty ? r.id : r.employeeId,
          name: r.employeeName,
          date: '${r.timestamp.day}/${r.timestamp.month}/${r.timestamp.year}',
          punches: records.where((log) => log.employeeId == r.employeeId).length,
        ));
      }
    }
    return users;
  }

  static Future<void> deleteEmployee({required String employeeId, required String id}) async {
    final response = await http.delete(
      Uri.parse('$kBackendUrl/employees/delete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'employeeId': employeeId, 'id': id}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw ApiException(data['detail']?.toString() ?? 'Could not delete user.');
    }
  }
}
