import 'file_saver_stub.dart'
    if (dart.library.html) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart';

/// Platform-agnostic interface for saving generated files.
abstract interface class FileSaver {
  /// Saves or downloads [content] with the given [filename] and [mimeType].
  ///
  /// Returns a user-displayable path, filename, or confirmation string.
  Future<String> saveFile({
    required String filename,
    required String content,
    required String mimeType,
  });

  /// Factory returning the platform-specific implementation.
  factory FileSaver() => getPlatformFileSaver();
}
