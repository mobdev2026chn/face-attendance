/// One break taken today (start → end). `to` is null while the break is ongoing.
class BreakEntry {
  final String? from;
  final String? to;
  final int durationMin;
  final bool ongoing;

  BreakEntry({this.from, this.to, required this.durationMin, required this.ongoing});

  factory BreakEntry.fromJson(Map<String, dynamic> json) {
    return BreakEntry(
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      durationMin: (json['duration_min'] is num) ? (json['duration_min'] as num).toInt() : 0,
      ongoing: json['ongoing'] == true,
    );
  }
}

/// Live attendance snapshot pulled from EHRMS (the single source of truth) for every
/// face profile linked to an EHRMS account. Backed by GET /api/attendance/ehrms-overview.
class EhrmsEmployee {
  final String employeeId;
  final String employeeName;
  final String? ehrmsEmail;
  final String? punchIn;
  final String? punchOut;
  final String? punchInIso;
  final String? punchOutIso;
  final String status;
  final bool onBreak;
  // Today's late arrival + permission usage (minutes), from the raw attendance doc.
  final int lateMin;
  final int earlyMin;
  final int permissionConsumedMin;
  final int permissionApprovedMin;
  final int totalBreakMin;
  final int? allowedBreakMin; // null = unlimited
  final int? remainingBreakMin; // null = unlimited
  final bool unlimitedBreak;
  final bool breakDisabled;
  final List<BreakEntry> breaks;
  final bool presentToday;
  final String? error;
  // Face captured at punch time (validated face), as EHRMS image URLs.
  final String? punchInSelfie;
  final String? punchOutSelfie;
  final num? punchInFaceMatch;
  final num? punchOutFaceMatch;
  // Enrolled reference face (base64) — fallback when no punch selfie is on EHRMS yet.
  final String? referencePhoto;

  EhrmsEmployee({
    required this.employeeId,
    required this.employeeName,
    this.ehrmsEmail,
    this.punchIn,
    this.punchOut,
    this.punchInIso,
    this.punchOutIso,
    required this.status,
    required this.onBreak,
    this.lateMin = 0,
    this.earlyMin = 0,
    this.permissionConsumedMin = 0,
    this.permissionApprovedMin = 0,
    required this.totalBreakMin,
    this.allowedBreakMin,
    this.remainingBreakMin,
    this.unlimitedBreak = false,
    this.breakDisabled = false,
    this.breaks = const [],
    required this.presentToday,
    this.error,
    this.punchInSelfie,
    this.punchOutSelfie,
    this.punchInFaceMatch,
    this.punchOutFaceMatch,
    this.referencePhoto,
  });

  factory EhrmsEmployee.fromJson(Map<String, dynamic> json) {
    return EhrmsEmployee(
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? '').toString(),
      ehrmsEmail: json['ehrms_email']?.toString(),
      punchIn: json['punch_in']?.toString(),
      punchOut: json['punch_out']?.toString(),
      punchInIso: json['punch_in_iso']?.toString(),
      punchOutIso: json['punch_out_iso']?.toString(),
      status: (json['status'] ?? '-').toString(),
      onBreak: json['on_break'] == true,
      lateMin: (json['late_min'] is num) ? (json['late_min'] as num).toInt() : 0,
      earlyMin: (json['early_min'] is num) ? (json['early_min'] as num).toInt() : 0,
      permissionConsumedMin: (json['permission_consumed_min'] is num) ? (json['permission_consumed_min'] as num).toInt() : 0,
      permissionApprovedMin: (json['permission_approved_min'] is num) ? (json['permission_approved_min'] as num).toInt() : 0,
      totalBreakMin: (json['total_break_min'] is num) ? (json['total_break_min'] as num).toInt() : 0,
      allowedBreakMin: (json['allowed_break_min'] is num) ? (json['allowed_break_min'] as num).toInt() : null,
      remainingBreakMin: (json['remaining_break_min'] is num) ? (json['remaining_break_min'] as num).toInt() : null,
      unlimitedBreak: json['unlimited_break'] == true,
      breakDisabled: json['break_disabled'] == true,
      breaks: (json['breaks'] as List<dynamic>? ?? [])
          .map((b) => BreakEntry.fromJson(b as Map<String, dynamic>))
          .toList(),
      presentToday: json['present_today'] == true,
      error: json['error']?.toString(),
      punchInSelfie: json['punch_in_selfie']?.toString(),
      punchOutSelfie: json['punch_out_selfie']?.toString(),
      punchInFaceMatch: json['punch_in_face_match'] is num ? json['punch_in_face_match'] as num : null,
      punchOutFaceMatch: json['punch_out_face_match'] is num ? json['punch_out_face_match'] as num : null,
      referencePhoto: json['reference_photo']?.toString(),
    );
  }

  /// Arrived late today (carries a late-arrival penalty/duration).
  bool get isLate => lateMin > 0;

  /// Took (or was approved for) a permission today.
  bool get hasPermission => permissionConsumedMin > 0 || permissionApprovedMin > 0;
}

class EhrmsOverview {
  final String ehrmsBaseUrl;
  final int linkedEmployees;
  final int presentToday;
  // Per-day, user-wise tallies for the dashboard summary card.
  final int lateToday;
  final int onBreakToday;
  final int permissionToday;
  final List<EhrmsEmployee> employees;

  EhrmsOverview({
    required this.ehrmsBaseUrl,
    required this.linkedEmployees,
    required this.presentToday,
    this.lateToday = 0,
    this.onBreakToday = 0,
    this.permissionToday = 0,
    required this.employees,
  });

  factory EhrmsOverview.fromJson(Map<String, dynamic> json) {
    final list = (json['employees'] as List<dynamic>? ?? [])
        .map((e) => EhrmsEmployee.fromJson(e as Map<String, dynamic>))
        .toList();
    int countOr(String key, bool Function(EhrmsEmployee) test) =>
        (json[key] is num) ? (json[key] as num).toInt() : list.where(test).length;
    return EhrmsOverview(
      ehrmsBaseUrl: (json['ehrms_base_url'] ?? '').toString(),
      linkedEmployees: (json['linked_employees'] is num) ? (json['linked_employees'] as num).toInt() : 0,
      presentToday: (json['present_today'] is num) ? (json['present_today'] as num).toInt() : list.where((e) => e.presentToday).length,
      lateToday: countOr('late_today', (e) => e.isLate),
      onBreakToday: countOr('on_break_today', (e) => e.onBreak),
      permissionToday: countOr('permission_today', (e) => e.hasPermission),
      employees: list,
    );
  }
}
