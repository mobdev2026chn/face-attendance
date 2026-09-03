import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/selfie_normalize.dart';
import '../widgets/face_guide_overlay.dart';

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
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _deptController = TextEditingController();
  final _designationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isScanning = false;
  bool _isLoading = false;
  CameraController? _cameraController;

  @override
  void dispose() {
    _cameraController?.dispose();
    _idController.dispose();
    _nameController.dispose();
    _deptController.dispose();
    _designationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool get _formValid =>
      _idController.text.trim().isNotEmpty &&
      _nameController.text.trim().isNotEmpty &&
      _deptController.text.trim().isNotEmpty &&
      _designationController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty;

  Future<void> _startScanning() async {
    // The employee record is created by the enroll-face-mobile endpoint on capture,
    // so here we only open the camera and move into the guided scan view.
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

  Future<void> _captureAndSave() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _isLoading = true);

    try {
      final file = await controller.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      final Uint8List upright = await normalizeSelfieUpright(bytes);
      final imageBase64 = base64Encode(upright);

      await ApiService.enrollFace(employeeId: _idController.text.trim(), imageBase64: imageBase64);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: Text('Face registered successfully for "${_idController.text.trim()}"!\nBiometrics encrypted & saved.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _reset();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      _showAlert('Enrollment Failed', e.message);
    } catch (e) {
      _showAlert('Connection Error', 'Could not connect to the server. Please check your IP address.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reset() {
    _cameraController?.dispose();
    setState(() {
      _cameraController = null;
      _isScanning = false;
      _idController.clear();
    });
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isScanning) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ENTER EMPLOYEE USERNAME/ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _idController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'e.g. Elena Smith'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _idController.text.trim().isEmpty ? null : _startScanning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Proceed to Scan', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text('Registration Lock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 8),
            const Text(
              "Please enter the employee's name above to proceed to guided biometric scan.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

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
                    Text('ID: ${_idController.text.trim()}', style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w800)),
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
                        onPressed: _isLoading ? null : _reset,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('← Change Name', style: TextStyle(fontWeight: FontWeight.w800)),
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
  late Future<List<EnrolledUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.fetchRegistry();
  }

  void _refresh() {
    setState(() => _future = ApiService.fetchRegistry());
  }

  Future<void> _delete(EnrolledUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to permanently delete "${user.name}"?\nThis action cannot be undone!'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete User', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteEmployee(employeeId: user.name, id: user.id);
      _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: FutureBuilder<List<EnrolledUser>>(
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
                Center(child: Text('No users registered in database.', style: TextStyle(color: AppColors.textMuted))),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
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
                          Text('Enrolled: ${user.date} | Punches: ${user.punches}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _delete(user),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      child: const Text('Remove'),
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
