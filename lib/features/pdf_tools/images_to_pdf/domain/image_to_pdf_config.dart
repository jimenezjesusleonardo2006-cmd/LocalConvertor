import 'dart:isolate';

/// Orientación de la página del documento PDF.
enum PdfPageOrientationOption {
  portrait,
  landscape,
}

/// Tamaño de página objetivo para cada imagen insertada.
enum PdfPageSizeOption {
  a4,
  letter,
  fitToImage,
}

/// Nivel de margen alrededor de cada imagen en la página PDF.
enum PdfMarginOption {
  none(0.0),
  small(16.0),
  large(42.0);

  /// Margen expresado en puntos tipográficos (1 pt = 1/72 pulgada).
  final double points;
  const PdfMarginOption(this.points);
}

/// Configuración inmutable para la conversión de Imágenes a PDF.
/// Segura para ser enviada a través de fronteras de [Isolate].
class ImageToPdfConfig {
  final List<String> imagePaths;
  final String outputFilePath;
  final PdfPageOrientationOption orientation;
  final PdfPageSizeOption pageSize;
  final PdfMarginOption margin;

  /// Calidad JPEG (1-100) al normalizar o comprimir imágenes para el PDF.
  final int jpegQuality;

  /// Límite máximo del lado mayor en píxeles para evitar desbordamientos de RAM (OOM)
  /// en dispositivos móviles al procesar fotos de alta resolución (ej. 48MP).
  final int maxDimensionPx;

  const ImageToPdfConfig({
    required this.imagePaths,
    required this.outputFilePath,
    this.orientation = PdfPageOrientationOption.portrait,
    this.pageSize = PdfPageSizeOption.a4,
    this.margin = PdfMarginOption.small,
    this.jpegQuality = 88,
    this.maxDimensionPx = 2800,
  });
}

/// Mensaje enviado al [Isolate] de trabajo al iniciar la conversión.
class ImageToPdfIsolateRequest {
  final SendPort mainSendPort;
  final ImageToPdfConfig config;

  const ImageToPdfIsolateRequest({
    required this.mainSendPort,
    required this.config,
  });
}

/// Estado del progreso determinista emitido desde el [Isolate] hacia el hilo principal.
enum ConversionStage {
  initializing,
  processingImage,
  writingPdf,
  completed,
  failed,
}

/// Evento inmutable emitido por el [Isolate] con el progreso determinista.
class ImageToPdfProgressEvent {
  final ConversionStage stage;
  final int currentIndex;
  final int totalImages;
  final String? currentFileName;
  final String? outputFilePath;
  final int? outputSizeBytes;
  final String? errorMessage;

  const ImageToPdfProgressEvent({
    required this.stage,
    required this.currentIndex,
    required this.totalImages,
    this.currentFileName,
    this.outputFilePath,
    this.outputSizeBytes,
    this.errorMessage,
  });

  /// Progreso normalizado entre 0.0 y 1.0 para alimentar un `LinearProgressIndicator`.
  double get progress {
    if (stage == ConversionStage.completed) return 1.0;
    if (totalImages <= 0) return 0.0;
    if (stage == ConversionStage.writingPdf) return 0.95;
    return (currentIndex / totalImages).clamp(0.0, 0.92);
  }
}



