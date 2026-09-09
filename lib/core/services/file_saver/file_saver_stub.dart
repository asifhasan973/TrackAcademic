import 'file_saver.dart';

FileSaver getPlatformFileSaver() =>
    throw UnsupportedError('File saving is not supported on this platform.');
