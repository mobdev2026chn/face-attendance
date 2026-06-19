import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Audible + haptic feedback for punch/break outcomes. Plays custom tones bundled in
/// assets/sounds, paired with distinct haptics so feedback is unmistakable on a kiosk.
class FeedbackSound {
  // Low-latency player reused across cues (kiosk fires these rapidly).
  static final AudioPlayer _player = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);

  static Future<void> _play(String asset) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: 1.0);
    } catch (_) {/* feedback is best-effort */}
  }

  /// Punch/break captured correctly — pleasant ascending two-tone.
  static Future<void> success() async {
    _play('sounds/success.wav');
    await HapticFeedback.mediumImpact();
  }

  /// Any validation/error outcome — low descending buzz.
  static Future<void> error() async {
    _play('sounds/error.wav');
    await HapticFeedback.heavyImpact();
  }

  /// Soft warning (e.g. break allowance exceeded) — single mid beep.
  static Future<void> warn() async {
    _play('sounds/warn.wav');
    await HapticFeedback.vibrate();
  }
}
