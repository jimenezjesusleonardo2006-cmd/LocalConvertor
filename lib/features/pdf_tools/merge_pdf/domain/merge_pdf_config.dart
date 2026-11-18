import 'dart:typed_data';

/// Representa un documento PDF individual cargado para ser unido.
class MergePdfDocumentItem {
  final String id;
  final String filePath;
  final String fileName;
  final int pageCount;
  final Uint8List? coverThumbnail;

  const MergePdfDocumentItem({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.pageCount,
    this.coverThumbnail,
  });

  MergePdfDocumentItem copyWith({
    int? pageCount,
    Uint8List? coverThumbnail,
  }) {
    return MergePdfDocumentItem(
      id: id,
      filePath: filePath,
      fileName: fileName,
      pageCount: pageCount ?? this.pageCount,
      coverThumbnail: coverThumbnail ?? this.coverThumbnail,
    );
  }
}

/// Nivel de calidad de ensamblaje al unir múltiples PDFs.
enum MergePdfQualityPreset {
  balanced(160.0, 88, 'Equilibrado (160 DPI • Rápido)'),
  high(220.0, 92, 'Alta Fidelidad (220 DPI • Nitidez)'),
  archival(300.0, 96, 'Impresión (300 DPI • Máxima calidad)');

  final double dpi;
  final int jpegQuality;
  final String label;
  const MergePdfQualityPreset(this.dpi, this.jpegQuality, this.label);
}

/// Página intermedia preparada para ser ensamblada por el [Isolate] en el PDF final.
class PreparedPdfPageSlice {
  final Uint8List jpegBytes;
  final double widthPoints;
  final double heightPoints;

  const PreparedPdfPageSlice({
    required this.jpegBytes,
    required this.widthPoints,
    required this.heightPoints,
  });
}

///Evento de progreso determinista al unir múltiples PDFs.
class MergePdfProgress {
  final int currentDocIndex;
  final int totalDocs;
  final int processedPages;
  final int totalPages;
  final String statusMessage;
  final bool isCompleted;
  final String? outputPdfPath;
  final String? errorMessage;

  const MergePdfProgress({
    required this.currentDocIndex,
    required this.totalDocs,
    required this.processedPages,
    required this.totalPages,
    required this.statusMessage,
    this.isCompleted = false,
    this.outputPdfPath,
    this.errorMessage,
  });

  double get progress {
    if (isCompleted) return 1.0;
    if (totalPages <= 0) return 0.0;
    return (processedPages / totalPages).clamp(0.0, 0.94);
  }
}



