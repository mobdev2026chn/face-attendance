import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/scan_result.dart';
import 'api_service.dart' show ApiException;

/// Result of a face match from the face backend: identity + the matched employee's
/// EHRMS token, so the app can call EHRMS DIRECTLY for punch/break.
class FaceResolve {
  final bool linked;
  final String employeeId;
  final String employeeName;
  final String? department;
  final String? profilePhoto;
  final String? profilePhotoIso; // enrollment time — decides legacy 180° flip
  final double confidence;
  final String ehrmsBaseUrl; // e.g. https://ehrms.askeva.net
  final String accessToken;
  final String? refreshToken;

  FaceResolve({
    required this.linked,
    required this.employeeId,
    required this.employeeName,
    this.department,
    this.profilePhoto,
    this.profilePhotoIso,
    required this.confidence,
    required this.ehrmsBaseUrl,
    required this.accessToken,
    this.refreshToken,
  });

  factory FaceResolve.fromJson(Map<String, dynamic> json) {
    return FaceResolve(
      linked: json['linked'] == true,
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? '').toString(),
      department: json['department']?.toString(),
      profilePhoto: json['profile_photo']?.toString(),
      profilePhotoIso: json['profile_photo_iso']?.toString(),
      confidence: (json['confidence'] is num) ? (json['confidence'] as num).toDouble() : 0.0,
      ehrmsBaseUrl: (json['ehrms_base_url'] ?? '').toString(),
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: json['refresh_token']?.toString(),
    );
  }
}

/// Talks to the EHRMS dev API (https://ehrms.askeva.net/api) DIRECTLY using the matched
/// employee's token. Mirrors the punch/break state machine and returns a ScanResult.
class EhrmsDirect {
  final FaceResolve face;
  String _token;
  EhrmsDirect(this.face) : _token = face.accessToken;

  // Always the DEV EHRMS host (kEhrmsBaseUrl = ehrms.askeva.net) — ignore the
  // per-resolve ehrms_base_url so a stale/empty backend value can't break or
  // mis-route attendance writes.
  String get _api => '${kEhrmsBaseUrl.replaceAll(RegExp(r'/+$'), '')}/api';

