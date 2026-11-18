import 'dart:isolate';

/// Representa un archivo de imagen cargado para inspección y limpieza de metadatos EXIF.
class ExifImageItem {
  final String path;
  final String fileName;
  final int originalSizeBytes;
  final List<String> detectedTags;

  const ExifImageItem({
    required this.path,
    required this.fileName,
    required this.originalSizeBytes,
    this.detectedTags = const [],
  });
}

/// Configuración inmutable enviada al [Isolate] de limpieza de metadatos.
class ExifStripperBatchConfig {
  final List<String> inputPaths;
  final String sessionDirPath;
  final bool packageAsZip;
  final int maxDimensionPx;
  final int jpegQuality;

  const ExifStripperBatchConfig({
    required this.inputPaths,
    required this.sessionDirPath,
    this.packageAsZip = false,
    this.maxDimensionPx = 4096,
    this.jpegQuality = 95,
  });
}

class ExifStripperIsolateRequest {
  final SendPort sendPort;
  final ExifStripperBatchConfig config;

  const ExifStripperIsolateRequest({
    required this.sendPort,
    required this.config,
  });
}

/// Evento de progreso determinista emitido por el [Isolate] limpiador de EXIF.
class ExifStripperProgressEvent {
  final int currentIndex;
  final int totalFiles;
  final String statusMessage;
  final bool isCompleted;
  final List<String> outputFiles;
  final String? zipFilePath;
  final int totalTagsRemoved;
  final Map<String, List<String>> perFileRemovedTags;
  final String? errorMessage;

  const ExifStripperProgressEvent({
    required this.currentIndex,
    required this.totalFiles,
    required this.statusMessage,
    this.isCompleted = false,
    this.outputFiles = const [],
    this.zipFilePath,
    this.totalTagsRemoved = 0,
    this.perFileRemovedTags = const {},
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalFiles <= 0) return 0.0;
    return (currentIndex / totalFiles).clamp(0.0, 0.95);
  }
}
