// One month of EHRMS attendance + break details for a linked employee,
// as returned by GET /api/employees/:id/ehrms-month.

class MonthBreak {
  final String? start;
  final String? end;
  final int? minutes;

  MonthBreak({this.start, this.end, this.minutes});

  factory MonthBreak.fromJson(Map<String, dynamic> j) => MonthBreak(
        start: j['start']?.toString(),
        end: j['end']?.toString(),
        minutes: j['minutes'] is num ? (j['minutes'] as num).toInt() : null,
      );
}

class MonthDay {
  final String? date; // ISO date string
  final String? status;
  final String? leaveType;
  final String? checkIn;
  final String? checkOut;
  final int lateMinutes;
  final int earlyMinutes;
  final double fineAmount;
  final int breakCount;
  final int breakMinutes;
  final List<MonthBreak> breaks;

  MonthDay({
    this.date,
    this.status,
    this.leaveType,
    this.checkIn,
    this.checkOut,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.fineAmount = 0,
    this.breakCount = 0,
    this.breakMinutes = 0,
    this.breaks = const [],
  });

  factory MonthDay.fromJson(Map<String, dynamic> j) => MonthDay(
        date: j['date']?.toString(),
        status: j['status']?.toString(),
        leaveType: j['leave_type']?.toString(),
        checkIn: j['check_in']?.toString(),
        checkOut: j['check_out']?.toString(),
        lateMinutes: (j['late_minutes'] as num?)?.toInt() ?? 0,
        earlyMinutes: (j['early_minutes'] as num?)?.toInt() ?? 0,
        fineAmount: (j['fine_amount'] as num?)?.toDouble() ?? 0,
        breakCount: (j['break_count'] as num?)?.toInt() ?? 0,
        breakMinutes: (j['break_minutes'] as num?)?.toInt() ?? 0,
        breaks: (j['breaks'] as List<dynamic>? ?? [])
            .map((e) => MonthBreak.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MonthAttendance {
  final String employeeId;
  final String? employeeName;
  final int year;
  final int month;
  final List<MonthDay> days;

  MonthAttendance({
    required this.employeeId,
    this.employeeName,
    required this.year,
    required this.month,
    required this.days,
  });

  factory MonthAttendance.fromJson(Map<String, dynamic> j) => MonthAttendance(
        employeeId: j['employee_id']?.toString() ?? '',
        employeeName: j['employee_name']?.toString(),
        year: (j['year'] as num?)?.toInt() ?? 0,
        month: (j['month'] as num?)?.toInt() ?? 0,
        days: (j['days'] as List<dynamic>? ?? [])
            .map((e) => MonthDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // Aggregate helpers for the summary header.
  int get presentDays =>
      days.where((d) => (d.status ?? '').toLowerCase().contains('present') ||
          (d.status ?? '').toLowerCase() == 'approved').length;
  int get totalBreakMinutes =>
      days.fold(0, (sum, d) => sum + d.breakMinutes);
  double get totalFine => days.fold(0.0, (sum, d) => sum + d.fineAmount);
}
