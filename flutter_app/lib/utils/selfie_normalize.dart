import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'face_detection_helper.dart';

/// Pure 180° pixel flip (deterministic; does not rely on EXIF or native rotate
/// semantics). Returns the input unchanged if it can't be decoded. Runs in a
/// background isolate via [compute].
Uint8List flip180(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    return Uint8List.fromList(
        img.encodeJpg(img.copyRotate(decoded, angle: 180), quality: 92));
  } catch (_) {
    return raw;
  }
}

/// Returns selfie JPEG [raw] rotated to UPRIGHT. Some front cameras write pixels
/// upside-down while reporting EXIF orientation = 1, so a bake at upload time is
/// a no-op and the stored selfie ends up inverted everywhere. We probe the image
/// with ML Kit AS-IS and ROTATED 180°, and keep whichever orientation yields an
/// upright face. Mirrors the EHRMS app's capture flow.
///
/// Falls back to the original bytes if neither orientation shows a clearly
/// upright face (e.g. no face found), so we never make a good capture worse.
Future<Uint8List> normalizeSelfieUpright(Uint8List raw) async {
  try {
    final asis = await FaceDetectionHelper.detectFromBytes(raw);
    // As-captured already shows an upright face → nothing to do.
    if (asis.faceCount > 0 && !asis.isUpsideDown) return raw;

    final rotated = await compute(flip180, raw);
    final flipped = await FaceDetectionHelper.detectFromBytes(rotated);
    // Rotating 180° produced an upright face → the capture was inverted.
    if (flipped.faceCount > 0 && !flipped.isUpsideDown) return rotated;

    // As-is has a face that's explicitly upside-down → rotating is the better bet.
    if (asis.faceCount > 0 && asis.isUpsideDown) return rotated;

    // Couldn't find a clearly-upright face either way: leave the capture as-is.
    return raw;
  } catch (_) {
    return raw;
  }
}
