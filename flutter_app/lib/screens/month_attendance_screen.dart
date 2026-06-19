import 'package:flutter/material.dart';

import '../models/month_attendance.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// One-month attendance + break view for a linked employee (data from EHRMS).
class MonthAttendanceScreen extends StatefulWidget {
  final String employeeId;
  final String? employeeName;

  const MonthAttendanceScreen({
    super.key,
    required this.employeeId,
    this.employeeName,
  });

  @override
  State<MonthAttendanceScreen> createState() => _MonthAttendanceScreenState();
}

class _MonthAttendanceScreenState extends State<MonthAttendanceScreen> {
  late DateTime _month; // first day of the displayed month
  late Future<MonthAttendance> _future;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _future = _load();
  }

  Future<MonthAttendance> _load() => ApiService.fetchEhrmsMonth(
        employeeId: widget.employeeId,
        year: _month.year,
        month: _month.month,
      );

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    // Don't allow navigating into the future.
    final now = DateTime(DateTime.now().year, DateTime.now().month);
    if (next.isAfter(now)) return;
    setState(() {
      _month = next;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.employeeName ?? widget.employeeId),
      ),
      body: Column(
        children: [
          _buildMonthSwitcher(),
          Expanded(
            child: FutureBuilder<MonthAttendance>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _buildError(snap.error.toString());
                }
                final data = snap.data!;
                final days = [...data.days]
                  ..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
                if (days.isEmpty) {
                  return const Center(
                    child: Text('No attendance records this month.',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(
                  children: [
                    _buildSummary(data),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          setState(() => _future = _load());
                          await _future;
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: days.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildDayCard(days[i]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSwitcher() {
    final now = DateTime(DateTime.now().year, DateTime.now().month);
    final atCurrent = !_month.isBefore(now);
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            '${_monthNames[_month.month - 1]} ${_month.year}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                color: atCurrent ? Colors.white38 : Colors.white),
            onPressed: atCurrent ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(MonthAttendance data) {
    String hm(int min) {
      final h = min ~/ 60, m = min % 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Present', '${data.presentDays}', AppColors.success),
          _summaryItem('Break', hm(data.totalBreakMinutes), AppColors.primaryDark),
          _summaryItem(
              'Fine', '₹${data.totalFine.toStringAsFixed(0)}', AppColors.danger),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _buildDayCard(MonthDay d) {
    final dateLabel = _formatDate(d.date);
    final status = d.status ?? '—';
    final statusColor = _statusColor(status, d.leaveType);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dateLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  d.leaveType?.isNotEmpty == true ? d.leaveType! : status,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _timeChip(Icons.login, 'In', _formatTime(d.checkIn),
                  AppColors.success),
              const SizedBox(width: 8),
              _timeChip(Icons.logout, 'Out', _formatTime(d.checkOut),
                  AppColors.danger),
            ],
          ),
          if (d.breakCount > 0) ...[
            const Divider(height: 18),
            Row(
              children: [
                const Icon(Icons.free_breakfast_outlined,
                    size: 16, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Text(
                  '${d.breakCount} break${d.breakCount > 1 ? 's' : ''} · ${d.breakMinutes}m total',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...d.breaks.map((b) => Padding(
                  padding: const EdgeInsets.only(left: 22, top: 2),
                  child: Text(
                    '${_formatTime(b.start)} → ${_formatTime(b.end)}'
                    '${b.minutes != null ? '  (${b.minutes}m)' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                )),
          ],
          if (d.lateMinutes > 0 || d.earlyMinutes > 0 || d.fineAmount > 0) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (d.lateMinutes > 0) 'Late ${d.lateMinutes}m',
                if (d.earlyMinutes > 0) 'Early ${d.earlyMinutes}m',
                if (d.fineAmount > 0) 'Fine ₹${d.fineAmount.toStringAsFixed(0)}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.lightBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text('$label ',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _future = _load()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Formatting ────────────────────────────────────────────────────────────
  Color _statusColor(String status, String? leaveType) {
    final s = status.toLowerCase();
    if ((leaveType ?? '').isNotEmpty) return AppColors.primaryDark;
    if (s.contains('present') || s == 'approved') return AppColors.success;
    if (s.contains('absent')) return AppColors.danger;
    if (s.contains('pending')) return AppColors.primaryDark;
    return AppColors.textMuted;
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${wd[dt.weekday - 1]}, ${dt.day} ${_monthNames[dt.month - 1]}';
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}
