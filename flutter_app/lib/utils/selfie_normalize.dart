import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'face_detection_helper.dart';

/// Pure rotate (deterministic) by 90, 180, or 270 degrees.
Uint8List _rotateSync(Uint8List raw, int angle) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    return Uint8List.fromList(
      img.encodeJpg(img.copyRotate(decoded, angle: angle), quality: 90),
    );
  } catch (_) {
    return raw;
  }
}

Uint8List _rotate90(Uint8List raw) => _rotateSync(raw, 90);
Uint8List _rotate180(Uint8List raw) => _rotateSync(raw, 180);
Uint8List _rotate270(Uint8List raw) => _rotateSync(raw, 270);

/// Pure 180° pixel flip exposed for other callers.
Uint8List flip180(Uint8List raw) => _rotate180(raw);

/// Returns selfie JPEG [raw] rotated to UPRIGHT.
/// Inspects ML Kit's Euler Z angle and tests 90/180/270 rotations if needed
/// so the face is always presented upright to the recognition model.
Future<Uint8List> normalizeSelfieUpright(Uint8List raw) async {
  try {
    final asis = await FaceDetectionHelper.detectFromBytes(raw);

    if (asis.faceCount > 0) {
      final roll = asis.rollZ ?? 0.0;
      if (roll > 45 && roll <= 135) {
        return await compute(_rotate270, raw);
      }
      if (roll < -45 && roll >= -135) {
        return await compute(_rotate90, raw);
      }
      if (roll > 135 || roll < -135 || asis.isUpsideDown) {
        return await compute(_rotate180, raw);
      }
      return raw;
    }

    // Fallback: If no face detected at angle 0, test rotations
    final rot180 = await compute(_rotate180, raw);
    final probe180 = await FaceDetectionHelper.detectFromBytes(rot180);
    if (probe180.faceCount > 0 && !probe180.isUpsideDown) return rot180;

    final rot90 = await compute(_rotate90, raw);
    final probe90 = await FaceDetectionHelper.detectFromBytes(rot90);
    if (probe90.faceCount > 0 && !probe90.isUpsideDown) return rot90;

    final rot270 = await compute(_rotate270, raw);
    final probe270 = await FaceDetectionHelper.detectFromBytes(rot270);
    if (probe270.faceCount > 0 && !probe270.isUpsideDown) return rot270;

    return raw;
  } catch (_) {
    return raw;
  }
}

/// Downscales a selfie to <= 180px @ 20% quality for EHRMS punch POST
/// so the request body never exceeds the reverse-proxy 10 KB limit.
String compressForEhrmsPunch(String base64Str) {
  try {
    final clean = base64Str.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '');
    final raw = base64Decode(clean);
    if (raw.length <= 5500) return base64Str;
    final decoded = img.decodeImage(raw);
    if (decoded == null) return base64Str;
    var processed = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 180 : null,
      height: decoded.height > decoded.width ? 180 : null,
    );
    var compressed = Uint8List.fromList(img.encodeJpg(processed, quality: 20));
    if (compressed.length > 5500) {
      processed = img.copyResize(processed, width: 140, height: 140);
      compressed = Uint8List.fromList(img.encodeJpg(processed, quality: 15));
    }
    return base64Encode(compressed);
  } catch (_) {
    return base64Str;
  }
}
