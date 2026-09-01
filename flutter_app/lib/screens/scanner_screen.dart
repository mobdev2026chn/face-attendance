import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../config/selfie_orientation.dart';
import '../models/scan_result.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../utils/avatar_orientation.dart';
import '../utils/feedback_sound.dart';
import '../utils/selfie_normalize.dart';
import '../widgets/app_drawer.dart';
import '../widgets/face_guide_overlay.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with RouteAware, WidgetsBindingObserver {
  CameraController? _cameraController;
  String? _cameraError;
  bool _cameraPermanentlyDenied = false;

  Timer? _scanTimer;

  bool _isLoading = false;
  bool _cameraLocked = false;
  bool _scanSuccessful = false;
  // True when the last scan found no enrolled match → offer at-kiosk enrollment.
  bool _notRecognized = false;
  Color _ovalColor = AppColors.primary;
  String _guidanceText = 'Align Face Inside Guide';

  String _locationStr = 'Detecting location...';
  double _gpsLat = 13.0827;
  double _gpsLon = 80.2707;
  // Full reverse-geocoded address sent with each punch (stored on the EHRMS record).
  String _address = '';
  String _area = '';
  String _city = '';
  String _pincode = '';

  ScanResult? _recognizedEmployee;
  String? _lastCapturedImageBase64;
  DateTime? _lastErrSoundAt; // throttles the error beep during fast polling

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _updateLocation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-acquire the camera when returning to the app (e.g. after granting
    // permission from system Settings) if it isn't running yet.
    if (state == AppLifecycleState.resumed && _cameraController == null) {
      _initCamera();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _scanTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  /// Another screen was pushed on top of this one — release the camera.
  @override
  void didPushNext() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
  }

  /// Returned to this screen — re-acquire the camera.
  @override
  void didPopNext() {
    _resetScannerState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _cameraError = null;
      _cameraPermanentlyDenied = false;
    });

    // The camera plugin does not request runtime permission itself — it throws
    // CameraAccessDenied if CAMERA isn't already granted. Ask for it first.
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _cameraPermanentlyDenied = status.isPermanentlyDenied || status.isRestricted;
        _cameraError = _cameraPermanentlyDenied
            ? 'Camera permission is blocked.\nEnable it in Settings to mark attendance.'
            : 'Camera Access Required\nPlease allow camera access to mark attendance.';
      });
      return;
    }

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
        _cameraError = null;
      });
      _startScanLoop();
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera Access Required\n${e.toString()}');
    }
  }

  Future<void> _updateLocation() async {
    setState(() => _locationStr = 'Detecting location...');
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationStr = 'Location permission denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _gpsLat = position.latitude;
      _gpsLon = position.longitude;

      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[];
        if (p.name != null && p.name!.isNotEmpty && p.name != p.street) parts.add(p.name!);
        if (p.street != null && p.street!.isNotEmpty) parts.add(p.street!);
        if (p.subLocality != null && p.subLocality!.isNotEmpty) parts.add(p.subLocality!);
        if (p.subAdministrativeArea != null && p.subAdministrativeArea!.isNotEmpty) parts.add(p.subAdministrativeArea!);
        if (p.locality != null && p.locality!.isNotEmpty) parts.add(p.locality!);
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) parts.add(p.administrativeArea!);
        if (p.postalCode != null && p.postalCode!.isNotEmpty) parts.add(p.postalCode!);
        if (p.country != null && p.country!.isNotEmpty) parts.add(p.country!);

        final full = parts.join(', ');
        _address = full;
        _area = (p.subLocality != null && p.subLocality!.isNotEmpty) ? p.subLocality! : (p.subAdministrativeArea ?? '');
        _city = p.locality ?? '';
        _pincode = p.postalCode ?? '';
        setState(() {
          _locationStr = full.isNotEmpty ? full : '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      } else {
        setState(() => _locationStr = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}');
      }
    } catch (e) {
      setState(() => _locationStr = 'Failed to resolve geocode address');
    }
  }

  void _startScanLoop() {
    _scanTimer?.cancel();
    // Live recognition: continuously scan so a face in the guide is recognized and
    // punched automatically. Each scan is guarded by _isLoading (no overlap).
    _scanTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!_isLoading && !_cameraLocked && !_scanSuccessful) {
        _handleScanAttendance();
      }
    });
  }

  void _resetScannerState() {
    setState(() {
      _cameraLocked = false;
      _scanSuccessful = false;
      _notRecognized = false;
      _ovalColor = AppColors.primary;
      _guidanceText = 'Align Face Inside Guide';
    });
  }

  /// Dismiss the centered result dialog (recognized employee / enroll prompt)
  /// and return the scanner to its ready state.
  void _dismissResult() {
    if (_isLoading) return;
    setState(() => _recognizedEmployee = null);
    _resetScannerState();
  }

  Future<String?> _captureImageBase64() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    final file = await controller.takePicture();
    final Uint8List bytes = await file.readAsBytes();
    // Some front cameras write the selfie upside-down. Normalize to upright BEFORE
    // sending so the punch selfie stored on EHRMS (and used for enrollment/match)
    // is correct everywhere — no display-time guessing needed for new captures.
    final Uint8List upright = await normalizeSelfieUpright(bytes);
    return base64Encode(upright);
  }

  Future<void> _handleScanAttendance() async {
    if (_cameraLocked) return;
    setState(() => _isLoading = true);

    try {
      final imageBase64 = await _captureImageBase64();
      if (imageBase64 == null) return;
      // Keep the capture so it can seed enrollment if the face isn't recognized (first punch).
      _lastCapturedImageBase64 = imageBase64;

      final result = await ApiService.scanAttendance(
        imageBase64: imageBase64,
        action: 'auto',
        gpsLat: _gpsLat,
        gpsLon: _gpsLon,
        address: _address,
        area: _area,
        city: _city,
        pincode: _pincode,
      );

      _lastCapturedImageBase64 = imageBase64;

      String guidance = 'Verification Passed!';
      if (result.action == 'Check-In') {
        guidance = result.status == 'Punched Late' ? 'PUNCHED LATE' : 'PUNCH IN SUCCESSFUL';
      } else if (result.action == 'Already-Checked-In' || result.action == 'On-Break-Scan') {
        guidance = 'Verification Passed!';
      } else if (result.action == 'Check-Out') {
        guidance = result.status == 'Punched Out Early' ? 'PUNCHED OUT EARLY' : 'PUNCH OUT SUCCESSFUL';
      } else if (result.action == 'Break-In') {
        guidance = 'BREAK MARKED SUCCESSFUL';
      } else if (result.action == 'Break-Out') {
        guidance = 'BREAK ENDED SUCCESSFUL';
      } else {
        guidance = 'PUNCH COMPLETED FOR TODAY';
      }

      setState(() {
        _cameraLocked = true;
        _scanSuccessful = true;
        _notRecognized = false;
        _ovalColor = AppColors.success;
        _guidanceText = guidance;
        _recognizedEmployee = result;
      });
      FeedbackSound.success();
      _notifyBreakPolicy(result);
      _notifyPunchPolicy(result);
      _addFaceSample(result, imageBase64);

      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _recognizedEmployee = null);
        _resetScannerState();
      });
    } on ApiException catch (e) {
      // No kiosk enroll/link anymore. An unrecognized face just means the person
      // isn't enrolled in EHRMS yet — they enroll in the EHRMS app (or their first
      // punch there); the kiosk only identifies against EHRMS's enrolled faces.
      _applyErrorGuidance(e.message);
    } catch (e) {
      FeedbackSound.error();
      setState(() {
        _guidanceText = 'Connection Error. Retrying...';
        _cameraLocked = false;
        _scanSuccessful = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// After a real punch (in/out/break), add the live face as another enrollment sample
  /// so recognition stays robust and the link survives day to day. Best-effort.
  void _addFaceSample(ScanResult r, String? image) {
    const writeActions = {'Check-In', 'Check-Out', 'Break-In', 'Break-Out'};
    if (image == null || image == 'mock_test_face' || !writeActions.contains(r.action)) return;
    if (r.employeeId.isEmpty) return;
    ApiService.addFaceSample(employeeId: r.employeeId, imageBase64: image);
  }

  /// Notify the break policy per EHRMS after a break action (remaining/over-allowance).
  void _notifyBreakPolicy(ScanResult r) {
    if (r.action != 'Break-In' && r.action != 'Break-Out') return;
    // Prefer EHRMS's exact policy notice (disabled / no-allowance "...processed with
    // Fine", or "Allocated break time exceeded by N minutes.") — single source of truth.
    final notice = r.notice;
    final hasNotice = notice != null && notice.trim().isNotEmpty;
    String msg;
    if (r.action == 'Break-In') {
      if (hasNotice) {
        msg = notice;
      } else if (r.breakUnlimited) {
        msg = 'Break started — unlimited break allowance.';
      } else if (r.breakRemainingMin != null) {
        msg = 'Break started — ${r.breakRemainingMin}m left of ${r.breakAllowedMin ?? 0}m today.';
      } else {
        msg = 'Break started.';
      }
    } else {
      final taken = r.breakTotalMin != null ? '${r.breakTotalMin}m taken today' : 'break ended';
      if (hasNotice) {
        msg = 'Break ended — $taken.\n$notice';
      } else {
        msg = r.breakOver
            ? 'Break ended — $taken. Over allowance (${r.breakAllowedMin}m) — a fine may apply.'
            : 'Break ended — $taken.';
      }
    }
    final highlight = r.breakOver || hasNotice;
    if (highlight) FeedbackSound.warn();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: highlight ? AppColors.danger : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Notify the permission result after a kiosk Permission Out / In. EHRMS owns the
  /// wording: Permission In returns "...exceeded by N minutes" (overrun fine) when the
  /// employee was out longer than the approved custom window; otherwise it's neutral.
  void _notifyPermissionAction(ScanResult r) {
    if (r.action != 'Permission-Out' && r.action != 'Permission-In') return;
    final notice = r.permissionNotice;
    final hasNotice = notice != null && notice.trim().isNotEmpty;
    final isOut = r.action == 'Permission-Out';
    final msg = isOut
        ? (hasNotice ? notice : 'Permission step-out recorded. Scan again to return.')
        : (hasNotice ? notice : 'Permission return recorded.');
    // Highlight only when EHRMS charged a fine (overrun beyond the approved time).
    final highlight = hasNotice && notice.toLowerCase().contains('fine');
    if (highlight) FeedbackSound.warn();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: highlight ? AppColors.danger : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Surface the EHRMS fine + overtime policy on a real punch (in/out). EHRMS is the
  /// single source of truth: it computes late/early/break/permission fine and overtime
  /// against the shift allocated for THAT day. The kiosk only displays the result.
  void _notifyPunchPolicy(ScanResult r) {
    if (r.action != 'Check-In' && r.action != 'Check-Out') return;

    final lines = <String>[];
    // Late / early fine (with the day's total fine amount when EHRMS charged one).
    final late = r.lateMinutes ?? 0;
    final early = r.earlyMinutes ?? 0;
    final fine = (r.fineAmount ?? 0).toDouble();
    if (r.action == 'Check-In' && late > 0) {
      lines.add('Late check-in by $late min.');
    }
    if (r.action == 'Check-Out' && early > 0) {
      lines.add('Early exit by $early min.');
    }
    if (fine > 0) {
      lines.add('Fine: ₹${fine.toStringAsFixed(fine.truncateToDouble() == fine ? 0 : 2)}.');
    }
    // Permission policy notice (verbatim from EHRMS), if any.
    if (r.permissionNotice != null) lines.add(r.permissionNotice!);

    // Overtime, only meaningful at punch-out.
    if (r.action == 'Check-Out') {
      final otNotice = r.overtimeNotice; // disabled / not-configured wording
      final ot = r.overtimeMinutes ?? 0;
      final otAmt = (r.overtimeAmount ?? 0).toDouble();
      if (otNotice != null) {
        lines.add(otNotice);
      } else if (ot > 0) {
        final amt = otAmt > 0
            ? ' (₹${otAmt.toStringAsFixed(otAmt.truncateToDouble() == otAmt ? 0 : 2)})'
            : '';
        lines.add('Overtime earned: $ot min$amt.');
      }
    }

    if (lines.isEmpty) return;
    final isFine = late > 0 || early > 0 || fine > 0 ||
        r.permissionNotice != null || r.overtimeNotice != null;
    if (isFine) FeedbackSound.warn();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lines.join('\n')),
        backgroundColor: isFine ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _errorSoundThrottled() {
    final now = DateTime.now();
    if (_lastErrSoundAt == null || now.difference(_lastErrSoundAt!).inMilliseconds > 2200) {
      _lastErrSoundAt = now;
      FeedbackSound.error();
    }
  }

  void _applyErrorGuidance(String errMsg) {
    // Beep on errors (incl. "no face detected"), but throttle so the 500ms poll loop
    // doesn't spam the sound while someone is positioning their face.
    _errorSoundThrottled();

    // An unrecognized face (not in EHRMS against any user) is the cue to offer
    // at-kiosk enrollment — distinct from positioning/spoof guidance.
    final notRecognized = errMsg.contains('not recognized') || errMsg.contains('Identity rejected');

    String guidance;
    if (errMsg.contains('off-center horizontally')) {
      guidance = 'Align Center (Move Left/Right)';
    } else if (errMsg.contains('off-center vertically')) {
      guidance = 'Align Center (Move Up/Down)';
    } else if (errMsg.contains('too far')) {
      guidance = 'Come Front Little';
    } else if (errMsg.contains('too close')) {
      guidance = 'Go Back Little';
    } else if (errMsg.contains('Side angles')) {
      guidance = 'Look Straight at Camera';
    } else if (errMsg.contains('Multiple faces')) {
      guidance = 'Ensure Only 1 Face Visible';
    } else if (errMsg.contains('Spoof Alert') || errMsg.contains('fake')) {
      guidance = 'Spoof Alert! Fake Face Detected';
    } else if (notRecognized) {
      guidance = 'Face Not Recognized — Enroll below';
    } else {
      guidance = errMsg.isNotEmpty ? errMsg : 'Face Not Recognized. Retrying...';
    }

    setState(() {
      _ovalColor = AppColors.danger;
      _guidanceText = guidance;
      _scanSuccessful = false;
      _notRecognized = notRecognized;
      // An unrecognized face surfaces a steady, actionable enroll prompt, so PAUSE
      // the scan loop (like the recognized-employee path) while it's shown. Otherwise
      // the next 800ms scans return positioning/transient guidance, toggling the
      // prompt off and on — making the "Enroll Your Face" box blink. Other errors
      // keep scanning live so positioning guidance stays responsive.
      _cameraLocked = notRecognized;
    });

    // Auto-recover an idle kiosk: if nobody acts on the steady enroll prompt, return
    // to scanning so a stale prompt doesn't linger after the person walks away.
    if (notRecognized) {
      Future.delayed(const Duration(seconds: 8), () {
        if (!mounted) return;
        if (_notRecognized && !_isLoading && _recognizedEmployee == null) {
          _resetScannerState();
        }
      });
    }
  }

  /// At-kiosk enrollment for an UNRECOGNIZED person. They sign in with their EHRMS
  /// account (proving identity); the live capture registers their canonical face in
  /// EHRMS. The backend refuses a face already enrolled to another user.
  Future<void> _startKioskEnroll() async {
    // Pause the live scan loop while enrolling. Clearing _notRecognized also
    // neutralizes any pending idle auto-recover timer from _applyErrorGuidance so it
    // can't reset state (and resume background scanning) mid-enrollment.
    setState(() {
      _cameraLocked = true;
      _scanSuccessful = false;
      _notRecognized = false;
    });

    final creds = await _promptEhrmsCredentials();
    if (creds == null) {
      if (mounted) _resetScannerState();
      return;
    }

    setState(() {
      _isLoading = true;
      _ovalColor = AppColors.primary;
      _guidanceText = 'Enrolling your face…';
    });
    try {
      // Capture a couple of fresh upright samples for a robust enrollment.
      final samples = <String>[];
      for (var i = 0; i < 2; i++) {
        final img = await _captureImageBase64();
        if (img != null) samples.add(img);
        await Future.delayed(const Duration(milliseconds: 350));
      }
      if (samples.isEmpty) {
        throw ApiException('Could not capture your face. Please try again.');
      }

      final name = await ApiService.kioskEnroll(
        email: creds.email,
        password: creds.password,
        images: samples,
      );
      if (!mounted) return;
      FeedbackSound.success();
      setState(() {
        _ovalColor = AppColors.success;
        _guidanceText = 'Enrolled! Scan to punch.';
        _notRecognized = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Face enrolled for $name. You can scan now.')),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _resetScannerState();
      });
    } on NeedsLiveCapture catch (e) {
      FeedbackSound.error();
      _showError(e.message);
      if (mounted) _resetScannerState();
    } on ApiException catch (e) {
      FeedbackSound.error();
      _showError(e.message);
      if (mounted) _resetScannerState();
    } catch (_) {
      FeedbackSound.error();
      _showError('Enrollment failed. Please try again.');
      if (mounted) _resetScannerState();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Collect EHRMS credentials for at-kiosk enrollment. Returns null if cancelled.
  Future<({String email, String password})?> _promptEhrmsCredentials() {
    final emailC = TextEditingController();
    final passC = TextEditingController();
    return showDialog<({String email, String password})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enroll Your Face'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "You're not enrolled yet. Sign in with your EHRMS account to register "
              'your face, then look at the camera.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailC,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'EHRMS email'),
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
            child: const Text('Capture & Enroll'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubsequentAction(String action, String successGuidance) async {
    if (_recognizedEmployee == null) return;
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.scanAttendance(
        imageBase64: _lastCapturedImageBase64 ?? 'mock_test_face',
        action: action,
        gpsLat: _gpsLat,
        gpsLon: _gpsLon,
        address: _address,
        area: _area,
        city: _city,
        pincode: _pincode,
      );
      setState(() {
        _guidanceText = successGuidance;
        _recognizedEmployee = result;
      });
      FeedbackSound.success();
      _notifyBreakPolicy(result);
      _notifyPermissionAction(result);
      _addFaceSample(result, _lastCapturedImageBase64);
      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _recognizedEmployee = null);
        _resetScannerState();
      });
    } on ApiException catch (e) {
      FeedbackSound.error();
      _showError(e.message);
    } catch (e) {
      FeedbackSound.error();
      _showError('Connection error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      drawer: const AppDrawer(),
      body: Builder(
        builder: (context) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildCameraPreview(),
              Container(color: Colors.black.withValues(alpha: 0.25)),
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    _buildReadyPill(),
                    const SizedBox(height: 12),
                    Text(
                      _guidanceText,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _ovalColor, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    // Face guide fills the remaining space — almost full screen.
                    Expanded(
                      child: FaceGuideOverlay(color: _ovalColor, showSuccessTick: _scanSuccessful),
                    ),
                    const SizedBox(height: 12),
                    _buildLocationCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // Scan result (recognized employee or enroll prompt) is shown as a
              // centered dialog over a dim scrim, not docked at the bottom.
              if (_recognizedEmployee != null || _notRecognized)
                _buildResultDialog(),
            ],
          );
        },
      ),
    );
  }

  /// Centered modal-style overlay for the scan result. Sits above the camera
  /// preview with a dim scrim so the card reads like a dialog in the middle of
  /// the screen instead of being docked at the bottom.
  Widget _buildResultDialog() {
    return Positioned.fill(
      // Tap anywhere on the scrim (outside the card) to cancel.
      child: GestureDetector(
        onTap: _dismissResult,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: SafeArea(
            child: Center(
              // Swallow taps on the card itself so they don't dismiss.
              child: GestureDetector(
                onTap: () {},
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _recognizedEmployee != null
                            ? _buildEmployeeCard(_recognizedEmployee!)
                            : _buildEnrollPrompt(),
                        const SizedBox(height: 18),
                        // Circular cancel icon.
                        Material(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 1.5)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _isLoading ? null : _dismissResult,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.close, size: 26, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraError != null) {
      return Container(
        color: AppColors.darkBg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, color: AppColors.primary, size: 48),
                const SizedBox(height: 16),
                Text(_cameraError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: () {
                    if (_cameraPermanentlyDenied) {
                      openAppSettings();
                    } else {
                      _initCamera();
                    }
                  },
                  child: Text(_cameraPermanentlyDenied ? 'Open Settings' : 'Allow Camera Access'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: AppColors.darkBg,
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return ClipRect(
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleIconButton(icon: Icons.menu, onTap: () => Scaffold.of(context).openDrawer()),
          const Text('Mark Attendance', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildReadyPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary)),
          const SizedBox(width: 8),
          const Text('READY TO SCAN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ],
      ),
    );
  }

  /// Shown when a scanned face matched no enrolled employee — lets the person
  /// register their face at the kiosk (gated by their EHRMS sign-in).
  Widget _buildEnrollPrompt() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Text(
            'Your face isn’t enrolled yet.',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _startKioskEnroll,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Enroll Your Face', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CURRENT LOCATION', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(_locationStr, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            onPressed: _updateLocation,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// profile_photo may be an EHRMS image URL, a base64 string, or a sentinel like
  /// 'mock_test_face'. Return the right provider; null falls back to the initial avatar.
  ImageProvider? _avatarProvider(String? photo) {
    if (photo == null) return null;
    final p = photo.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http')) return NetworkImage(p);
    try {
      final clean = p.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '');
      return MemoryImage(base64Decode(clean));
    } catch (_) {
      return null;
    }
  }

  Widget _buildEmployeeCard(ScanResult employee) {
    final isLateOrEarly = employee.status.toLowerCase().contains('late') || employee.status.toLowerCase().contains('early');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Builder(builder: (_) {
                // Prefer the LIVE punch image just captured (interlinked — the same image
                // sent to EHRMS as the punch selfie); fall back to the EHRMS/enrolled photo.
                // The live capture is already normalized upright at capture time, so it
                // never needs a flip; only the stored fallback photo is orientation-probed.
                final live = _lastCapturedImageBase64;
                ImageProvider? liveProvider;
                if (live != null && live.isNotEmpty && live != 'mock_test_face') {
                  try { liveProvider = MemoryImage(base64Decode(live)); } catch (_) {}
                }

                Widget circle(ImageProvider provider, bool flip) => ClipOval(
                      child: RotatedBox(
                        quarterTurns: flip ? 2 : 0,
                        child: Image(image: provider, width: 72, height: 72, fit: BoxFit.cover),
                      ),
                    );

                if (liveProvider != null) return circle(liveProvider, false);

                final fallback = _avatarProvider(employee.profilePhoto);
                if (fallback == null) {
                  return CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      employee.employeeName.isNotEmpty ? employee.employeeName[0] : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26),
                    ),
                  );
                }
                // Detect the stored photo's true orientation (ML Kit); heuristic fallback
                // while pending/undetermined.
                final src = employee.profilePhoto?.trim() ?? '';
                return FutureBuilder<bool?>(
                  future: src.isEmpty ? Future.value(false) : AvatarOrientation.resolveNeedsFlip(src),
                  builder: (context, snap) {
                    final flip = snap.data ??
                        ehrmsSelfieNeedsFlip(employee.profilePhoto, captureIso: employee.profilePhotoIso);
                    return circle(fallback, flip);
                  },
                );
              }),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.employeeName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                    Text('ID: ${employee.employeeId}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    if (employee.department != null) Text('Dept: ${employee.department}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        employee.status == 'Present' ? 'Punched In Successful' : employee.status,
                        style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Full punch location (reverse-geocoded address).
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _locationStr,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          // Fine banner — wording driven by EHRMS's per-day shift calc (late/early
          // minutes + total fine amount), never a hardcoded shift time.
          Builder(builder: (_) {
            final late = employee.lateMinutes ?? 0;
            final early = employee.earlyMinutes ?? 0;
            final fine = (employee.fineAmount ?? 0).toDouble();
            final showBanner = isLateOrEarly || late > 0 || early > 0 || fine > 0;
            if (!showBanner) return const SizedBox.shrink();
            final parts = <String>[];
            if (late > 0) parts.add('PUNCHED LATE BY $late MIN');
            if (early > 0) parts.add('PUNCHED OUT EARLY BY $early MIN');
            if (parts.isEmpty) {
              parts.add(employee.status.toLowerCase().contains('late')
                  ? 'PUNCHED LATE'
                  : 'PUNCHED OUT EARLY');
            }
            if (fine > 0) {
              parts.add('FINE ₹${fine.toStringAsFixed(fine.truncateToDouble() == fine ? 0 : 2)}');
            }
            return Column(children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                alignment: Alignment.center,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  parts.join(' • '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ]);
          }),
          // Overtime banner (punch-out): earned OT or EHRMS's disabled/not-configured notice.
          Builder(builder: (_) {
            if (employee.action != 'Check-Out') return const SizedBox.shrink();
            final ot = employee.overtimeMinutes ?? 0;
            final otAmt = (employee.overtimeAmount ?? 0).toDouble();
            final otNotice = employee.overtimeNotice;
            String? text;
            Color color = AppColors.success;
            if (ot > 0) {
              final amt = otAmt > 0
                  ? ' • ₹${otAmt.toStringAsFixed(otAmt.truncateToDouble() == otAmt ? 0 : 2)}'
                  : '';
              text = 'OVERTIME $ot MIN$amt';
            } else if (otNotice != null && otNotice.trim().isNotEmpty) {
              text = otNotice.toUpperCase();
              color = AppColors.textMuted;
            }
            if (text == null) return const SizedBox.shrink();
            return Column(children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                alignment: Alignment.center,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ]);
          }),
          if (employee.action == 'Already-Checked-In') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _handleSubsequentAction('break_in', 'BREAK MARKED SUCCESSFUL'),
                    child: const Text('Take a Break'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    onPressed: _isLoading ? null : () => _handleSubsequentAction('out', 'PUNCH OUT SUCCESSFUL'),
                    child: const Text('Punch Out'),
                  ),
                ),
              ],
            ),
            // Custom-permission step-out / return — shown only when the employee has
            // an actionable permission for today (created in the EHRMS app). EHRMS
            // fines any time beyond the approved window on Permission In.
            if (employee.permissionPhase == 'out' || employee.permissionPhase == 'in') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _handleSubsequentAction(
                            employee.permissionPhase == 'out' ? 'permission_out' : 'permission_in',
                            employee.permissionPhase == 'out'
                                ? 'PERMISSION OUT RECORDED'
                                : 'PERMISSION IN RECORDED',
                          ),
                  icon: const Icon(Icons.meeting_room_outlined, size: 18),
                  label: Text(employee.permissionPhase == 'out' ? 'Permission Out' : 'Permission In'),
                ),
              ),
            ],
          ],
          if (employee.action == 'On-Break-Scan') ...[
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : () => _handleSubsequentAction('break_out', 'BREAK ENDED SUCCESSFUL'),
              child: const Text('End Break'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
