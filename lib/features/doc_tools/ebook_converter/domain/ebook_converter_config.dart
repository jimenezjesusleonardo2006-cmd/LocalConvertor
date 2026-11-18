import '../../../../core/utils/pdf_font_asset_loader.dart';

/// Formatos de salida soportados para documentos HTML / EPUB.
enum EbookTargetFormat {
  pdf('Documento PDF Paginado', 'pdf'),
  txt('Texto Plano Limpio (.TXT)', 'txt');

  final String label;
  final String extension;
  const EbookTargetFormat(this.label, this.extension);
}

enum EbookBlockType {
  title,
  heading1,
  heading2,
  heading3,
  paragraph,
  listItem,
  quote,
  code,
}

class EbookContentBlock {
  final EbookBlockType type;
  final String text;

  const EbookContentBlock({
    required this.type,
    required this.text,
  });
}

/// Configuración para convertir archivos `.html`, `.htm` o `.epub` en Isolate.
class EbookConverterConfig {
  final String? sourceFilePath;
  final String? rawHtmlOverride;
  final EbookTargetFormat targetFormat;
  final String outputFilePath;
  final double fontScale;
  final bool includePageNumbers;
  final PdfFontBundle? fontBundle;

  const EbookConverterConfig({
    this.sourceFilePath,
    this.rawHtmlOverride,
    this.targetFormat = EbookTargetFormat.pdf,
    required this.outputFilePath,
    this.fontScale = 1.0,
    this.includePageNumbers = true,
    this.fontBundle,
  });
}

class EbookConversionResult {
  final String outputFilePath;
  final String extractedTitle;
  final int chapterCount;
  final int characterCount;
  final String previewText;

  const EbookConversionResult({
    required this.outputFilePath,
    required this.extractedTitle,
    required this.chapterCount,
    required this.characterCount,
    required this.previewText,
  });
}
