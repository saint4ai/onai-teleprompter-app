import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:tiefprompt/models/database.dart';
import 'package:tiefprompt/models/keybinding.dart';
import 'package:tiefprompt/providers/database_provider.dart';
import 'package:tiefprompt/providers/keybinding_provider.dart';
import 'package:tiefprompt/providers/talker_provider.dart';

class _InMemoryDatabase extends AppDatabaseManager {
  @override
  AppDatabase build() {
    final db = AppDatabase(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }
}

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Keybindings keybindings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        appDatabaseManagerProvider.overrideWith(_InMemoryDatabase.new),
        talkerProvider.overrideWithValue(Talker()),
      ],
    );
    await container.read(keybindingsProvider.future);
    keybindings = container.read(keybindingsProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('пульт по умолчанию: ←/→ — скорость, центр — старт/пауза, ↑/↓ — прокрутка', () {
    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.arrowLeft)), [
      KeybindingAction.speedDown,
    ]);
    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.arrowRight)), [
      KeybindingAction.speedUp,
    ]);
    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.select)), [
      KeybindingAction.playPause,
    ]);
    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.arrowUp)), [
      KeybindingAction.scrollUp,
    ]);
    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.arrowDown)), [
      KeybindingAction.scrollDown,
    ]);
  });

  test('назначение занятой кнопки переносит её на новое действие', () async {
    await keybindings.addBinding(
      KeybindingAction.speedUp,
      Keybinding(keyId: LogicalKeyboardKey.arrowUp.keyId),
    );

    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.arrowUp)), [
      KeybindingAction.speedUp,
    ]);
  });

  test('удаление одной кнопки не стирает другие кнопки того же действия', () async {
    await keybindings.removeBinding(
      KeybindingAction.playPause,
      Keybinding(keyId: LogicalKeyboardKey.enter.keyId),
    );

    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.enter)), isEmpty);
    expect(keybindings.actionsForEvent(_down(LogicalKeyboardKey.space)), [
      KeybindingAction.playPause,
    ]);
  });
}
