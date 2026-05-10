import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;

  late Logger _logger;
  late File _logFile;

  LoggerService._internal();

  Future<void> initialize() async {
    final Directory configDir = Directory(p.join(Platform.environment['HOME']!, '.config', 'fyrbrowser'));
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }

    final Directory logsDir = Directory(p.join(configDir.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    _logFile = File(p.join(logsDir.path, 'fyrbrowser.log'));
    
    // Rotate log file if it's too big (e.g., > 5MB)
    if (await _logFile.exists() && await _logFile.length() > 5 * 1024 * 1024) {
      await _logFile.rename(p.join(logsDir.path, 'fyrbrowser_old.log'));
    }

    _logger = Logger(
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        printTime: true,
      ),
      output: MultiOutput([
        ConsoleOutput(),
        FileOutput(file: _logFile),
      ]),
    );
  }

  void d(String message) => _logger.d(message);
  void i(String message) => _logger.i(message);
  void w(String message) => _logger.w(message);
  void e(String message, [dynamic error, StackTrace? stackTrace]) => _logger.e(message, error: error, stackTrace: stackTrace);
  void v(String message) => _logger.v(message);
}

class FileOutput extends LogOutput {
  final File file;
  FileOutput({required this.file});

  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    }
  }
}

final logger = LoggerService();
