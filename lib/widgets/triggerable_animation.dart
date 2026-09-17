// widgets/triggerable_animation.dart
//
// 2026-09-17: minimal shared interface so GifSwipeTrigger can drive
// something other than a baked GIF (see flowing_data_animation.dart)
// through the exact same trigger()/isPlaying contract ActionGifState
// already has, without GifSwipeTrigger needing to know or care which
// concrete widget it's holding. Its own file (not living inside
// gif_swipe_trigger.dart or action_gif.dart) so both of those can
// depend on it without a circular import between them.
abstract class TriggerableAnimation {
  bool get isPlaying;
  Future<void> trigger(Future<void> Function() action);
}
