import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/employee_directory.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Full detail for one EHRMS-enrolled employee: profile + today's attendance +
/// this month's attendance rows. All data is pulled live from EHRMS (the source of
/// truth) via the face backend; nothing is stored on the kiosk.
class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;
  final String name;
  final String? avatar;

  const EmployeeDetailScreen({
    super.key,
    required this.employeeId,
    required this.name,
    this.avatar,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late Future<EmployeeDetail> _future;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchEmployeeDetail(widget.employeeId);
  }

  void _reload() => setState(() => _future = ApiService.fetchEmployeeDetail(widget.employeeId));

  /// Admin: clear this employee's enrolled face (canonical, in EHRMS) so they can
  /// re-enroll. After clearing they drop out of recognition until they enroll again.
  Future<void> _clearEnrolledFace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Enrolled Face'),
        content: Text(
          'Remove the registered face for "${widget.name}"?\n\n'
          'They will no longer be recognized at the kiosk until they enroll their '
          'face again. Attendance history is not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear Face', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearing = true);
    try {
      await ApiService.clearEnrolledFace(employeeId: widget.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared enrolled face for ${widget.name}.')),
      );
      // Tell the dashboard the roster changed, then leave this (now un-enrolled) detail.
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _clearing = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Could not clear face'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Employee Detail', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: FutureBuilder<EmployeeDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return _errorState();
          }
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _profileCard(d),
                const SizedBox(height: 14),
                _todayCard(d.today),
                const SizedBox(height: 14),
                _monthCard(d),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 10),
          const Text('Could not load detail.', style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _reload, child: const Text('Retry')),
        ],
      ),
    );
  }

  ImageProvider? _avatarProvider(String? avatar) {
    final a = avatar ?? widget.avatar;
    if (a == null || a.isEmpty) return null;
    if (a.startsWith('http')) return NetworkImage(a);
    try {
      return MemoryImage(base64Decode(a.contains(',') ? a.split(',').last : a));
    } catch (_) {
      return null;
    }
  }

  Widget _profileCard(EmployeeDetail d) {
    final p = d.profile;
    final img = _avatarProvider(d.get('avatar'));
    final rows = <List<String>>[
      ['Employee ID', d.get('employee_id') ?? '-'],
      ['Department', d.get('department') ?? '-'],
      ['Designation', d.get('designation') ?? '-'],
      ['Email', d.get('email') ?? '-'],
      ['Phone', d.get('phone') ?? '-'],
      ['Shift', d.get('shift') ?? '-'],
      ['Type', d.get('staff_type') ?? '-'],
      ['Status', d.get('status') ?? '-'],
      ['Gender', d.get('gender') ?? '-'],
      ['Blood Group', d.get('blood_group') ?? '-'],
      ['Joined', _dateOnly(d.get('joining_date'))],
      ['Face Enrolled', _dateOnly(d.get('enrolled_at'))],
    ]..removeWhere((r) => r[1] == '-' || r[1].isEmpty);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary,
                backgroundImage: img,
                child: img == null
                    ? Text(
                        (p['name']?.toString().isNotEmpty == true) ? p['name'].toString()[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.get('name') ?? widget.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                    if ((d.get('designation') ?? '').isNotEmpty)
                      Text(d.get('designation')!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(r[0], style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ),
                    Expanded(
                      child: Text(r[1],
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 6),
          const Divider(height: 18),
          // Admin: clear the registered face so this person can enroll a fresh one.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _clearing ? null : _clearEnrolledFace,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _clearing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                  : const Icon(Icons.face_retouching_off, size: 18),
              label: Text(_clearing ? 'Clearing…' : 'Clear Enrolled Face'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todayCard(AttendanceRow? t) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.primary)),
          const SizedBox(height: 10),
          if (t == null)
            const Text('No attendance today.', style: TextStyle(color: AppColors.textMuted))
          else ...[
            Row(
              children: [
                _stat('IN', _timeOnly(t.punchIn), AppColors.success),
                _stat('OUT', _timeOnly(t.punchOut), AppColors.danger),
                _stat('STATUS', t.status ?? '-', AppColors.textDark),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat('BREAKS', '${t.breakCount} · ${t.breakMin}m', AppColors.textDark),
                _stat('BREAK FINE', _money(t.breakFine), t.breakFine > 0 ? AppColors.danger : AppColors.textDark),
                _stat('FINE', _money(t.fine), t.fine > 0 ? AppColors.danger : AppColors.textDark),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _monthCard(EmployeeDetail d) {
    final tot = d.totals;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text((d.monthLabel ?? 'THIS MONTH').toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.primary)),
              Text('${d.presentDays} present', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          // Month-to-date totals: breaks taken + fines.
          Row(
            children: [
              _stat('BREAKS', '${tot.breakCount} · ${tot.breakMin}m', AppColors.textDark),
              _stat('BREAK FINE', _money(tot.breakFine), tot.breakFine > 0 ? AppColors.danger : AppColors.textDark),
              _stat('TOTAL FINE', _money(tot.fine), tot.fine > 0 ? AppColors.danger : AppColors.textDark),
            ],
          ),
          const Divider(height: 22),
          if (d.month.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No attendance this month.', style: TextStyle(color: AppColors.textMuted)),
            )
          else
            ...d.month.reversed.map(_monthRow),
        ],
      ),
    );
  }

  Widget _monthRow(AttendanceRow r) {
    final extras = <String>[];
    if (r.breakCount > 0 || r.breakMin > 0) {
      extras.add('${r.breakCount} break${r.breakCount == 1 ? '' : 's'} · ${r.breakMin}m');
    }
    if (r.lateMin > 0) extras.add('late ${r.lateMin}m');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 92, child: Text(_dateOnly(r.date), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textDark))),
              Expanded(child: Text('IN ${_timeOnly(r.punchIn)}', style: const TextStyle(fontSize: 12, color: AppColors.success))),
              Expanded(child: Text('OUT ${_timeOnly(r.punchOut)}', style: const TextStyle(fontSize: 12, color: AppColors.danger))),
              Text(r.status ?? '-', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          if (extras.isNotEmpty || r.fine > 0)
            Padding(
              padding: const EdgeInsets.only(left: 92, top: 2),
              child: Row(
                children: [
                  Expanded(child: Text(extras.join(' · '), style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted))),
                  if (r.fine > 0)
                    Text('Fine ${_money(r.fine)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _money(double v) {
    if (v <= 0) return '₹0';
    return v == v.roundToDouble() ? '₹${v.toInt()}' : '₹${v.toStringAsFixed(2)}';
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  String _dateOnly(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _timeOnly(String? iso) {
    if (iso == null || iso.isEmpty) return '--';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
  }
}
