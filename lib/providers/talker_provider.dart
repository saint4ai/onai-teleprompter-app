import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';

final talkerProvider = Provider<Talker>((ref) {
  throw UnimplementedError(
    'talkerProvider must be overridden in ProviderScope',
  );
});

Future<Talker> createTalker() async {
  // onAI: в браузере нет файлов — журнал только в памяти.
  if (kIsWeb) {
    return TalkerFlutter.init(
      settings: TalkerSettings(useHistory: true, maxHistoryItems: 1000),
    );
  }

  final dir = await getApplicationDocumentsDirectory();
  final logFile = File('${dir.path}/tiefprompt_logs.txt');

  final talker = TalkerFlutter.init(
    settings: TalkerSettings(useHistory: true, maxHistoryItems: 1000),
    observer: _FileObserver(logFile),
  );

  return talker;
}

class _FileObserver extends TalkerObserver {
  _FileObserver(this._file);

  final File _file;

  @override
  void onError(TalkerError err) => _write(err.generateTextMessage());

  @override
  void onException(TalkerException err) => _write(err.generateTextMessage());

  @override
  void onLog(TalkerData log) => _write(log.generateTextMessage());

  void _write(String message) {
    try {
      _file.writeAsStringSync('$message\n', mode: FileMode.append);
    } catch (_) {}
  }
}
