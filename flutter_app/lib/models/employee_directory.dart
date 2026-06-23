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
  // Today's live attendance snapshot (per-user) — drives the dashboard summary card.
  final bool presentToday;
  final bool lateToday;
  final bool onBreak;
  final bool permissionToday;

  EnrolledEmployee({
    required this.employeeId,
    required this.name,
    this.email,
    this.department,
    this.designation,
    this.avatar,
    this.enrolledAt,
    this.status,
    this.presentToday = false,
    this.lateToday = false,
    this.onBreak = false,
    this.permissionToday = false,
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
        presentToday: j['present_today'] == true,
        lateToday: j['late_today'] == true,
        onBreak: j['on_break'] == true,
        permissionToday: j['permission_today'] == true,
      );
}

/// One break session within a day (start/end/duration/fine), shown when a day
/// card is expanded in the detail screen.
class BreakSession {
  final String? start;
  final String? end;
  final int durationMin;
  final int fineMin;
  final double fine;

  BreakSession({this.start, this.end, this.durationMin = 0, this.fineMin = 0, this.fine = 0});

  factory BreakSession.fromJson(Map<String, dynamic> j) => BreakSession(
        start: j['start']?.toString(),
        end: j['end']?.toString(),
        durationMin: j['duration_min'] is num ? (j['duration_min'] as num).toInt() : 0,
        fineMin: j['fine_min'] is num ? (j['fine_min'] as num).toInt() : 0,
        fine: j['fine'] is num ? (j['fine'] as num).toDouble() : 0,
      );
}

/// Permission usage + fine for a day (custom step-outs / late-in / early-out).
class PermissionDetail {
  final int consumedMin;
  final int approvedMin;
  final int remainingMin;
  final int lateMin;
  final int earlyMin;
  final int fineMin;
  final double fineAmount;

  PermissionDetail({
    this.consumedMin = 0,
    this.approvedMin = 0,
    this.remainingMin = 0,
    this.lateMin = 0,
    this.earlyMin = 0,
    this.fineMin = 0,
    this.fineAmount = 0,
  });

  /// True when there's nothing meaningful to show for this day.
  bool get isEmpty =>
      consumedMin == 0 && approvedMin == 0 && lateMin == 0 && earlyMin == 0 && fineMin == 0 && fineAmount == 0;

  factory PermissionDetail.fromJson(Map<String, dynamic> j) {
    int i(dynamic v) => v is num ? v.toInt() : 0;
    return PermissionDetail(
      consumedMin: i(j['consumed_min']),
      approvedMin: i(j['approved_min']),
      remainingMin: i(j['remaining_min']),
      lateMin: i(j['late_min']),
      earlyMin: i(j['early_min']),
      fineMin: i(j['fine_min']),
      fineAmount: j['fine_amount'] is num ? (j['fine_amount'] as num).toDouble() : 0,
    );
  }
}

/// One attendance day row (today or a month entry) in the detail screen.
class AttendanceRow {
  final String? date;
  final String? punchIn;
  final String? punchOut;
  final String? status;
  final double? workHours;
  final int breakMin;
  final int breakCount;
  final double breakFine;
  final int breakFineMin;
  final int lateMin;
  final int earlyMin;
  final double fine;
  final double totalFine;
  final List<BreakSession> breaks;
  final PermissionDetail permission;

  AttendanceRow({
    this.date,
    this.punchIn,
    this.punchOut,
    this.status,
    this.workHours,
    this.breakMin = 0,
    this.breakCount = 0,
    this.breakFine = 0,
    this.breakFineMin = 0,
    this.lateMin = 0,
    this.earlyMin = 0,
    this.fine = 0,
    this.totalFine = 0,
    this.breaks = const [],
    PermissionDetail? permission,
  }) : permission = permission ?? PermissionDetail();

  static int _i(dynamic v) => v is num ? v.toInt() : 0;
  static double _d(dynamic v) => v is num ? v.toDouble() : 0;

  factory AttendanceRow.fromJson(Map<String, dynamic> j) => AttendanceRow(
        date: j['date']?.toString(),
        punchIn: j['punch_in']?.toString(),
        punchOut: j['punch_out']?.toString(),
        status: j['status']?.toString(),
        workHours: j['work_hours'] is num ? (j['work_hours'] as num).toDouble() : null,
        breakMin: _i(j['break_min']),
        breakCount: _i(j['break_count']),
        breakFine: _d(j['break_fine']),
        breakFineMin: _i(j['break_fine_min']),
        lateMin: _i(j['late_min']),
        earlyMin: _i(j['early_min']),
        fine: _d(j['fine']),
        totalFine: _d(j['total_fine']),
        breaks: (j['breaks'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(BreakSession.fromJson)
            .toList(),
        permission: (j['permission'] is Map<String, dynamic>)
            ? PermissionDetail.fromJson(j['permission'] as Map<String, dynamic>)
            : null,
      );
}

/// Month-to-date totals for breaks taken + fines.
class MonthTotals {
  final int breakMin;
  final int breakCount;
  final double breakFine;
  final double fine;

  MonthTotals({this.breakMin = 0, this.breakCount = 0, this.breakFine = 0, this.fine = 0});

  factory MonthTotals.fromJson(Map<String, dynamic> j) => MonthTotals(
        breakMin: j['break_min'] is num ? (j['break_min'] as num).toInt() : 0,
        breakCount: j['break_count'] is num ? (j['break_count'] as num).toInt() : 0,
        breakFine: j['break_fine'] is num ? (j['break_fine'] as num).toDouble() : 0,
        fine: j['fine'] is num ? (j['fine'] as num).toDouble() : 0,
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
  final MonthTotals totals;

  EmployeeDetail({
    required this.profile,
    this.today,
    this.month = const [],
    this.presentDays = 0,
    this.monthLabel,
    MonthTotals? totals,
  }) : totals = totals ?? MonthTotals();

  String? get(String key) => profile[key]?.toString();

  factory EmployeeDetail.fromJson(Map<String, dynamic> j) {
    final t = j['today'];
    final tot = j['totals'];
    return EmployeeDetail(
      profile: (j['profile'] as Map<String, dynamic>?) ?? const {},
      today: (t is Map<String, dynamic>) ? AttendanceRow.fromJson(t) : null,
      month: (j['month'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AttendanceRow.fromJson)
          .toList(),
      presentDays: j['present_days'] is num ? (j['present_days'] as num).toInt() : 0,
      monthLabel: j['month_label']?.toString(),
      totals: (tot is Map<String, dynamic>) ? MonthTotals.fromJson(tot) : null,
    );
  }
}
