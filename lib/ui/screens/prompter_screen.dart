import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tiefprompt/core/constants.dart';
import 'package:tiefprompt/core/control_buttons.dart';
import 'package:tiefprompt/core/debouncer.dart';
import 'package:tiefprompt/core/hold_scroll.dart';
import 'package:tiefprompt/models/keybinding.dart';
import 'package:tiefprompt/providers/feature_provider.dart';
import 'package:tiefprompt/providers/keybinding_provider.dart';
import 'package:tiefprompt/providers/prompter_provider.dart';
import 'package:tiefprompt/providers/settings_provider.dart';
import 'package:tiefprompt/services/script_service.dart';
import 'package:tiefprompt/ui/widgets/countdown_timer.dart';
import 'package:tiefprompt/ui/widgets/current_chapter_banner.dart';
import 'package:tiefprompt/ui/widgets/prompter_bottom_bar.dart';
import 'package:tiefprompt/ui/widgets/prompter_control_buttons_overlay.dart';
import 'package:tiefprompt/ui/widgets/prompter_top_bar.dart';
import 'package:tiefprompt/ui/widgets/vertical_margin.dart';
import 'package:tiefprompt/ui/widgets/scrollable_text.dart';
import 'package:tiefprompt/providers/script_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class _ControlsVisible extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
}

final controlsVisibleProvider = NotifierProvider<_ControlsVisible, bool>(
  _ControlsVisible.new,
);

