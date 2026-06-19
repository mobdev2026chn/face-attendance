/// Cross-app selfie orientation handling for EHRMS images shown in the face app.
///
/// Legacy EHRMS punch/break/permission selfies were stored rotated 180°: the front
/// camera wrote upside-down pixels with EXIF orientation = 1, so the upload-time
/// bake was a no-op. As of the EHRMS capture-time rotation fix, images captured
/// at/after [selfieFlipCutoffUtc] are stored UPRIGHT.
///
/// This MUST match the EHRMS app's AppConstants.selfieOrientationFixCutoffUtc.
/// SET IT to the UTC instant the EHRMS build with the capture-time rotation fix
/// went live.
final DateTime selfieFlipCutoffUtc = DateTime.utc(2026, 6, 17);

/// Whether an EHRMS-sourced image needs a 180° display flip.
///
/// Only http (EHRMS) images captured BEFORE the cutoff are legacy/upside-down.
/// Base64 (local kiosk) captures are always upright. An http image with no usable
/// capture time is assumed legacy (flipped), since real EHRMS records always carry
/// a timestamp and only old data lacks one.
bool ehrmsSelfieNeedsFlip(String? source, {String? captureIso}) {
  final s = source?.trim() ?? '';
  if (!s.startsWith('http')) return false;
  if (captureIso == null || captureIso.isEmpty) return true;
  final dt = DateTime.tryParse(captureIso);
  if (dt == null) return true;
  return dt.toUtc().isBefore(selfieFlipCutoffUtc);
}
