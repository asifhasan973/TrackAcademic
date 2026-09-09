import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'file_saver.dart';

/// Web file saver using browser Blob download via package:web.
class WebFileSaver implements FileSaver {
  const WebFileSaver();

  @override
  Future<String> saveFile({
    required String filename,
    required String content,
    required String mimeType,
  }) async {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';

    web.document.body?.appendChild(anchor);
    anchor.click();
    web.document.body?.removeChild(anchor);
    web.URL.revokeObjectURL(url);

    return filename;
  }
}

FileSaver getPlatformFileSaver() => const WebFileSaver();
