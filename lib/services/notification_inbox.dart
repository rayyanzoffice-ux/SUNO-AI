import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class NotificationInbox {
  NotificationInbox({this.directory});
  final Directory? directory;

  Future<Directory> _directory() async {
    final folder =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/notification_inbox',
        );
    await folder.create(recursive: true);
    return folder;
  }

  Future<void> add(Map<String, String> data) async {
    final folder = await _directory();
    final name =
        '${DateTime.now().microsecondsSinceEpoch}-${const Uuid().v4()}';
    final pending = File('${folder.path}/$name.pending');
    await pending.writeAsString(jsonEncode(data), flush: true);
    await pending.rename('${folder.path}/$name.json');
  }

  Future<void> drain(Future<void> Function(Map<String, String>) accept) async {
    final folder = await _directory();
    final files = await folder
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final entry in files) {
      final file = entry as File;
      dynamic decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } on FormatException {
        await file.delete();
        continue;
      }
      if (decoded is! Map<String, dynamic> ||
          decoded.values.any((value) => value is! String)) {
        await file.delete();
        continue;
      }
      await accept(Map<String, String>.from(decoded));
      await file.delete();
    }
  }
}
