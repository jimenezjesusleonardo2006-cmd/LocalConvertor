import 'dart:isolate';

/// Modo de redimensionamiento de imagen.
enum ImageResizeMode {
  percentage('Por Porcentaje (%)'),
  exactDimensions('Dimensiones Exactas (px)');

  final String label;
  const ImageResizeMode(this.label);
}

/// Resultado de la estimación en tiempo real del peso final y dimensiones.
class CompressionEstimateResult {
  final int originalBytes;
  final int estimatedBytes;
  final int originalWidth;
  final int originalHeight;
  final int targetWidth;
  final int targetHeight;

  const CompressionEstimateResult({
    required this.originalBytes,
    required this.estimatedBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.targetWidth,
    required this.targetHeight,
  });

  /// Porcentaje de reducción de tamaño (positivo = ahorro de espacio).
  double get savingsPercent {
    if (originalBytes <= 0) return 0.0;
    return ((originalBytes - estimatedBytes) / originalBytes) * 100.0;
  }
}

/// Configuración inmutable para comprimir y redimensionar un lote de imágenes.
class CompressorResizerBatchConfig {
  final List<String> inputPaths;
  final String sessionDirPath;
  final ImageResizeMode resizeMode;
  final int scalePercent; // 10 - 100
  final int? targetWidthPx;
  final int? targetHeightPx;
  final bool maintainAspectRatio;
  final int quality; // 1 - 100
  final int maxDimensionPx;

  const CompressorResizerBatchConfig({
    required this.inputPaths,
    required this.sessionDirPath,
    this.resizeMode = ImageResizeMode.percentage,
    this.scalePercent = 100,
    this.targetWidthPx,
    this.targetHeightPx,
    this.maintainAspectRatio = true,
    this.quality = 80,
    this.maxDimensionPx = 4096,
  });
}

class CompressorIsolateRequest {
  final SendPort sendPort;
  final CompressorResizerBatchConfig config;

  const CompressorIsolateRequest({
    required this.sendPort,
    required this.config,
  });
}

class CompressorProgressEvent {
  final int currentIndex;
  final int totalFiles;
  final String statusMessage;
  final bool isCompleted;
  final List<String> outputFiles;
  final String? zipFilePath;
  final int totalOriginalBytes;
  final int totalCompressedBytes;
  final String? errorMessage;

  const CompressorProgressEvent({
    required this.currentIndex,
    required this.totalFiles,
    required this.statusMessage,
    this.isCompleted = false,
    this.outputFiles = const [],
    this.zipFilePath,
    this.totalOriginalBytes = 0,
    this.totalCompressedBytes = 0,
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalFiles <= 0) return 0.0;
    return (currentIndex / totalFiles).clamp(0.0, 0.95);
  }
}



