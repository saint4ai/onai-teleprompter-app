import 'package:flutter_test/flutter_test.dart';
import 'package:tiefprompt/core/constants.dart';
import 'package:tiefprompt/core/hold_scroll.dart';

void main() {
  group('holdScrollLinesPerSecond', () {
    test('короткое нажатие — это клик, быстрой прокрутки нет', () {
      expect(holdScrollLinesPerSecond(Duration.zero), 0);
      expect(holdScrollLinesPerSecond(const Duration(milliseconds: 299)), 0);
    });

    test('после задержки и до 3 секунд — медленная прокрутка', () {
      expect(
        holdScrollLinesPerSecond(kHoldScrollDelay),
        kHoldScrollSlowLinesPerSecond,
      );
      expect(
        holdScrollLinesPerSecond(const Duration(milliseconds: 2999)),
        kHoldScrollSlowLinesPerSecond,
      );
    });

    test('после 3 секунд плавно разгоняется до быстрой', () {
      final middle = holdScrollLinesPerSecond(
        kHoldScrollFastAfter + kHoldScrollRamp ~/ 2,
      );
      expect(middle, greaterThan(kHoldScrollSlowLinesPerSecond));
      expect(middle, lessThan(kHoldScrollFastLinesPerSecond));
      expect(
        holdScrollLinesPerSecond(kHoldScrollFastAfter + kHoldScrollRamp),
        kHoldScrollFastLinesPerSecond,
      );
      expect(
        holdScrollLinesPerSecond(const Duration(seconds: 30)),
        kHoldScrollFastLinesPerSecond,
      );
    });
  });
}
