import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiefprompt/providers/prompter_provider.dart';
import 'package:tiefprompt/providers/settings_provider.dart';

void main() {
  late ProviderContainer container;
  late Prompter prompter;

  setUp(() {
    container = ProviderContainer();
    container.listen(prompterProvider, (_, _) {});
    prompter = container.read(prompterProvider.notifier);
  });

  tearDown(() => container.dispose());

  final saved = SettingsState();

  test('правка шрифта в настройках не сбрасывает скорость и зеркало из суфлёра', () {
    prompter.applySettings(saved);
    prompter.increaseSpeed(0.5);
    prompter.toggleMirroredX();

    prompter.applySettingsChange(
      saved,
      saved.copyWith(config: saved.config.copyWith(fontSize: 60)),
    );

    final config = container.read(prompterProvider).config;
    expect(config.fontSize, 60);
    expect(config.scrollSpeed, 1.5);
    expect(config.mirroredX, isTrue);
  });

  test('скорость, изменённая в настройках, применяется', () {
    prompter.applySettings(saved);
    prompter.increaseSpeed(0.5);

    prompter.applySettingsChange(
      saved,
      saved.copyWith(config: saved.config.copyWith(scrollSpeed: 2.0)),
    );

    expect(container.read(prompterProvider).config.scrollSpeed, 2.0);
  });

  test('первая загрузка настроек применяет их целиком', () {
    prompter.increaseSpeed(0.5);

    prompter.applySettingsChange(null, saved);

    expect(container.read(prompterProvider).config, saved.config);
  });
}
