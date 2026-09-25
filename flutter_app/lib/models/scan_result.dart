/// Outcome of one kiosk face scan, mapped from HRMS `POST /admin/face-kiosk/scan`
/// (see ApiService.scanAttendance) into the action/status strings the scanner UI uses.
class ScanResult {
  /// HRMS staff id (Mongo `_id`) — used for detail / face reset.
  final String employeeId;

  /// HR employee code shown to people (staff.employeeId), when set.
  final String? employeeCode;
  final String employeeName;
  final String? department;
  final String? profilePhoto;
  final String? profilePhotoIso; // enrollment time — decides legacy 180° flip
  final String action; // Check-In, Check-Out, Break-In, Break-Out, Already-Checked-In, On-Break-Scan, Punch-Completed
  final String status; // Present, Punched Late, Punched Out Early
  final double confidence;
  final String? checkInTime;
  final String? checkOutTime;
  // Break policy snapshot (set for break actions) — drives the break-policy notification.
  final int? breakTotalMin;
  final int? breakAllowedMin; // null = unlimited / not configured
  final int? breakRemainingMin;
  final bool breakOver;
  final bool breakUnlimited;

  /// Exact HRMS policy notice for the action (e.g. break allowance exceeded).
  /// null when there is no notice. Shown verbatim — HRMS is the source of truth.
  final String? notice;
  // Fine snapshot from the HRMS punch response. Always based on the shift
  // allocated for that day — never hardcoded at the kiosk.
  final int? lateMinutes;
  final int? earlyMinutes;
  final num? fineAmount;
  // Overtime snapshot (not returned by the HRMS kiosk scan; kept for the UI).
  final int? overtimeMinutes;
  final num? overtimeAmount;
  final String? overtimeNotice;

  /// Permission policy notice — permission is not handled by the kiosk anymore,
  /// so these stay null.
  final String? permissionNotice;
  final String? permissionId;
  final String? permissionPhase;

  /// Follow-up actions the server offers after an 'Already-Checked-In' /
  /// 'On-Break-Scan' result (HRMS scan `options`: punch_out / break_start / break_end).
  final List<String> options;

  ScanResult({
    required this.employeeId,
    this.employeeCode,
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
    this.permissionId,
    this.permissionPhase,
    this.options = const [],
  });
}
