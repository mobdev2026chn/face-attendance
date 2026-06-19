import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'face_detection_helper.dart';

/// Decides whether a stored selfie/avatar needs a 180° DISPLAY flip by DETECTING
/// the face's actual orientation (ML Kit) instead of guessing from a capture
/// timestamp. Mirrors the EHRMS app's AvatarOrientation.
///
/// Why: front-camera selfies on some devices were stored upside-down (rotated
/// pixels with EXIF orientation = 1, so an upload-time bake was a no-op). A
/// timestamp cutoff can't tell which images are actually affected, so it both
/// wrongly flips upright photos and misses genuinely-inverted ones. Running the
/// detector on the image is authoritative.
///
/// Decisions are cached per-source (memory; + SharedPreferences for http URLs)
/// so detection runs at most once per image. Returns null when orientation can't
/// be determined (no face / fetch / decode failed) so callers keep their fallback.
class AvatarOrientation {
  AvatarOrientation._();

  static const String _prefsPrefix = 'face_avatar_needs_flip_v1:';
  static final Map<String, bool> _memCache = {};

  static String _key(String source) {
    final s = source.trim();
    // base64 strings are huge — key by length+hash so the map stays small.
    return s.startsWith('http') ? s : 'b64:${s.length}:${s.hashCode}';
  }

  /// The cached decision for [source] if already known, else null.
  static Future<bool?> cachedDecision(String source) async {
    final s = source.trim();
    if (s.isEmpty) return null;
    final key = _key(s);
    if (_memCache.containsKey(key)) return _memCache[key];
    if (!s.startsWith('http')) return null; // base64 isn't persisted
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('$_prefsPrefix$key');
      if (v != null) _memCache[key] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Resolve (and cache) whether the image at [source] (http URL or base64) is
  /// stored upside-down and needs a 180° display flip. Returns null when it
  /// can't be determined (not cached in that case, so a later load can retry).
  static Future<bool?> resolveNeedsFlip(String source) async {
    final s = source.trim();
    if (s.isEmpty) return null;
    final key = _key(s);

    final existing = await cachedDecision(s);
    if (existing != null) return existing;

    try {
      Uint8List? bytes;
      if (s.startsWith('http')) {
        final resp = await http.get(Uri.parse(s));
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
        bytes = resp.bodyBytes;
      } else {
        final clean = s.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '');
        bytes = base64Decode(clean);
      }
      if (bytes.isEmpty) return null;

      final det = await FaceDetectionHelper.detectFromBytes(bytes);
      // No face detected → can't tell; let the caller keep its fallback and retry.
      if (det.rollZ == null) return null;

      final needsFlip = det.isUpsideDown;
      _memCache[key] = needsFlip;
      if (s.startsWith('http')) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('$_prefsPrefix$key', needsFlip);
        } catch (_) {}
      }
      return needsFlip;
    } catch (_) {
      return null;
    }
  }
}
