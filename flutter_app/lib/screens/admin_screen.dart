import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/employee_directory.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/selfie_normalize.dart';
import '../utils/session.dart';
import '../widgets/face_guide_overlay.dart';

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final l = dt.toLocal();
  return '${l.day}/${l.month}/${l.year}';
}

/// Admin Panel (reached through the admin-password gate):
///  * Enroll User — pick a company employee and register their face
///    (`POST /admin/face-kiosk/enroll`).
///  * Registry — enrolled employees, with a face reset
///    (`DELETE /admin/face-recognition/:staffId`).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        title: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Enroll User'),
            Tab(text: 'Registry'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _EnrollUserTab(),
          _RegistryTab(),
        ],
      ),
    );
  }
}

class _EnrollUserTab extends StatefulWidget {
  const _EnrollUserTab();

  @override
  State<_EnrollUserTab> createState() => _EnrollUserTabState();
}

class _EnrollUserTabState extends State<_EnrollUserTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late Future<List<EnrolledEmployee>> _future;
  EnrolledEmployee? _selected;

  bool _isScanning = false;
  bool _isLoading = false;
  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cameraController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<EnrolledEmployee>> _load() =>
      guardSession(context, ApiService.fetchKioskStaff(query: _searchController.text));

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _future = _load());
    });
  }

  Future<void> _startScanning() async {
    if (_selected == null) return;
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      CameraController? controller;
      final presets = [ResolutionPreset.medium, ResolutionPreset.low, ResolutionPreset.high];
      for (final preset in presets) {
        try {
          final c = CameraController(
            frontCamera,
            preset,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.jpeg,
          );
          await c.initialize();
          controller = c;
          break;
        } catch (_) {}
      }

      if (controller == null) {
        final c = CameraController(frontCamera, ResolutionPreset.low, enableAudio: false);
        await c.initialize();
        controller = c;
      }

      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _isScanning = true;
      });
    } catch (e) {
      _showAlert('Camera Error', 'Could not access camera: $e');
    }
  }

  Future<String?> _captureSample() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    final file = await controller.takePicture();
    final Uint8List bytes = await file.readAsBytes();
    final Uint8List upright = await normalizeSelfieUpright(bytes);
    return base64Encode(upright);
  }

  Future<void> _captureAndSave() async {
    final staff = _selected;
    final controller = _cameraController;
    if (staff == null || controller == null || !controller.value.isInitialized) return;
    setState(() => _isLoading = true);

    try {
      // Two fresh upright samples for a robust enrollment.
      final samples = <String>[];
      for (var i = 0; i < 2; i++) {
        final img = await _captureSample();
        if (img != null) samples.add(img);
        if (i == 0) await Future.delayed(const Duration(milliseconds: 350));
      }
      if (samples.isEmpty) {
        throw NeedsLiveCapture('Could not capture the face. Please try again.');
      }

      final message = await ApiService.adminEnroll(staffId: staff.employeeId, images: samples);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Success'),
          content: Text('${staff.name}: $message'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _reset(clearSelection: true);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on SessionExpired {
      if (mounted) await handleSessionExpired(context);
    } on NeedsLiveCapture catch (e) {
      _showAlert('Retake Needed', e.message);
    } on NetworkException catch (e) {
      _showAlert('Connection Error', e.message);
    } on ApiException catch (e) {
      _showAlert('Enrollment Failed', e.message);
    } catch (e) {
      _showAlert('Enrollment Failed', 'Could not capture or upload the face. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reset({bool clearSelection = false}) {
    final controller = _cameraController;
    setState(() {
      _cameraController = null;
      _isScanning = false;
      if (clearSelection) {
        _selected = null;
        _future = _load();
      }
    });
    controller?.dispose();
  }

  void _showAlert(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
      ),
    );
  }

  Widget _employeeList() {
    return FutureBuilder<List<EnrolledEmployee>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snap.error is ApiException ? (snap.error as ApiException).message : 'Could not load employees.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => setState(() => _future = _load()), child: const Text('Retry')),
              ],
            ),
          );
        }
        final list = snap.data ?? const <EnrolledEmployee>[];
        if (list.isEmpty) {
          return const Center(child: Text('No matching employees.', style: TextStyle(color: AppColors.textMuted)));
        }
        return ListView.separated(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final e = list[index];
            final selected = _selected?.employeeId == e.employeeId;
            final subtitle = e.enrolled
                ? 'Reset face first'
                : [e.hrEmployeeId, e.department].where((s) => s != null && s.isNotEmpty).join(' · ');
            return Material(
              color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                enabled: !e.enrolled,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                ),
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: e.enrolled ? AppColors.textMuted : AppColors.primary,
                  child: Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                trailing: e.enrolled
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('ENROLLED',
                            style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w800)),
                      )
                    : (selected ? const Icon(Icons.check_circle, color: AppColors.primary) : null),
                onTap: e.enrolled ? null : () => setState(() => _selected = e),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isScanning) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('SELECT EMPLOYEE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(hintText: 'Search name, ID, email…', prefixIcon: Icon(Icons.search)),
                    onChanged: _onSearchChanged,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _selected == null ? null : _startScanning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      _selected == null ? 'Proceed to Scan' : 'Proceed to Scan · ${_selected!.name}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: _employeeList()),
          ],
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final staff = _selected;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1,
                height: controller.value.previewSize?.width ?? 1,
                child: CameraPreview(controller),
              ),
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.25)),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ENROLLING BIOMETRIC PROFILE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(staff?.name ?? '', style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w800)),
                    if ((staff?.hrEmployeeId ?? '').isNotEmpty)
                      Text('ID: ${staff!.hrEmployeeId}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Spacer(),
              const FaceGuideOverlay(color: AppColors.primary),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _captureAndSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Capture & Save Face', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () => _reset(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('← Change Employee', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegistryTab extends StatefulWidget {
  const _RegistryTab();

  @override
  State<_RegistryTab> createState() => _RegistryTabState();
}

