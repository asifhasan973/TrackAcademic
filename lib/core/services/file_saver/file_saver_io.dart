import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'file_saver.dart';

/// Mobile/Desktop file saver using app internal storage / downloads.
class IoFileSaver implements FileSaver {
  const IoFileSaver();

  @override
  Future<String> saveFile({
    required String filename,
    required String content,
    required String mimeType,
  }) async {
    Directory directory;
    try {
      final downloadsDir = await getDownloadsDirectory();
      directory = downloadsDir ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      directory = await getApplicationDocumentsDirectory();
    }

    final file = File('${directory.path}/$filename');
    await file.writeAsString(content, flush: true);

    return file.path;
  }
}

FileSaver getPlatformFileSaver() => const IoFileSaver();
