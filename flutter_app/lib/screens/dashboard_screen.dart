import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/employee_directory.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/session.dart';
import 'employee_detail_screen.dart';

/// Dashboard: the face-enrolled employee roster (HRMS). Tapping a row opens the
/// detail (profile + today). All data is pulled live from HRMS
/// `GET /admin/face-kiosk/staff` — there is no local kiosk store.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<EnrolledEmployee>> _future;
  String _query = '';
  int _displayedCount = 15;

  @override
  void initState() {
    super.initState();
    _future = guardSession(context, ApiService.fetchEnrolledEmployees());
  }

  void _refresh() => setState(() {
    _displayedCount = 15;
    _future = guardSession(context, ApiService.fetchEnrolledEmployees());
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<EnrolledEmployee>>(
          future: _future,
          builder: (context, snap) {
            final waiting = snap.connectionState == ConnectionState.waiting;
            final all = snap.data ?? const <EnrolledEmployee>[];
            final q = _query.toLowerCase();
            final list = q.isEmpty
                ? all
                : all
                    .where((e) =>
                        e.name.toLowerCase().contains(q) ||
                        (e.email ?? '').toLowerCase().contains(q) ||
                        (e.department ?? '').toLowerCase().contains(q) ||
                        e.employeeId.toLowerCase().contains(q) ||
                        (e.hrEmployeeId ?? '').toLowerCase().contains(q))
                    .toList();

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _banner(all.length),
                const SizedBox(height: 12),
                _todaySummary(all, waiting),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search name, ID, department…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _displayedCount = 15;
                  }),
                ),
                const SizedBox(height: 18),
                const Text('ENROLLED EMPLOYEES · HRMS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 12),
                if (waiting)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                else if (snap.hasError)
                  _emptyOrError('Could not load employees.', retry: true)
                else if (all.isEmpty)
                  _emptyOrError('No one has enrolled their face yet.')
                else if (list.isEmpty)
                  _emptyOrError('No matching employees.')
                else ...[
                  ...list.take(_displayedCount).map(_tile),
                  if (list.length > _displayedCount)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _displayedCount += 15;
                            });
                          },
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text(
                            'Load More (${list.length - _displayedCount} remaining)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.05),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _banner(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Live from HRMS · enrolled employees',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  /// Today's per-day, user-wise attendance snapshot (live from HRMS): how many
  /// enrolled employees are present, late, currently on break, and have taken a
  /// permission today. Counts are derived from the enrolled roster itself, so the
  /// card and the list below always agree.
  Widget _todaySummary(List<EnrolledEmployee> all, bool loading) {
    final present = all.where((e) => e.presentToday).length;
    final late = all.where((e) => e.lateToday).length;
    final onBreak = all.where((e) => e.onBreak).length;
    final permission = all.where((e) => e.permissionToday).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('TODAY',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.primary)),
              const Spacer(),
              if (loading)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryStat('Present', present, Icons.how_to_reg, AppColors.success, loading),
              _summaryStat('Late', late, Icons.schedule, AppColors.danger, loading),
              _summaryStat('On Break', onBreak, Icons.free_breakfast, Colors.orange, loading),
              _summaryStat('Permission', permission, Icons.event_available, AppColors.primary, loading),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, int value, IconData icon, Color color, bool loading) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            loading ? '–' : '$value',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _tile(EnrolledEmployee e) {
    final img = _avatar(e.avatar);
    final subtitle = [e.hrEmployeeId, e.designation, e.department].where((s) => s != null && s.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primary,
          backgroundImage: img,
          child: img == null
              ? Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))
              : null,
        ),
        title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
        subtitle: Text(
          subtitle.isNotEmpty ? subtitle : (e.email ?? ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => EmployeeDetailScreen(employeeId: e.employeeId, name: e.name, avatar: e.avatar, email: e.email),
          ));
          // Face was cleared → the roster changed; reload the enrolled list.
          if (changed == true) _refresh();
        },
      ),
    );
  }

  ImageProvider? _avatar(String? a) {
    if (a == null || a.isEmpty) return null;
    if (a.startsWith('http')) return NetworkImage(a);
    try {
      return MemoryImage(base64Decode(a.contains(',') ? a.split(',').last : a));
    } catch (_) {
      return null;
    }
  }

  Widget _emptyOrError(String msg, {bool retry = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Text(msg, style: const TextStyle(color: AppColors.textMuted)),
            if (retry) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
