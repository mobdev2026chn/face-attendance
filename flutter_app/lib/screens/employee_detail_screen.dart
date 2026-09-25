import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/employee_directory.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../utils/session.dart';

/// Detail for one face-enrolled employee: profile + face registration + today's
/// attendance, pulled live from HRMS (`GET /admin/face-kiosk/staff/:staffId`).
/// Monthly history is not available on the kiosk (it lives in the HRMS web portal).
class EmployeeDetailScreen extends StatefulWidget {
  /// HRMS staff id (Mongo `_id`).
  final String employeeId;
  final String name;
  final String? avatar;
  final String? email;

  const EmployeeDetailScreen({
    super.key,
    required this.employeeId,
    required this.name,
    this.avatar,
    this.email,
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
    _future = guardSession(context, ApiService.fetchEmployeeDetail(widget.employeeId));
  }

  void _reload() => setState(() => _future = guardSession(context, ApiService.fetchEmployeeDetail(widget.employeeId)));

  /// Admin: clear this employee's registered face so they can enroll again.
  /// Requires re-entering the admin password. After clearing they drop out of
  /// recognition until they enroll again.
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
            child: const Text('Continue', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Re-authorize this destructive action with the admin password.
    final password = await _promptAdminPassword();
    if (password == null || !mounted) return;

    setState(() => _clearing = true);
    final appState = context.read<AppState>();
    final authError = await appState.verifyAdminPassword(password);
    if (!mounted) return;
    if (authError != null) {
      setState(() => _clearing = false);
      _showError('Could not clear face', authError);
      return;
    }

    try {
      await ApiService.resetFace(widget.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared enrolled face for ${widget.name}.')),
      );
      // Tell the dashboard the roster changed, then leave this (now un-enrolled) detail.
      Navigator.of(context).pop(true);
    } on SessionExpired {
      if (mounted) await handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _clearing = false);
      _showError('Could not clear face', e.message);
    }
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  /// Ask the signed-in admin for their password only. Returns null if cancelled.
  Future<String?> _promptAdminPassword() {
    final loggedInEmail = context.read<AppState>().currentUser?.email ?? '';
    final passC = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin authentication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loggedInEmail.isNotEmpty
                  ? 'Enter the admin password for $loggedInEmail to clear this enrolled face.'
                  : 'Enter your admin password to clear this enrolled face.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passC,
              obscureText: true,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Admin password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final p = passC.text;
              if (p.isEmpty) return;
              Navigator.of(ctx).pop(p);
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
                _historyNote(),
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
    final name = d.get('name') ?? widget.name;
    final img = _avatarProvider(null);
    final rows = <List<String>>[
      ['Employee ID', d.get('employeeId') ?? '-'],
      ['Department', d.get('department') ?? '-'],
      ['Designation', d.get('designation') ?? '-'],
      ['Email', d.get('email') ?? widget.email ?? '-'],
      ['Face Enrolled', d.enrolled ? _fmtDate(d.get('enrolledAt')) : 'Not enrolled'],
      ['Face Samples', d.samples != null ? '${d.samples}' : '-'],
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
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
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
          if (d.enrolled) ...[
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
        ],
      ),
    );
  }

  Widget _todayCard(KioskToday? t) {
    String mins(int? v) => v == null ? '-' : '${v}m';
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
                _stat('IN', _fmtTime(t.checkInTime), AppColors.success),
                _stat('OUT', _fmtTime(t.checkOutTime), AppColors.danger),
                _stat('STATUS', t.statusLabel, t.onBreak ? Colors.orange : AppColors.textDark),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat('BREAK USED', mins(t.breakUsedMin), AppColors.textDark),
                _stat('ALLOWED', (t.breakAllowedMin ?? 0) > 0 ? mins(t.breakAllowedMin) : '-', AppColors.textDark),
                _stat(
                  'REMAINING',
                  (t.breakAllowedMin ?? 0) > 0 ? mins(t.breakRemainingMin) : '-',
                  (t.breakRemainingMin ?? 1) <= 0 && (t.breakAllowedMin ?? 0) > 0 ? AppColors.danger : AppColors.textDark,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyNote() {
    return _card(
      child: const Row(
        children: [
          Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Monthly history is available in the HRMS web portal.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
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
}

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final l = dt.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${l.day} ${months[l.month - 1]} ${l.year}';
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
