// services/sync_log.dart
//
// 2026-11-13 owner: "add log capture, might be useful with the Send diagnosis too". A small log of what the app did
// and when: each pull, push and background sync (start, end, result kind, seconds), and the slow message coming and
// going. NEVER holds note text, file names or paths: only event names, result kinds and times. Kept on this phone only
// (last ~400 lines); nothing is sent anywhere. The person copies it from the menu, or reads it in Send details.
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SyncLog {
  static const _max = 400;
  static File? _file;
  static final List<String> _mem = [];
  static bool _loaded = false;
  static Future<void> _chain = Future.value();

  static String _stamp() {
    final n = DateTime.now();
    String z(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${n.year}-${z(n.month)}-${z(n.day)} ${z(n.hour)}:${z(n.minute)}:${z(n.second)}';
  }

  static Future<File?> _f() async {
    if (_file != null) return _file;
    try {
      final d = await getApplicationSupportDirectory();
      return _file = File('${d.path}/sync_log.txt');
    } catch (_) {
      return null; // e.g. in tests: the in-memory copy still works
    }
  }

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final f = await _f();
    if (f != null && await f.exists()) {
      final old = (await f.readAsLines());
      _mem.insertAll(0, old.length > _max ? old.sublist(old.length - _max) : old);
    }
  }

  /// One event line. Safe to call anywhere; never throws.
  static void add(String event) {
    final line = '${_stamp()}  $event';
    _chain = _chain.then((_) async {
      try {
        await _load();
        _mem.add(line);
        if (_mem.length > _max) _mem.removeRange(0, _mem.length - _max);
        final f = await _f();
        if (f != null) await f.writeAsString(_mem.join('\n') + '\n');
      } catch (_) {}
    });
  }

  /// The last [n] lines, oldest first.
  static Future<String> tail({int n = 60}) async {
    await _chain;
    await _load();
    final l = _mem.length > n ? _mem.sublist(_mem.length - n) : _mem;
    return l.join('\n');
  }
}
