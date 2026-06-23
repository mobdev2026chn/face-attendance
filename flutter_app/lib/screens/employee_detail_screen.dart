import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/employee_directory.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
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

  /// Admin: clear this employee's enrolled face + profile image (canonical, in EHRMS)
  /// so they can re-enroll. Requires re-authenticating as an admin. After clearing
  /// they drop out of recognition until they enroll again.
  Future<void> _clearEnrolledFace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Enrolled Face'),
        content: Text(
          'Remove the registered face AND profile photo for "${widget.name}"?\n\n'
          'They will no longer be recognized at the kiosk until they enroll their '
          'face again. Attendance history is not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Re-authorize this destructive action with admin credentials.
    final creds = await _promptAdminCredentials();
    if (creds == null) return;

    setState(() => _clearing = true);
    try {
      await ApiService.clearEnrolledFace(
        employeeId: widget.employeeId,
        adminEmail: creds.email,
        adminPassword: creds.password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared enrolled face and profile photo for ${widget.name}.')),
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

  /// Collect admin credentials to authorize the clear. Pre-fills the email of the
  /// admin already signed in to the kiosk. Returns null if cancelled.
  Future<({String email, String password})?> _promptAdminCredentials() {
    final loggedInEmail = context.read<AppState>().currentUser?.email ?? '';
    final emailC = TextEditingController(text: loggedInEmail);
    final passC = TextEditingController();
    return showDialog<({String email, String password})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Confirm your admin credentials to clear this enrolled face.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailC,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Admin email'),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: passC,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final e = emailC.text.trim();
              final p = passC.text;
              if (e.isEmpty || p.isEmpty) return;
              Navigator.of(ctx).pop((email: e, password: p));
            },
            child: const Text('Confirm & Clear'),
          ),
        ],
      ),
    );
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
                const SizedBox(height: 14),
                _monthList(d),
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
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// The month's days as individual, tappable cards (newest first). Tapping a
  /// card expands it to show that day's break / permission / fine breakdown.
  Widget _monthList(EmployeeDetail d) {
    if (d.month.isEmpty) {
      return _card(
        child: const Text('No attendance this month.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      children: [
        for (final r in d.month.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DayCard(row: r),
          ),
      ],
    );
  }

  String _money(double v) => _fmtMoney(v);

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

  String _dateOnly(String? iso) => _fmtDate(iso);

  String _timeOnly(String? iso) => _fmtTime(iso);
}

// --- Shared formatters (used by the screen and the per-day expandable cards) ---

String _fmtMoney(double v) {
  if (v <= 0) return '₹0';
  return v == v.roundToDouble() ? '₹${v.toInt()}' : '₹${v.toStringAsFixed(2)}';
}

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

String _fmtTime(String? iso) {
  if (iso == null || iso.isEmpty) return '--';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

String _weekday(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[dt.weekday - 1];
}

/// A single day in the month list. Collapsed it shows date + punch in/out +
/// status + a fine badge; tapping expands it to the break, permission and fine
/// breakdown for that date.
class _DayCard extends StatefulWidget {
  final AttendanceRow row;
  const _DayCard({required this.row});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _open = false;

  AttendanceRow get r => widget.row;

  bool get _hasDetail =>
      r.breaks.isNotEmpty || !r.permission.isEmpty || r.totalFine > 0 || r.lateMin > 0 || r.earlyMin > 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _hasDetail ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _header(),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: _detail(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final fineColor = r.totalFine > 0 ? AppColors.danger : AppColors.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(_fmtDate(r.date),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  const SizedBox(width: 8),
                  Text(_weekday(r.date), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            Text(r.status ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            if (_hasDetail)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: AppColors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _miniStat('IN', _fmtTime(r.punchIn), AppColors.success),
            _miniStat('OUT', _fmtTime(r.punchOut), AppColors.danger),
            _miniStat('FINE', _fmtMoney(r.totalFine), fineColor),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color color) {
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

  Widget _detail() {
    final sections = <Widget>[];

    // Breaks
    if (r.breaks.isNotEmpty) {
      sections.add(_sectionTitle('Breaks', '${r.breakCount} · ${r.breakMin}m'));
      for (var i = 0; i < r.breaks.length; i++) {
        final b = r.breaks[i];
        sections.add(_detailRow(
          'Break ${i + 1}',
          '${_fmtTime(b.start)} – ${_fmtTime(b.end)} · ${b.durationMin}m',
          b.fine > 0 ? 'Fine ${_fmtMoney(b.fine)}' : null,
        ));
      }
    }

    // Permission
    final p = r.permission;
    if (!p.isEmpty) {
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 10));
      sections.add(_sectionTitle('Permission', p.consumedMin > 0 ? '${p.consumedMin}m used' : ''));
      if (p.lateMin > 0) sections.add(_detailRow('Late-in permission', '${p.lateMin}m', null));
      if (p.earlyMin > 0) sections.add(_detailRow('Early-out permission', '${p.earlyMin}m', null));
      if (p.approvedMin > 0) sections.add(_detailRow('Approved', '${p.approvedMin}m', null));
      if (p.remainingMin > 0) sections.add(_detailRow('Remaining', '${p.remainingMin}m', null));
      if (p.fineMin > 0 || p.fineAmount > 0) {
        sections.add(_detailRow('Exceeded', '${p.fineMin}m', p.fineAmount > 0 ? 'Fine ${_fmtMoney(p.fineAmount)}' : null));
      }
    }

    // Fine breakdown
    final fineRows = <Widget>[];
    if (r.lateMin > 0) fineRows.add(_detailRow('Late', '${r.lateMin}m', null));
    if (r.earlyMin > 0) fineRows.add(_detailRow('Early out', '${r.earlyMin}m', null));
    if (r.breakFine > 0 || r.breakFineMin > 0) {
      fineRows.add(_detailRow('Break fine', '${r.breakFineMin}m', _fmtMoney(r.breakFine)));
    }
    if (r.permission.fineAmount > 0 || r.permission.fineMin > 0) {
      fineRows.add(_detailRow('Permission fine', '${r.permission.fineMin}m', _fmtMoney(r.permission.fineAmount)));
    }
    if (fineRows.isNotEmpty || r.totalFine > 0) {
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 10));
      sections.add(_sectionTitle('Fine', _fmtMoney(r.totalFine)));
      sections.addAll(fineRows);
    }

    if (sections.isEmpty) {
      return const Text('No break, permission or fine for this day.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections);
  }

  Widget _sectionTitle(String title, String trailing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.primary)),
          if (trailing.isNotEmpty)
            Text(trailing, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, String? trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          ),
          if (trailing != null)
            Text(trailing, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
        ],
      ),
    );
  }
}
