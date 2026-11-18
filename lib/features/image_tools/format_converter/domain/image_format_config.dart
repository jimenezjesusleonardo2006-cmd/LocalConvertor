import 'dart:isolate';

/// Formatos soportados para conversión bidireccional de imágenes.
enum TargetImageFormat {
  png('PNG', 'png', 'Sin pérdida • Soporta transparencia'),
  jpg('JPG', 'jpg', 'Comprimido • Ideal para fotografía'),
  webp('WEBP', 'webp', 'Formato moderno compacto'),
  bmp('BMP', 'bmp', 'Mapa de bits sin compresión'),
  tiff('TIFF', 'tiff', 'Sin pérdida • Archivo e impresión'),
  ico('ICO', 'ico', 'Icono de escritorio (hasta 256×256 px)'),
  gif('GIF', 'gif', 'Paleta compacta de 256 colores'),
  tga('TGA', 'tga', 'Textura raster Truevision Targa');

  final String label;
  final String extension;
  final String description;
  const TargetImageFormat(this.label, this.extension, this.description);
}

/// Elemento de imagen cargado en la cola de conversión por lotes.
class ImageBatchFileItem {
  final String path;
  final String fileName;
  final int originalSizeBytes;
  final String sourceExtension;

  const ImageBatchFileItem({
    required this.path,
    required this.fileName,
    required this.originalSizeBytes,
    required this.sourceExtension,
  });
}

/// Configuración inmutable enviada al [Isolate] de conversión de formatos.
class ImageFormatBatchConfig {
  final List<String> inputPaths;
  final String sessionDirPath;
  final TargetImageFormat targetFormat;
  final int quality;
  final bool packageAsZip;
  final int maxDimensionPx;
  final int svgScaleMultiplier;

  const ImageFormatBatchConfig({
    required this.inputPaths,
    required this.sessionDirPath,
    required this.targetFormat,
    this.quality = 90,
    this.packageAsZip = false,
    this.maxDimensionPx = 4096,
    this.svgScaleMultiplier = 2,
  });
}

class ImageFormatIsolateRequest {
  final SendPort sendPort;
  final ImageFormatBatchConfig config;

  const ImageFormatIsolateRequest({
    required this.sendPort,
    required this.config,
  });
}

/// Evento de progreso determinista emitido por el [Isolate] de conversión de formatos.
class ImageFormatProgressEvent {
  final int currentIndex;
  final int totalFiles;
  final String statusMessage;
  final bool isCompleted;
  final List<String> outputFiles;
  final String? zipFilePath;
  final String? errorMessage;

  const ImageFormatProgressEvent({
    required this.currentIndex,
    required this.totalFiles,
    required this.statusMessage,
    this.isCompleted = false,
    this.outputFiles = const [],
    this.zipFilePath,
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalFiles <= 0) return 0.0;
    return (currentIndex / totalFiles).clamp(0.0, 0.95);
  }
}
