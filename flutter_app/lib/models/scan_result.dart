class ScanResult {
  final String employeeId;
  final String employeeName;
  final String? department;
  final String? profilePhoto;
  final String? profilePhotoIso; // enrollment time — decides legacy 180° flip
  final String action; // Check-In, Check-Out, Break-In, Break-Out, Already-Checked-In, On-Break-Scan, Punch-Completed
  final String status; // Present, Punched Late, Punched Out Early, etc.
  final double confidence;
  final String? checkInTime;
  final String? checkOutTime;
  // Break policy snapshot (set for break actions) — drives the break-policy notification.
  final int? breakTotalMin;
  final int? breakAllowedMin; // null = unlimited / not configured
  final int? breakRemainingMin;
  final bool breakOver;
  final bool breakUnlimited;
  /// Exact EHRMS policy notice for the action (break disabled / no-allowance
  /// "...processed with Fine", or "Allocated break time exceeded by N minutes.").
  /// null when there is no notice. Shown verbatim — EHRMS is the source of truth.
  final String? notice;
  // Fine snapshot from the EHRMS punch response (single source of truth). Always
  // based on the shift allocated for that day — never hardcoded at the kiosk.
  final int? lateMinutes;
  final int? earlyMinutes;
  final num? fineAmount; // total day fine (late + early + break + permission)
  // Overtime snapshot (set on punch-out). overtimeNotice carries EHRMS's exact
  // "Overtime is disabled for you." / "Overtime is not configured. Contact HR."
  // wording, or empty when eligible.
  final int? overtimeMinutes;
  final num? overtimeAmount;
  final String? overtimeNotice;
  /// Exact EHRMS permission policy notice ("Permission is not configured..." /
  /// "...exceeded by N minutes"), when the punch response carries one.
  final String? permissionNotice;

  ScanResult({
    required this.employeeId,
    required this.employeeName,
    this.department,
    this.profilePhoto,
    this.profilePhotoIso,
    required this.action,
    required this.status,
    required this.confidence,
    this.checkInTime,
    this.checkOutTime,
    this.breakTotalMin,
    this.breakAllowedMin,
    this.breakRemainingMin,
    this.breakOver = false,
    this.breakUnlimited = false,
    this.notice,
    this.lateMinutes,
    this.earlyMinutes,
    this.fineAmount,
    this.overtimeMinutes,
    this.overtimeAmount,
    this.overtimeNotice,
    this.permissionNotice,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? '').toString(),
      department: json['department']?.toString(),
      profilePhoto: json['profile_photo']?.toString(),
      profilePhotoIso: json['profile_photo_iso']?.toString(),
      action: (json['action'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      confidence: (json['confidence'] is num) ? (json['confidence'] as num).toDouble() : 0.0,
      checkInTime: json['check_in_time']?.toString(),
      checkOutTime: json['check_out_time']?.toString(),
      notice: (json['notice'] is String && (json['notice'] as String).trim().isNotEmpty)
          ? json['notice'] as String
          : null,
      lateMinutes: (json['late_minutes'] is num) ? (json['late_minutes'] as num).toInt() : null,
      earlyMinutes: (json['early_minutes'] is num) ? (json['early_minutes'] as num).toInt() : null,
      fineAmount: (json['fine_amount'] is num) ? json['fine_amount'] as num : null,
      overtimeMinutes: (json['overtime_minutes'] is num) ? (json['overtime_minutes'] as num).toInt() : null,
      overtimeAmount: (json['overtime_amount'] is num) ? json['overtime_amount'] as num : null,
      overtimeNotice: (json['overtime_notice'] is String && (json['overtime_notice'] as String).trim().isNotEmpty)
          ? json['overtime_notice'] as String
          : null,
      permissionNotice: (json['permission_notice'] is String && (json['permission_notice'] as String).trim().isNotEmpty)
          ? json['permission_notice'] as String
          : null,
    );
  }
}
