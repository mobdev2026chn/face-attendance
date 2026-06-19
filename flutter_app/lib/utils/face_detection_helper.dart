import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

/// Result of still-image face detection.
class FaceDetectionResult {
  final bool valid;
  final int faceCount;
  final String? message;

  /// Roll angle (headEulerAngleZ, degrees) of the largest detected face.
  /// ~0 = upright, ~±180 = upside-down. Null when no face was found.
  final double? rollZ;

  /// Definitive upside-down verdict for the largest detected face. Derived from
  /// landmark GEOMETRY (eyes vs mouth vertical position) when landmarks are
  /// present, falling back to [rollZ]. Null when no face was found.
  ///
  /// Geometry beats [rollZ] because ML Kit can detect an upside-down face yet
  /// NORMALIZE the reported roll back toward ~0°, which makes an "abs(rollZ) > 90"
  /// test silently miss flipped captures.
  final bool? upsideDown;

  const FaceDetectionResult({
    required this.valid,
    required this.faceCount,
    this.message,
    this.rollZ,
    this.upsideDown,
  });

  /// True when a face is present and clearly upside-down.
  bool get isUpsideDown => upsideDown ?? false;
}

/// On-device still-image face detection (ML Kit). Used only for the selfie
/// orientation gate — once per capture and once per displayed image — so the
/// landmark cost is fine. (The live preview here is plain `camera`, no ML stream.)
class FaceDetectionHelper {
  static FaceDetector? _detector;

  static FaceDetector get _getDetector {
    _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
        // Landmarks give a rotation-robust upside-down test (eyes vs mouth Y),
        // which the roll angle alone can't provide.
        enableLandmarks: true,
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
      ),
    );
    return _detector!;
  }

  /// Decides whether [face] is upside-down. Prefers landmark geometry — for an
  /// upright face the eyes sit ABOVE (smaller y) the mouth; flipped, they sit
  /// below. Immune to ML Kit normalizing the reported roll toward ~0° on a
  /// genuinely inverted face. Falls back to the roll angle when the eye/mouth
  /// landmarks aren't both available.
  static bool _isFaceUpsideDown(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final mouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position ??
        face.landmarks[FaceLandmarkType.noseBase]?.position;
    final eyes = [leftEye, rightEye].whereType<math.Point<int>>().toList();
    if (eyes.isNotEmpty && mouth != null) {
      final eyeY = eyes.map((p) => p.y).reduce((a, b) => a + b) / eyes.length;
      return eyeY > mouth.y;
    }
    final roll = face.headEulerAngleZ;
    return roll != null && roll.abs() > 90;
  }

  /// Detects faces in [file]. [valid] is true only when exactly one face is found.
  static Future<FaceDetectionResult> detectFromFile(File file) async {
    if (!file.existsSync()) {
      return const FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Image file not found',
      );
    }

    try {
      final inputImage = InputImage.fromFile(file);
      final faces = await _getDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return const FaceDetectionResult(
          valid: false,
          faceCount: 0,
          message: 'No face detected.',
        );
      }

      // Largest face drives the orientation decision.
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
      final rollZ = faces.first.headEulerAngleZ;
      final upsideDown = _isFaceUpsideDown(faces.first);

      return FaceDetectionResult(
        valid: faces.length == 1,
        faceCount: faces.length,
        message: faces.length > 1 ? 'Multiple faces detected.' : null,
        rollZ: rollZ,
        upsideDown: upsideDown,
      );
    } catch (e) {
      return const FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Face detection failed.',
      );
    }
  }

  /// Runs [detectFromFile] on in-memory JPEG [bytes] by staging them to a temp
  /// file (ML Kit's still-image detector needs a file/URI, not raw JPEG bytes).
  static Future<FaceDetectionResult> detectFromBytes(Uint8List bytes) async {
    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File(
          '${dir.path}/orient_probe_${bytes.length}_${bytes.isEmpty ? 0 : bytes.first}.jpg');
      await temp.writeAsBytes(bytes, flush: true);
      return await detectFromFile(temp);
    } catch (e) {
      return const FaceDetectionResult(
        valid: false,
        faceCount: 0,
        message: 'Face detection failed.',
      );
    } finally {
      try {
        await temp?.delete();
      } catch (_) {}
    }
  }

  /// Release the detector (e.g. on app lifecycle). Optional; reused otherwise.
  static Future<void> close() async {
    await _detector?.close();
    _detector = null;
  }
}
