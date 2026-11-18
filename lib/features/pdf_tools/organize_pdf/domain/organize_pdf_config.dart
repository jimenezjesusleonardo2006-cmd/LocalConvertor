import 'dart:typed_data';

/// Representa una página individual dentro del organizador visual de PDFs.
class OrganizePdfPageItem {
  final int id;
  final int originalPageIndex;
  final int rotationDeltaDegrees;
  final Uint8List? thumbnailBytes;

  const OrganizePdfPageItem({
    required this.id,
    required this.originalPageIndex,
    this.rotationDeltaDegrees = 0,
    this.thumbnailBytes,
  });

  OrganizePdfPageItem copyWith({
    int? rotationDeltaDegrees,
    Uint8List? thumbnailBytes,
  }) {
    return OrganizePdfPageItem(
      id: id,
      originalPageIndex: originalPageIndex,
      rotationDeltaDegrees: rotationDeltaDegrees ?? this.rotationDeltaDegrees,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
    );
  }
}

/// Configuración para reorganizar, rotar y exportar páginas vectoriales de un PDF.
class OrganizePdfConfig {
  final String sourcePdfPath;
  final String outputPdfPath;
  final List<OrganizePdfPageItem> pages;

  const OrganizePdfConfig({
    required this.sourcePdfPath,
    required this.outputPdfPath,
    required this.pages,
  });
}

/// Evento de progreso determinista al reorganizar un PDF.
class OrganizePdfProgress {
  final int processedPages;
  final int totalPages;
  final String statusMessage;
  final bool isCompleted;
  final String? outputPdfPath;
  final String? errorMessage;

  const OrganizePdfProgress({
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
    return (processedPages / totalPages).clamp(0.0, 0.95);
  }
}
