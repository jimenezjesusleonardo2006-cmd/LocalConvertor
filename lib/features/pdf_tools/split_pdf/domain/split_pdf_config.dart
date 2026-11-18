import 'page_range_parser.dart';

/// Modo de salida al dividir un documento PDF.
enum SplitOutputMode {
  singleCombinedPdf('Fusionar páginas extraídas en 1 solo PDF'),
  separatePdfsPerRangeZip('Crear 1 PDF por cada rango/página (.ZIP)');

  final String label;
  const SplitOutputMode(this.label);
}

/// Configuración para dividir o extraer páginas de un PDF.
class SplitPdfConfig {
  final String sourcePdfPath;
  final String sessionDirPath;
  final List<PdfPageSegment> segments;
  final Set<int> uniquePagesToExtract;
  final SplitOutputMode outputMode;
  final double dpi;
  final int jpegQuality;

  const SplitPdfConfig({
    required this.sourcePdfPath,
    required this.sessionDirPath,
    required this.segments,
    required this.uniquePagesToExtract,
    this.outputMode = SplitOutputMode.singleCombinedPdf,
    this.dpi = 220.0,
    this.jpegQuality = 92,
  });
}

/// Evento de progreso determinista al dividir un PDF.
class SplitPdfProgress {
  final int processedPages;
  final int totalPagesToExtract;
  final String statusMessage;
  final bool isCompleted;
  final String? singleOutputPdfPath;
  final String? zipOutputPath;
  final String? errorMessage;

  const SplitPdfProgress({
    required this.processedPages,
    required this.totalPagesToExtract,
    required this.statusMessage,
    this.isCompleted = false,
    this.singleOutputPdfPath,
    this.zipOutputPath,
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalPagesToExtract <= 0) return 0.0;
    return (processedPages / totalPagesToExtract).clamp(0.0, 0.94);
  }
}



