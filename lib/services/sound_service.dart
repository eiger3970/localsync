// services/sound_service.dart
//
// 2026-09-24: launch check list, real ask - "Audio for important
// completions like? Push, Pull, Desktop sync, all conflicts cleared?"
// One short chime per event (assets/sounds/, synthesized for this app -
// no third-party audio, nothing to license):
//   push              rising two notes
//   pull              falling two notes
//   desktop_sync      three-note chord, rising
//   conflicts_cleared five-note arpeggio - the "done" moment
//
// Only for things the user started (a button, a Quick Action) - the
// callers decide that; background auto-sync on resume stays silent, or
// every app open would chime.
//
// iOS "ambient" audio: respects the silent switch and mixes with
// whatever else is playing instead of stopping the user's music - a
// completion chime should never be the reason a podcast pauses.
//
// On by default; Settings -> SOUNDS turns it off (saved on this device).

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SoundEvent { push, pull, desktopSync, conflictsCleared }

const _kSoundsEnabledKey = 'sounds_enabled';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  AudioPlayer? _player;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSoundsEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundsEnabledKey, enabled);
  }

  static String _asset(SoundEvent e) => switch (e) {
        SoundEvent.push => 'sounds/push.wav',
        SoundEvent.pull => 'sounds/pull.wav',
        SoundEvent.desktopSync => 'sounds/desktop_sync.wav',
        SoundEvent.conflictsCleared => 'sounds/conflicts_cleared.wav',
      };

  /// Plays [event]'s chime if sounds are on. Best-effort: a missing
  /// audio plugin (tests, desktop preview) or any playback error is
  /// silently ignored - a chime is never worth an error message.
  Future<void> play(SoundEvent event) async {
    try {
      if (!await isEnabled()) return;
      final player = _player ??= AudioPlayer()
        ..setAudioContext(AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ));
      await player.stop();
      await player.play(AssetSource(_asset(event)));
    } catch (_) {}
  }
}