class _RegistryTabState extends State<_RegistryTab> {
  late Future<List<EnrolledEmployee>> _future;
  final Set<String> _resetting = <String>{};

  @override
  void initState() {
    super.initState();
    _future = guardSession(context, ApiService.fetchEnrolledEmployees());
  }

  void _refresh() {
    setState(() => _future = guardSession(context, ApiService.fetchEnrolledEmployees()));
  }

  /// Clear this employee's registered face. The admin already re-verified their
  /// password at the Admin Panel gate, so only a confirmation is asked here.
  Future<void> _resetFace(EnrolledEmployee user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Face'),
        content: Text(
          'Remove the registered face for "${user.name}"?\n\n'
          'They will no longer be recognized at the kiosk until their face is enrolled '
          'again. Attendance history is not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset Face', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _resetting.add(user.employeeId));
    try {
      final message = await ApiService.resetFace(user.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${user.name}: $message')));
      _refresh();
    } on SessionExpired {
      if (mounted) await handleSessionExpired(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _resetting.remove(user.employeeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<EnrolledEmployee>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snapshot.hasError) {
            return ListView(
              children: const [
                SizedBox(height: 100),
                Center(child: Text('Could not load users registry.', style: TextStyle(color: AppColors.textMuted))),
              ],
            );
          }

          final users = snapshot.data ?? [];
          if (users.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 100),
                Center(child: Text('No faces enrolled yet.', style: TextStyle(color: AppColors.textMuted))),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final busy = _resetting.contains(user.employeeId);
              final meta = <String>[
                if ((user.hrEmployeeId ?? '').isNotEmpty) 'ID: ${user.hrEmployeeId}',
                'Enrolled: ${_fmtDate(user.enrolledAt)}',
              ].join(' | ');
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                          const SizedBox(height: 2),
                          Text(meta, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    busy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger)),
                          )
                        : TextButton(
                            onPressed: () => _resetFace(user),
                            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                            child: const Text('Reset face'),
                          ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
