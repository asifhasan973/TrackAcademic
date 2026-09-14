import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:trackademic/core/services/file_saver/file_saver.dart';

class SavedFileResult {
  final String displayPath;
  final String uri;
  final String mimeType;

  const SavedFileResult({
    required this.displayPath,
    required this.uri,
    required this.mimeType,
  });
}

class PlatformStorageService {
  static const _channel = MethodChannel('com.trackademic/storage_channel');

  const PlatformStorageService();

  /// Saves [bytes] to the public Downloads/TrackAcademic directory.
  /// On Android, uses MediaStore.Downloads (API 29+) or public Downloads directory (< API 29).
  /// On other platforms, falls back to the app file saver.
  Future<SavedFileResult> saveToDownloads({
    required String filename,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'saveToDownloads',
          {
            'filename': filename,
            'bytes': bytes,
            'mimeType': mimeType,
          },
        );

        if (result != null && result['displayPath'] != null) {
          return SavedFileResult(
            displayPath: result['displayPath'] as String,
            uri: result['uri'] as String? ?? '',
            mimeType: result['mimeType'] as String? ?? mimeType,
          );
        }
      } catch (e) {
        debugPrint('[PlatformStorageService] Android channel error: $e. Falling back to FileSaver.');
      }
    }

    // Fallback using FileSaver
    final saver = FileSaver();
    final path = await saver.saveFile(
      filename: filename,
      content: String.fromCharCodes(bytes),
      mimeType: mimeType,
    );

    return SavedFileResult(
      displayPath: path,
      uri: path,
      mimeType: mimeType,
    );
  }

  /// Opens the saved file with an external viewer app.
  Future<bool> openFile({
    required String uri,
    required String mimeType,
  }) async {
    if (!kIsWeb && Platform.isAndroid && uri.isNotEmpty) {
      try {
        final ok = await _channel.invokeMethod<bool>('openFile', {
          'uri': uri,
          'mimeType': mimeType,
        });
        return ok ?? false;
      } catch (e) {
        debugPrint('[PlatformStorageService] openFile error: $e');
        return false;
      }
    }
    return false;
  }

  /// Shares the saved file via Android Share sheet.
  Future<bool> shareFile({
    required String uri,
    required String mimeType,
  }) async {
    if (!kIsWeb && Platform.isAndroid && uri.isNotEmpty) {
      try {
        final ok = await _channel.invokeMethod<bool>('shareFile', {
          'uri': uri,
          'mimeType': mimeType,
        });
        return ok ?? false;
      } catch (e) {
        debugPrint('[PlatformStorageService] shareFile error: $e');
        return false;
      }
    }
    return false;
  }
}
