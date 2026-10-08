import 'package:tiefprompt/core/constants.dart';

/// onAI: скорость быстрой прокрутки (строк в секунду) в зависимости от того,
/// сколько держат стрелку. До [kHoldScrollDelay] — 0 (это ещё клик), до
/// [kHoldScrollFastAfter] — медленная, дальше за [kHoldScrollRamp] плавно
/// разгоняется до быстрой.
double holdScrollLinesPerSecond(Duration heldFor) {
  if (heldFor < kHoldScrollDelay) {
    return 0;
  }

  final sinceFast = heldFor - kHoldScrollFastAfter;
  if (sinceFast.isNegative) {
    return kHoldScrollSlowLinesPerSecond;
  }

  final rampProgress =
      (sinceFast.inMicroseconds / kHoldScrollRamp.inMicroseconds).clamp(
        0.0,
        1.0,
      );
  return kHoldScrollSlowLinesPerSecond +
      (kHoldScrollFastLinesPerSecond - kHoldScrollSlowLinesPerSecond) *
          rampProgress;
}
