import 'dart:typed_data';

/// Formato de imagen de salida al extraer páginas de un PDF.
enum PdfImageOutputFormat {
  png('PNG (Sin pérdida)', 'png'),
  jpg('JPG (Comprimido)', 'jpg');

  final String label;
  final String extension;
  const PdfImageOutputFormat(this.label, this.extension);
}

/// Modo de entrega de las imágenes extraídas.
enum PdfImagePackagingMode {
  zipArchive('Empaquetar todo en un archivo .ZIP'),
  folderOrZip('Guardar archivos individuales (Carpeta en Escritorio / ZIP en Móvil)');

  final String label;
  const PdfImagePackagingMode(this.label);
}

/// Resolución de rasterización en puntos por pulgada (DPI).
enum PdfRasterDpiOption {
  standard(150.0, 'Estándar (150 DPI)'),
  high(220.0, 'Alta definición (220 DPI)'),
  printQuality(300.0, 'Impresión (300 DPI)');

  final double dpi;
  final String label;
  const PdfRasterDpiOption(this.dpi, this.label);
}

/// Configuración para extraer páginas de un PDF a imágenes.
class PdfToImagesConfig {
  final String sourcePdfPath;
  final String sessionDirPath;
  final PdfImageOutputFormat outputFormat;
  final PdfImagePackagingMode packagingMode;
  final PdfRasterDpiOption dpiOption;
  final int jpgQuality;

  const PdfToImagesConfig({
    required this.sourcePdfPath,
    required this.sessionDirPath,
    this.outputFormat = PdfImageOutputFormat.png,
    this.packagingMode = PdfImagePackagingMode.zipArchive,
    this.dpiOption = PdfRasterDpiOption.high,
    this.jpgQuality = 90,
  });
}

/// Datos crudos RGBA de una página rasterizada enviados al [Isolate] para codificación.
class RawRasterPagePayload {
  final int pageNumber;
  final int width;
  final int height;
  final Uint8List rgbaPixels;
  final PdfImageOutputFormat format;
  final int jpgQuality;

  const RawRasterPagePayload({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.rgbaPixels,
    required this.format,
    required this.jpgQuality,
  });
}

/// Progreso determinista de la extracción de PDF a Imágenes.
class PdfToImagesProgress {
  final int processedPages;
  final int? totalPages;
  final String statusMessage;
  final bool isCompleted;
  final String? zipFilePath;
  final List<String> extractedImagePaths;
  final String? errorMessage;

  const PdfToImagesProgress({
    required this.processedPages,
    this.totalPages,
    required this.statusMessage,
    this.isCompleted = false,
    this.zipFilePath,
    this.extractedImagePaths = const [],
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalPages == null || totalPages! <= 0) {
      return (processedPages * 0.08).clamp(0.05, 0.90);
    }
    return (processedPages / totalPages!).clamp(0.0, 0.95);
  }
}



