/// One EHRMS-enrolled employee, as listed on the face-app dashboard.
/// Backed by GET /api/employees/enrolled (proxied to EHRMS kiosk-enrolled).
class EnrolledEmployee {
  final String employeeId;
  final String name;
  final String? email;
  final String? department;
  final String? designation;
  final String? avatar;
  final String? enrolledAt;
  final String? status;

  EnrolledEmployee({
    required this.employeeId,
    required this.name,
    this.email,
    this.department,
    this.designation,
    this.avatar,
    this.enrolledAt,
    this.status,
  });

  factory EnrolledEmployee.fromJson(Map<String, dynamic> j) => EnrolledEmployee(
        employeeId: (j['employee_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        email: j['email']?.toString(),
        department: j['department']?.toString(),
        designation: j['designation']?.toString(),
        avatar: j['avatar']?.toString(),
        enrolledAt: j['enrolled_at']?.toString(),
        status: j['status']?.toString(),
      );
}

/// One attendance day row (today or a month entry) in the detail screen.
class AttendanceRow {
  final String? date;
  final String? punchIn;
  final String? punchOut;
  final String? status;
  final double? workHours;
  final int breakMin;

  AttendanceRow({
    this.date,
    this.punchIn,
    this.punchOut,
    this.status,
    this.workHours,
    this.breakMin = 0,
  });

  factory AttendanceRow.fromJson(Map<String, dynamic> j) => AttendanceRow(
        date: j['date']?.toString(),
        punchIn: j['punch_in']?.toString(),
        punchOut: j['punch_out']?.toString(),
        status: j['status']?.toString(),
        workHours: j['work_hours'] is num ? (j['work_hours'] as num).toDouble() : null,
        breakMin: j['break_min'] is num ? (j['break_min'] as num).toInt() : 0,
      );
}

/// Full detail for one employee: profile + today + this month's attendance.
/// Backed by GET /api/employees/:id/detail (proxied to EHRMS kiosk-employee).
class EmployeeDetail {
  final Map<String, dynamic> profile;
  final AttendanceRow? today;
  final List<AttendanceRow> month;
  final int presentDays;
  final String? monthLabel;

  EmployeeDetail({
    required this.profile,
    this.today,
    this.month = const [],
    this.presentDays = 0,
    this.monthLabel,
  });

  String? get(String key) => profile[key]?.toString();

  factory EmployeeDetail.fromJson(Map<String, dynamic> j) {
    final t = j['today'];
    return EmployeeDetail(
      profile: (j['profile'] as Map<String, dynamic>?) ?? const {},
      today: (t is Map<String, dynamic>) ? AttendanceRow.fromJson(t) : null,
      month: (j['month'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AttendanceRow.fromJson)
          .toList(),
      presentDays: j['present_days'] is num ? (j['present_days'] as num).toInt() : 0,
      monthLabel: j['month_label']?.toString(),
    );
  }
}
