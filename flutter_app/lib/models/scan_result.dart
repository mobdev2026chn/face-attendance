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
    );
  }
}