  static String? _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    return DateFormat('yyyy-MM-dd hh:mm:ss a').format(dt.toLocal());
  }

  Future<http.Response> _send(String method, String path, {Map<String, dynamic>? body}) async {
    Future<http.Response> once() {
      final uri = Uri.parse('$_api$path');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'};
      final b = body != null ? jsonEncode(body) : null;
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'POST':
          return http.post(uri, headers: headers, body: b);
        case 'PUT':
          return http.put(uri, headers: headers, body: b);
        case 'PATCH':
          return http.patch(uri, headers: headers, body: b);
        default:
          throw ApiException('Unsupported method $method');
      }
    }

    var res = await once();
    // Transparent token refresh against EHRMS directly, then retry once.
    if (res.statusCode == 401 && face.refreshToken != null) {
      final r = await http.post(
        Uri.parse('$_api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': face.refreshToken}),
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body)['data'];
        final newTok = data?['accessToken'];
        if (newTok is String && newTok.isNotEmpty) {
          _token = newTok;
          res = await once();
        }
      }
      if (res.statusCode == 401) {
        throw ApiException('EHRMS session expired for ${face.employeeName}. Please re-link.');
      }
    }
    return res;
  }

  Map<String, dynamic> _json(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _detail(http.Response res, String fallback) {
    final j = _json(res);
    return (j['message'] ?? (j['error'] is Map ? j['error']['message'] : null) ?? j['detail'] ?? fallback).toString();
  }

  /// Run the punch/break flow for [requestedAction] ('auto'|'in'|'out'|'break_in'|'break_out'|'break').
  Future<ScanResult> punch({
    required String requestedAction,
    required double latitude,
    required double longitude,
    required String selfie,
    String address = '',
    String area = '',
    String city = '',
    String pincode = '',
  }) async {
    // 1. Read current EHRMS state — both reads in PARALLEL (saves a round-trip).
    final reads = await Future.wait([
      _send('GET', '/attendance/today'),
      _send('GET', '/breaks/current'),
    ]);
    final todayRes = reads[0];
    if (todayRes.statusCode != 200) throw ApiException(_detail(todayRes, 'Could not read attendance.'));
    final today = _json(todayRes);
    final att = (today['data'] is Map) ? today['data'] as Map<String, dynamic> : null;
    final hasPunchIn = today['hasPunchIn'] == true;
    final hasPunchOut = today['hasPunchOut'] == true;

    final brk = _json(reads[1]);
    final onBreak = brk['hasActiveBreak'] == true;
    // Resolve the active break id defensively: the server may key it as id / _id /
    // breakId depending on version. Empty id => PATCH /breaks//end 404s, so we must
    // get this right (and fall back to today's ongoing break below if needed).
    String? activeBreakId;
    if (brk['data'] is Map) {
      final d = brk['data'] as Map<String, dynamic>;
      activeBreakId =
          (d['id'] ?? d['_id'] ?? d['breakId'])?.toString();
    }

    var action = requestedAction.isEmpty ? 'auto' : requestedAction;
    if (action == 'break') action = 'break_in';
    if (action == 'auto') {
      if (hasPunchOut) {
        action = 'Punch-Completed';
      } else if (hasPunchIn) {
        action = onBreak ? 'On-Break-Scan' : 'Already-Checked-In';
      } else {
        action = 'in';
      }
    }

    final name = face.employeeName;
    final status = (att?['status'] ?? 'Present').toString();
    ScanResult build(String act, {String? ci, String? co}) => ScanResult(
          employeeId: face.employeeId,
          employeeName: name,
          department: face.department,
          profilePhoto: face.profilePhoto,
          profilePhotoIso: face.profilePhotoIso,
          action: act,
          status: status,
          confidence: face.confidence,
          checkInTime: ci,
          checkOutTime: co,
        );

    // 2. Status-only actions (no write).
    if (action == 'Punch-Completed') {
      return build('Punch-Completed', ci: _fmt(att?['punchIn']?.toString()), co: _fmt(att?['punchOut']?.toString()));
    }
    if (action == 'On-Break-Scan') {
      return build('On-Break-Scan', ci: _fmt(att?['punchIn']?.toString()));
    }
    if (action == 'Already-Checked-In') {
      return build('Already-Checked-In', ci: _fmt(att?['punchIn']?.toString()));
    }

    // 3. Validate writes (mirror backend guards).
    if (action == 'in' && hasPunchIn) throw ApiException('Hello $name, you have already Punched IN today.');
    if (action == 'out') {
      if (hasPunchOut) throw ApiException('Hello $name, you have already Punched OUT today.');
      if (!hasPunchIn) throw ApiException('Hello $name, no Punch In record found for today. Please Punch IN first.');
      if (onBreak) throw ApiException('Hello $name, please End your Break before Punching Out.');
    }
    if (action == 'break_in') {
      if (!hasPunchIn) throw ApiException('Hello $name, you must Punch IN first before taking a break.');
      if (onBreak) throw ApiException('Hello $name, you are already on a break.');
    }
    if (action == 'break_out') {
      // Fallback: if /breaks/current didn't give us an id, find today's ongoing
      // break (endTime null / ongoing true) so ending it still reaches EHRMS.
      if (activeBreakId == null) {
        try {
          final tRes = await _send('GET', '/breaks/today');
          final tBody = _json(tRes);
          final tData = (tBody['data'] is Map) ? tBody['data'] as Map<String, dynamic> : tBody;
          final list = (tData['breaks'] is List) ? tData['breaks'] as List : const [];
          for (final b in list) {
            if (b is Map) {
              final ongoing = b['ongoing'] == true ||
                  b['endTime'] == null ||
                  (b['endTime']?.toString().isEmpty ?? true);
              if (ongoing) {
                activeBreakId = (b['id'] ?? b['_id'] ?? b['breakId'])?.toString();
                if (activeBreakId != null && activeBreakId.isNotEmpty) break;
              }
            }
          }
        } catch (_) {/* fall through to the guard below */}
      }
      if (activeBreakId == null || activeBreakId.isEmpty) {
        throw ApiException('Hello $name, you are not currently on a break.');
      }
    }

    // No EHRMS profile-photo validation here: the face app already performed strong
    // LIVE 1-to-many recognition (embeddings) + passive anti-spoofing on the backend,
    // which authoritatively identifies who this is. We do NOT re-verify the selfie
    // against EHRMS's rolling reference photo.

    // 4. Write DIRECTLY to EHRMS (include the full reverse-geocoded address).
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'selfie': selfie,
      'source': 'software',
      if (address.isNotEmpty) 'address': address,
      if (area.isNotEmpty) 'area': area,
      if (city.isNotEmpty) 'city': city,
      if (pincode.isNotEmpty) 'pincode': pincode,
    };
    http.Response w;
    String label;
    if (action == 'in') {
      w = await _send('POST', '/attendance/checkin', body: body);
      label = 'Check-In';
    } else if (action == 'out') {
      w = await _send('PUT', '/attendance/checkout', body: body);
      label = 'Check-Out';
    } else if (action == 'break_in') {
      w = await _send('POST', '/breaks/start', body: body);
      label = 'Break-In';
    } else {
      w = await _send('PATCH', '/breaks/$activeBreakId/end', body: body);
      label = 'Break-Out';
    }
    if (w.statusCode < 200 || w.statusCode >= 300) {
      throw ApiException(_detail(w, '$label failed.'));
    }

    // 5. Derive post-write times/status from the WRITE response (checkin/checkout return
    // the attendance record) — no extra round-trip. Fall back to pre-write data + now.
    final wbody = _json(w);
    final wAtt = (wbody['data'] is Map) ? wbody['data'] as Map<String, dynamic> : wbody;
    final nowFmt = DateFormat('yyyy-MM-dd hh:mm:ss a').format(DateTime.now().toLocal());
    String? ci = _fmt(wAtt['punchIn']?.toString()) ?? _fmt(att?['punchIn']?.toString());
    String? co = _fmt(wAtt['punchOut']?.toString()) ?? _fmt(att?['punchOut']?.toString());
    if (action == 'in' && ci == null) ci = nowFmt;
    if (action == 'out' && co == null) co = nowFmt;
    final outStatus = (wAtt['status'] ?? att?['status'] ?? status).toString();

    // Break policy (only for break actions) — single extra read, best-effort.
    int? breakTotal, breakAllowed, breakRemaining;
    bool breakOver = false, breakUnlimited = false;
    if (action == 'break_in' || action == 'break_out') {
      try {
        final bRes = await _send('GET', '/breaks/today');
        final bd = (_json(bRes)['data'] is Map) ? _json(bRes)['data'] as Map<String, dynamic> : {};
        breakUnlimited = bd['isUnlimited'] == true;
        breakTotal = (bd['totalBreakMin'] is num) ? (bd['totalBreakMin'] as num).toInt() : null;
        if (!breakUnlimited) {
          breakAllowed = (bd['allowedMinutes'] is num) ? (bd['allowedMinutes'] as num).toInt() : null;
          breakRemaining = (bd['remainingMin'] is num) ? (bd['remainingMin'] as num).toInt() : null;
          breakOver = breakAllowed != null && breakAllowed > 0 && (breakTotal ?? 0) > breakAllowed;
        }
      } catch (_) {/* policy is best-effort */}
    }

    return ScanResult(
      employeeId: face.employeeId,
      employeeName: name,
      department: face.department,
      profilePhoto: face.profilePhoto,
      profilePhotoIso: face.profilePhotoIso,
      action: label,
      status: outStatus,
      confidence: face.confidence,
      checkInTime: ci,
      checkOutTime: co,
      breakTotalMin: breakTotal,
      breakAllowedMin: breakAllowed,
      breakRemainingMin: breakRemaining,
      breakOver: breakOver,
      breakUnlimited: breakUnlimited,
    );
  }
}
