class AttendanceRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final String action; // in, out, break_in, break_out
  final String status;
  final DateTime timestamp;

  AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.action,
    required this.status,
    required this.timestamp,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: (json['_id'] ?? '').toString(),
      employeeId: (json['employeeId'] ?? '').toString(),
      employeeName: (json['employeeName'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      // Stored timestamps are UTC (ISO 8601 with 'Z'); convert to device-local
      // time so punch times display in the correct local timezone (e.g. IST).
      timestamp: (DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toLocal()) ?? DateTime.now(),
    );
  }
}
