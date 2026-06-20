import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/selfie_orientation.dart';
import '../models/ehrms_overview.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/avatar_orientation.dart';
import 'month_attendance_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Combined dashboard data: every enrolled face + the EHRMS attendance overview.
class _DashboardData {
  final List<EnrolledFace> faces;
  final EhrmsOverview overview;
  _DashboardData(this.faces, this.overview);
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _dataFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_DashboardData> _load() async {
    // Fetch both in parallel: the full enrolled-face roster + live EHRMS attendance.
    final results = await Future.wait([
      ApiService.fetchEnrolledFaces(),
      ApiService.fetchEhrmsOverview(),
    ]);
    return _DashboardData(results[0] as List<EnrolledFace>, results[1] as EhrmsOverview);
  }

  void _refresh() {
    setState(() {
      _dataFuture = _load();
    });
  }

  // Linking removed: the kiosk no longer enrolls/links employees. EHRMS identifies the
  // face against its canonical enrollment and mints a short-lived token for the punch,
  // so there is no per-employee link/unlink step here anymore.


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        // No "Link all" — the kiosk no longer links employees; EHRMS identifies the
        // face against its enrolled store and mints a token for the punch on the fly.
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<_DashboardData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final waiting = snapshot.connectionState == ConnectionState.waiting;
            final data = snapshot.data;
            final overview = data?.overview;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Source banner — attendance is served live from EHRMS.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_done, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Live from EHRMS${overview != null && overview.ehrmsBaseUrl.isNotEmpty ? ' · ${_host(overview.ehrmsBaseUrl)}' : ''}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _StatCard(label: 'Enrolled', value: '${data?.faces.length ?? 0}')),
                    const SizedBox(width: 8),
                    Expanded(child: _StatCard(label: 'Linked', value: '${overview?.linkedEmployees ?? 0}')),
                    const SizedBox(width: 8),
                    Expanded(child: _StatCard(label: 'Present', value: '${overview?.presentToday ?? 0}')),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('SEARCH ATTENDANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(hintText: 'Search username...', prefixIcon: Icon(Icons.search)),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 20),
                const Text('ALL ENROLLED FACES · EHRMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
                const SizedBox(height: 12),

                if (waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                else if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('Could not load dashboard data.', style: TextStyle(color: AppColors.textMuted))),
                  )
                else
                  ..._buildRows(data),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildRows(_DashboardData? data) {
    if (data == null || data.faces.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text('No enrolled faces yet.', style: TextStyle(color: AppColors.textMuted)),
          ),
        ),
      ];
    }

    // Index live EHRMS attendance by employeeId for quick lookup per face.
    final byId = {for (final e in data.overview.employees) e.employeeId: e};

    final q = _searchQuery.toLowerCase();
    final faces = data.faces
        .where((f) => f.fullName.toLowerCase().contains(q) || (f.ehrmsEmail ?? '').toLowerCase().contains(q))
        .toList();

    if (faces.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('No matching faces.', style: TextStyle(color: AppColors.textMuted))),
        ),
      ];
    }

    // Linked faces (with live attendance) first, then unlinked.
    faces.sort((a, b) {
      if (a.ehrmsLinked != b.ehrmsLinked) return a.ehrmsLinked ? -1 : 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });

    return faces.map((f) {
      if (f.ehrmsLinked && byId.containsKey(f.employeeId)) {
        return _employeeCard(byId[f.employeeId]!);
      }
      return _unlinkedRow(f);
    }).toList();
  }

  /// Row for an enrolled face not yet linked to EHRMS — offers a one-tap Link.
  Widget _unlinkedRow(EnrolledFace f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.fullName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const Text('Enrolled in EHRMS', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          // No "Link" button — identification + punch go through EHRMS directly.
        ],
      ),
    );
  }

  Widget _employeeCard(EhrmsEmployee e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: e.error != null
          ? Row(children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text('${e.employeeName}: ${e.error}', style: const TextStyle(fontSize: 11, color: AppColors.danger))),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Small validated punch faces.
                    _FaceCircle(label: 'IN', source: e.punchInSelfie ?? e.referencePhoto, matchScore: e.punchInFaceMatch, captureIso: e.punchInIso),
                    const SizedBox(width: 6),
                    _FaceCircle(label: 'OUT', source: e.punchOutSelfie, matchScore: e.punchOutFaceMatch, captureIso: e.punchOutIso),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.employeeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
                          if (e.ehrmsEmail != null && e.ehrmsEmail!.isNotEmpty)
                            Text(e.ehrmsEmail!, style: const TextStyle(fontSize: 10, color: AppColors.textMuted), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(children: [
                              _timeCol('IN', _timeOnly(e.punchIn), e.punchIn != null ? AppColors.success : AppColors.textMuted),
                              const SizedBox(width: 14),
                              _timeCol('OUT', _timeOnly(e.punchOut), e.punchOut != null ? AppColors.danger : AppColors.textMuted),
                              const SizedBox(width: 14),
                              _timeCol('BREAK', _breakText(e), _breakColor(e)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Monthly attendance & breaks',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 18,
                      icon: const Icon(Icons.calendar_month, color: AppColors.primaryDark),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MonthAttendanceScreen(
                            employeeId: e.employeeId,
                            employeeName: e.employeeName,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(e.presentToday ? 'Present' : 'Not punched', e.presentToday ? AppColors.success : AppColors.textMuted),
                    if (e.onBreak) _chip('On Break', AppColors.danger),
                  ],
                ),
                // Each break taken today, from → to.
                if (e.breaks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...e.breaks.asMap().entries.map((entry) {
                    final i = entry.key;
                    final b = entry.value;
                    final to = b.ongoing ? 'ongoing' : _timeOnly(b.to);
                    return Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        const Icon(Icons.free_breakfast_outlined, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('Break ${i + 1}:  ${_timeOnly(b.from)} → $to',
                              style: const TextStyle(fontSize: 11, color: AppColors.textDark)),
                        ),
                        Text('${b.durationMin}m',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: b.ongoing ? AppColors.primary : AppColors.textMuted)),
                      ]),
                    );
                  }),
                ],
              ],
            ),
    );
  }

  // Break taken time for the BREAK column: "12m", "12/60m" (with allowance), or "—".
  String _breakText(EhrmsEmployee e) {
    final allowed = e.allowedBreakMin ?? 0;
    if (e.totalBreakMin <= 0 && allowed <= 0 && !e.unlimitedBreak) return '—';
    if (e.unlimitedBreak || allowed <= 0) return '${e.totalBreakMin}m';
    return '${e.totalBreakMin}/${allowed}m';
  }

  // Red when over allowance, primary while on break, else muted.
  Color _breakColor(EhrmsEmployee e) {
    final allowed = e.allowedBreakMin ?? 0;
    if (allowed > 0 && e.totalBreakMin > allowed) return AppColors.danger;
    if (e.onBreak) return AppColors.primary;
    return e.totalBreakMin > 0 ? AppColors.textDark : AppColors.textMuted;
  }

  Widget _timeCol(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  // "2026-06-16 10:30:23 AM" -> "10:30:23 AM" (with seconds).
  static String _timeOnly(String? s) {
    if (s == null || s.trim().isEmpty) return '-';
    final parts = s.trim().split(' ');
    if (parts.length >= 3) {
      final hms = parts[1].split(':');
      if (hms.length >= 3) return '${hms[0]}:${hms[1]}:${hms[2]} ${parts[2]}';
      if (hms.length >= 2) return '${hms[0]}:${hms[1]} ${parts[2]}';
    }
    return s;
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }

  static String _host(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }
}

