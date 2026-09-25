int? _intOrNull(dynamic v) => v is num ? v.toInt() : null;

String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// One company employee as returned by HRMS `GET /admin/face-kiosk/staff`.
/// Used by the dashboard (enrolled ones only) and the admin enroll picker.
class EnrolledEmployee {
  /// HRMS staff id (Mongo `_id`) — used to open detail / enroll / reset.
  final String employeeId;

  /// HR employee code (staff.employeeId) shown to people, when set.
  final String? hrEmployeeId;
  final String name;
  final String? email;
  final String? department;
  final String? designation;
  final String? avatar;
  final String? enrolledAt;
  final String? status;
  final bool enrolled;
  // Today's live attendance snapshot (per-user) — drives the dashboard summary card.
  final bool presentToday;
  final bool lateToday;
  final bool onBreak;
  final bool permissionToday;

  EnrolledEmployee({
    required this.employeeId,
    this.hrEmployeeId,
    required this.name,
    this.email,
    this.department,
    this.designation,
    this.avatar,
    this.enrolledAt,
    this.status,
    this.enrolled = false,
    this.presentToday = false,
    this.lateToday = false,
    this.onBreak = false,
    this.permissionToday = false,
  });

  factory EnrolledEmployee.fromJson(Map<String, dynamic> j) {
    final today = _map(j['today']);
    return EnrolledEmployee(
      employeeId: (j['id'] ?? j['_id'] ?? '').toString(),
      hrEmployeeId: _strOrNull(j['employeeId']),
      name: (j['name'] ?? '').toString(),
      email: _strOrNull(j['email']),
      department: _strOrNull(j['department']),
      designation: _strOrNull(j['designation']),
      avatar: null,
      enrolledAt: _strOrNull(j['enrolledAt']),
      enrolled: j['enrolled'] == true,
      presentToday: today['checkInTime'] != null,
      lateToday: false,
      onBreak: today['onBreak'] == true,
      permissionToday: false,
    );
  }
}

/// Today's attendance state for one employee (HRMS kiosk `today` object).
class KioskToday {
  final bool punchedIn;
  final bool punchedOut;
  final String? checkInTime;
  final String? checkOutTime;
  final bool onBreak;
  final bool canStartBreak;
  final int? breakAllowedMin;
  final int? breakUsedMin;
  final int? breakRemainingMin;
  final String? breakActiveSince;

  KioskToday({
    this.punchedIn = false,
    this.punchedOut = false,
    this.checkInTime,
    this.checkOutTime,
    this.onBreak = false,
    this.canStartBreak = false,
    this.breakAllowedMin,
    this.breakUsedMin,
    this.breakRemainingMin,
    this.breakActiveSince,
  });

  /// Human status derived from the punch/break flags.
  String get statusLabel {
    if (punchedOut || checkOutTime != null) return 'Punched Out';
    if (onBreak) return 'On Break';
    if (punchedIn || checkInTime != null) return 'Punched In';
    return 'Not Punched In';
  }

  factory KioskToday.fromJson(Map<String, dynamic> j) {
    final brk = _map(j['break']);
    return KioskToday(
      punchedIn: j['punchedIn'] == true,
      punchedOut: j['punchedOut'] == true,
      checkInTime: _strOrNull(j['checkInTime']),
      checkOutTime: _strOrNull(j['checkOutTime']),
      onBreak: j['onBreak'] == true,
      canStartBreak: j['canStartBreak'] == true,
      breakAllowedMin: _intOrNull(brk['allowedMinutes']),
      breakUsedMin: _intOrNull(brk['usedMinutes']),
      breakRemainingMin: _intOrNull(brk['remainingMinutes']),
      breakActiveSince: _strOrNull(brk['activeSince']),
    );
  }
}

/// Detail for one employee: profile + face registration + today's state.
/// Backed by HRMS `GET /admin/face-kiosk/staff/:staffId`. There is no monthly
/// history on the kiosk (it lives in the HRMS web portal).
class EmployeeDetail {
  final Map<String, dynamic> profile;
  final bool enrolled;
  final int? samples;
  final KioskToday? today;

  EmployeeDetail({required this.profile, this.enrolled = false, this.samples, this.today});

  String? get(String key) => _strOrNull(profile[key]);

  factory EmployeeDetail.fromJson(Map<String, dynamic> j) {
    final t = j['today'];
    return EmployeeDetail(
      profile: j,
      enrolled: j['enrolled'] == true,
      samples: _intOrNull(j['samples']),
      today: t is Map ? KioskToday.fromJson(Map<String, dynamic>.from(t)) : null,
    );
  }
}
