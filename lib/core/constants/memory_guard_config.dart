import 'dart:io';

/// Políticas adaptativas de protección de memoria RAM (OOM Prevention)
/// diferenciadas entre dispositivos Móviles (Android/iOS) y Escritorio.
class MemoryGuardConfig {
  /// Límite máximo seguro del lado mayor en píxeles al decodificar imágenes en un [Isolate].
  static int get maxSafeImageDimensionPx {
    if (Platform.isAndroid || Platform.isIOS) {
      return 2560; // Protege el heap de móviles ante cámaras de 48MP / 108MP
    }
    return 4096; // 4K en Windows / macOS / Linux
  }

  /// Ancho máximo de caché de decodificación (`cacheWidth`) para miniaturas en cuadrículas UI.
  static int get thumbnailDecodeWidthPx {
    if (Platform.isAndroid || Platform.isIOS) {
      return 260;
    }
    return 340;
  }

  /// Umbral máximo de archivos simultáneos recomendados por lote en móvil.
  static int get recommendedMaxBatchSize {
    if (Platform.isAndroid || Platform.isIOS) {
      return 50;
    }
    return 250;
  }

  /// Resolución DPI segura para rasterizar miniaturas de vista previa en PDFs.
  static double get pdfPreviewDpi {
    if (Platform.isAndroid || Platform.isIOS) {
      return 36.0;
    }
    return 45.0;
  }

  /// Indica si un lote supera el umbral recomendado para el dispositivo actual.
  static bool exceedsRecommendedBatch(int itemCount) =>
      itemCount > recommendedMaxBatchSize;

  /// Máximo de transcodificaciones de video concurrentes para proteger CPU y RAM.
  static int get maxConcurrentVideoTranscodes {
    if (Platform.isAndroid || Platform.isIOS) {
      return 1;
    }
    return 2;
  }

  /// Máximo de conversiones de audio concurrentes por lote.
  static int get maxConcurrentAudioTranscodes {
    if (Platform.isAndroid || Platform.isIOS) {
      return 2;
    }
    return 4;
  }
}