/// Small circular punch-time face (EHRMS URL or base64). Flips legacy EHRMS images
/// 180° (stored upside-down). Tap to enlarge. Tiny label above + match% below.
class _FaceCircle extends StatelessWidget {
  final String label;
  final String? source;
  final num? matchScore;
  final String? captureIso; // ISO capture time of this selfie (decides 180° flip)

  const _FaceCircle({required this.label, this.source, this.matchScore, this.captureIso});

  bool get _has => source != null && source!.trim().isNotEmpty;

  // Initial guess (timestamp heuristic) used only until ML Kit detection resolves.
  bool get _flipFallback => ehrmsSelfieNeedsFlip(source, captureIso: captureIso);

  ImageProvider? _provider() {
    if (!_has) return null;
    final s = source!.trim();
    if (s.startsWith('http')) return NetworkImage(s);
    try {
      return MemoryImage(base64Decode(s.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '')));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider();
    // Detect the true orientation from the image (ML Kit) and flip if upside-down;
    // fall back to the timestamp heuristic while detection is pending/undetermined.
    return FutureBuilder<bool?>(
      future: _has ? AvatarOrientation.resolveNeedsFlip(source!.trim()) : Future.value(false),
      builder: (context, snap) {
        final flip = snap.data ?? _flipFallback;
        return Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: p == null ? null : () => _enlarge(context, p, flip),
              child: Container(
                width: 46,
                height: 46,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.03),
                  border: Border.all(color: AppColors.border),
                ),
                child: p == null
                    ? const Icon(Icons.person, size: 18, color: AppColors.textMuted)
                    : RotatedBox(quarterTurns: flip ? 2 : 0, child: Image(image: p, width: 46, height: 46, fit: BoxFit.cover)),
              ),
            ),
            SizedBox(
              height: 10,
              child: matchScore != null
                  ? Text('${matchScore!.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: AppColors.success))
                  : null,
            ),
          ],
        );
      },
    );
  }

  void _enlarge(BuildContext context, ImageProvider provider, bool flip) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: RotatedBox(quarterTurns: flip ? 2 : 0, child: Image(image: provider, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary)),
        ],
      ),
    );
  }
}