class PrompterScreen extends ConsumerStatefulWidget {
  const PrompterScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends ConsumerState<PrompterScreen>
    with SingleTickerProviderStateMixin {
  final _focusNode = FocusNode();
  late final ScrollableTextController _scrollableTextController;
  late final Debouncer _scrollableTextControllerSaveDebouncer;

  // onAI: быстрая прокрутка, пока держат стрелку вверх/вниз.
  late final Ticker _holdTicker;
  late final AppLifecycleListener _lifecycleListener;
  LogicalKeyboardKey? _holdKey;
  int _holdDirection = 0;
  Duration _lastHoldElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _scrollableTextController = ScrollableTextController();
    _holdTicker = createTicker(_onHoldTick);
    // Приложение ушло в фон — отпускания кнопки можем не получить, удержание снимаем сразу.
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) {
          _stopHold();
        }
      },
    );
    // Привязки грузятся из базы асинхронно — начинаем заранее, чтобы первое нажатие
    // на пульте не потерялось.
    ref.read(keybindingsProvider);
    _scrollableTextControllerSaveDebouncer = PeriodicRunDebouncer(
      delay: Duration(seconds: 1),
      periodicDelay: Duration(seconds: 5),
    );
    WakelockPlus.enable();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.leanBack);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollableTextController.scrollController.hasClients) {
        final storedScrollOffset = ref.read(scriptProvider).scrollPosition;
        _scrollableTextController.jumpTo(
          storedScrollOffset ?? MediaQuery.of(context).size.height / 2,
        );
      }
    });

    ref.read(settingsProvider).whenData((data) {
      ref.read(prompterProvider.notifier).applySettings(data);
    });

    _scrollableTextController.scrollController.addListener(_saveOnScroll);
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);

    ref.listen(settingsProvider, (previous, next) async {
      next.whenData((data) {
        ref.read(prompterProvider.notifier).applySettings(data);
      });
    });

    final (:prompterConfig, :displayCountdown) = ref.watch(
      prompterProvider.select(
        (p) => (prompterConfig: p.config, displayCountdown: p.displayCountdown),
      ),
    );

    return Focus(
      onKeyEvent: _onKeyEvent,
      // Фокус ушёл (открыли настройки) — отпускания кнопки здесь не будет.
      onFocusChange: (hasFocus) {
        if (!hasFocus) {
          _stopHold();
        }
      },
      focusNode: _focusNode,
      autofocus: true,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () {
                ref.read(controlsVisibleProvider.notifier).toggle();
              },
              child: SafeArea(
                minimum: const EdgeInsets.all(16.0),
                child: ScrollableText(
                  controller: _scrollableTextController,
                  text: script.text,
                  style: TextStyle(
                    fontSize: prompterConfig.fontSize,
                    fontFamily: prompterConfig.fontFamily,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  sideMargin:
                      (MediaQuery.of(context).size.width / 2) *
                      (prompterConfig.sideMargin / 100),
                ),
              ),
            ),
            if (prompterConfig.displayVerticalMarginBoxes)
              VerticalMargin(
                heightRatio: prompterConfig.verticalMarginBoxesHeight,
                color: Theme.of(context).canvasColor,
                fade: prompterConfig.verticalMarginBoxesFadeEnabled,
                // NOTE: fadeLength should be normalized to [0, 1]
                fadeLength: prompterConfig.verticalMarginBoxesFadeLength / 100,
              ),
            if (prompterConfig.displayReadingIndicatorBoxes)
              VerticalMargin(
                heightRatio: prompterConfig.readingIndicatorBoxesHeight,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(60),
              ),
            CurrentChapterBanner(
              offset: ref.watch(controlsVisibleProvider)
                  ? EdgeInsets.fromLTRB(0, 64, 0, 0)
                  : EdgeInsets.all(0),
            ),
            if ((!ref.watch(controlsVisibleProvider) ||
                    (prompterConfig.controlButtonsPosition ==
                            ControlButtonsPosition.left ||
                        prompterConfig.controlButtonsPosition ==
                            ControlButtonsPosition.right)) &&
                prompterConfig.showControlButtons)
              PrompterControlButtonsOverlay(),
            if (ref.watch(controlsVisibleProvider)) PrompterTopBar(),
            if (ref.watch(controlsVisibleProvider)) PrompterBottomBar(),
            if (displayCountdown && prompterConfig.countdownDuration > 0)
              CountdownTimer(
                duration: prompterConfig.countdownDuration.toInt(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    WakelockPlus.disable();
    _lifecycleListener.dispose();
    _holdTicker.dispose();
    _focusNode.dispose();
    _scrollableTextController.dispose();
    _scrollableTextControllerSaveDebouncer.dispose();
    super.dispose();
  }

  // onAI: назначенные клавиши помечаются обработанными — система не уводит фокус
  // стрелками и не нажимает кнопки панели. Клик ↑/↓ сдвигает текст сразу,
  // удержание включает быструю прокрутку, отпускание возвращает обычный показ.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent && event.logicalKey == _holdKey) {
      _stopHold();
      return KeyEventResult.handled;
    }

    final actions = ref
        .read(keybindingsProvider.notifier)
        .actionsForEvent(event);
    if (actions.isEmpty) {
      return KeyEventResult.ignored;
    }

    // Отпускание назначенной клавиши обрабатываем так же, как нажатие, — иначе
    // система получает «отпускание» без «нажатия».
    if (event is KeyUpEvent) {
      return KeyEventResult.handled;
    }

    // Автоповтор при удержании не повторяет действие: прокрутку ведёт таймер удержания,
    // а пауза и скорость меняются только по нажатию.
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }

    _runActions(actions);

    final direction = _holdDirectionFor(actions);
    if (direction != 0 && _isFeatureEnabled(Feature.keybindings)) {
      _startHold(event.logicalKey, direction);
    }
    return KeyEventResult.handled;
  }

  int _holdDirectionFor(List<KeybindingAction> actions) {
    if (actions.contains(KeybindingAction.scrollUp)) {
      return -1;
    }
    if (actions.contains(KeybindingAction.scrollDown)) {
      return 1;
    }
    return 0;
  }

  void _startHold(LogicalKeyboardKey key, int direction) {
    _stopHold();
    _holdKey = key;
    _holdDirection = direction;
    _lastHoldElapsed = Duration.zero;
    _holdTicker.start();
  }

  void _stopHold() {
    if (_holdTicker.isActive) {
      _holdTicker.stop();
    }
    _holdKey = null;
    _holdDirection = 0;
    _scrollableTextController.holdActive = false;
  }

  void _onHoldTick(Duration elapsed) {
    final holdKey = _holdKey;
    if (holdKey == null ||
        !HardwareKeyboard.instance.logicalKeysPressed.contains(holdKey)) {
      _stopHold();
      return;
    }

    final linesPerSecond = holdScrollLinesPerSecond(elapsed);
    final deltaSeconds =
        (elapsed - _lastHoldElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastHoldElapsed = elapsed;

    if (linesPerSecond == 0) {
      return;
    }

    _scrollableTextController.holdActive = true;
    // Высота строки — как у автопрокрутки: размер шрифта × 1.0.
    final lineHeight = ref.read(prompterProvider).config.fontSize;
    _scrollableTextController.jumpRelativeClamped(
      _holdDirection * linesPerSecond * lineHeight * deltaSeconds,
    );
  }

  bool _isFeatureEnabled(Feature feature) => ref
      .read(featuresProvider)
      .features
      .contains(feature);

  void _runActions(List<KeybindingAction> actions) {
    if (!context.mounted) {
      throw StateError("Context not available.");
    }

    for (final action in actions) {
      switch (action) {
        case KeybindingAction.playPause:
          _gatedKeybinding(
            Feature.playPause,
            () => ref.read(prompterProvider.notifier).togglePlayPause(),
          );
          break;
        case KeybindingAction.scrollUp:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpRelative(-75),
          );
          break;
        case KeybindingAction.scrollDown:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpRelative(75),
          );
          break;
        case KeybindingAction.scrollUpSmall:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpRelative(-25),
          );
          break;
        case KeybindingAction.scrollDownSmall:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpRelative(25),
          );
          break;
        case KeybindingAction.pageUp:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpRelative(
              -MediaQuery.of(context).size.height,
            ),
          );
          break;
        case KeybindingAction.pageDown:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpRelative(
              MediaQuery.of(context).size.height,
            ),
          );
          break;
        case KeybindingAction.jumpStart:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpTo(0),
          );
          break;
        case KeybindingAction.jumpEnd:
          _gatedKeybinding(
            Feature.keybindings,
            () => _scrollableTextController.jumpTo(
              _scrollableTextController
                  .scrollController
                  .position
                  .maxScrollExtent,
            ),
          );
          break;
        case KeybindingAction.toggleControls:
          _gatedKeybinding(
            Feature.keybindings,
            () => ref.read(controlsVisibleProvider.notifier).toggle(),
          );
          break;
        case KeybindingAction.fontSizeUp:
          _gatedKeybinding(
            Feature.fontSize,
            () => ref.read(prompterProvider.notifier).increaseFontSize(1),
          );
          break;
        case KeybindingAction.fontSizeDown:
          _gatedKeybinding(
            Feature.fontSize,
            () => ref.read(prompterProvider.notifier).decreaseFontSize(1),
          );
          break;
        case KeybindingAction.speedUp:
          _gatedKeybinding(
            Feature.keybindings,
            () => ref.read(prompterProvider.notifier).increaseSpeed(.1),
          );
          break;
        case KeybindingAction.speedDown:
          _gatedKeybinding(
            Feature.keybindings,
            () => ref.read(prompterProvider.notifier).decreaseSpeed(.1),
          );
          break;
        case KeybindingAction.openSettings:
          _gatedKeybinding(
            Feature.keybindings,
            () => context.push('/settings'),
          );
          break;
        case KeybindingAction.saveSettingsFromPrompter:
          _gatedKeybinding(
            Feature.keybindings,
            () => ref
                .read(settingsProvider.notifier)
                .applySettingsFromPrompter(ref.read(prompterProvider)),
          );
          break;
      }
    }
  }

  void _gatedKeybinding(Feature feature, Function() action) {
    final isEnabled = ref.watch(
      featuresProvider.select((s) => s.features.contains(feature)),
    );

    if (isEnabled) {
      action();
    }
  }

  void _saveOnScroll() {
    _scrollableTextControllerSaveDebouncer.run(_saveScrollPosition);
  }

  void _saveScrollPosition() {
    final scriptId = ref.read(scriptProvider).id;
    final scrollOffset = _scrollableTextController.scrollController.offset;

    ref.read(scriptProvider.notifier).setScrollPosition(scrollOffset);
    if (scriptId != null) {
      ref
          .read(scriptServiceProvider.notifier)
          .updateScrollPosition(scriptId, scrollOffset);
    }
  }
}
