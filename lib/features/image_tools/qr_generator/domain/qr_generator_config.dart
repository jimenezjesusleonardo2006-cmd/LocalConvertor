enum QrOutputFormat {
  png('PNG', 'png', 'Imagen raster de alto contraste'),
  svg('SVG', 'svg', 'Gráfico vectorial escalable'),
  pdf('Lámina PDF', 'pdf', 'Hoja A4 imprimible (cuadrícula 3×4)');

  final String label;
  final String extension;
  final String description;
  const QrOutputFormat(this.label, this.extension, this.description);
}

enum QrErrorCorrection {
  low('L', 'L (7%)'),
  medium('M', 'M (15%)'),
  quartile('Q', 'Q (25%)'),
  high('H', 'H (30%)');

  final String code;
  final String label;
  const QrErrorCorrection(this.code, this.label);
}

class QrPreviewResult {
  final String previewPath;
  final int moduleCount;
  final int widthPx;

  const QrPreviewResult({
    required this.previewPath,
    required this.moduleCount,
    required this.widthPx,
  });
}

class QrBatchConfig {
  final List<String> items;
  final String sessionDirPath;
  final QrOutputFormat outputFormat;
  final QrErrorCorrection errorCorrection;
  final int sizePx;
  final bool packageAsZip;

  const QrBatchConfig({
    required this.items,
    required this.sessionDirPath,
    this.outputFormat = QrOutputFormat.png,
    this.errorCorrection = QrErrorCorrection.medium,
    this.sizePx = 512,
    this.packageAsZip = false,
  });
}

class QrBatchResult {
  final List<String> outputFiles;
  final String? zipFilePath;
  final int generatedCount;

  const QrBatchResult({
    required this.outputFiles,
    this.zipFilePath,
    required this.generatedCount,
  });
}
