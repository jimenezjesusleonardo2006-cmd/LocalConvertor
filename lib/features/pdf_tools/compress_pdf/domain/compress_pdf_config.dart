/// Nivel de compresión para optimización local de peso de PDFs.
enum CompressPdfLevel {
  losslessVector(
    'Optimización Vectorial (Sin pérdida)',
    'Comprime flujos internos y limpia objetos sin rasterizar el texto.',
    0,
    100,
  ),
  highQuality(
    'Equilibrado (150 DPI • Calidad 80%)',
    'Remuestrea páginas pesadas respetando límites de memoria.',
    150,
    80,
  ),
  maximumCompression(
    'Compresión Máxima (110 DPI • Calidad 62%)',
    'Máxima reducción de tamaño para archivo o envío ligero.',
    110,
    62,
  );

  final String label;
  final String description;
  final int dpi;
  final int jpegQuality;
  const CompressPdfLevel(
    this.label,
    this.description,
    this.dpi,
    this.jpegQuality,
  );
}

/// Configuración para comprimir un documento PDF localmente.
class CompressPdfConfig {
  final String sourcePdfPath;
  final String outputPdfPath;
  final CompressPdfLevel level;
  final int maxDimensionPx;

  const CompressPdfConfig({
    required this.sourcePdfPath,
    required this.outputPdfPath,
    this.level = CompressPdfLevel.highQuality,
    this.maxDimensionPx = 4096,
  });
}

/// Resultado comparativo tras comprimir un PDF.
class CompressPdfResult {
  final String outputPdfPath;
  final int originalBytes;
  final int compressedBytes;
  final int pageCount;

  const CompressPdfResult({
    required this.outputPdfPath,
    required this.originalBytes,
    required this.compressedBytes,
    required this.pageCount,
  });

  double get savedPercent {
    if (originalBytes <= 0) return 0;
    return ((originalBytes - compressedBytes) / originalBytes * 100)
        .clamp(-100.0, 100.0);
  }
}
