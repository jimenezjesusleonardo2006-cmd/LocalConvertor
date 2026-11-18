import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';

/// Escala tipográfica del documento PDF generado desde Texto o Markdown.
enum DocFontScaleOption {
  compact(0.9, 'Compacto (10 pt)'),
  normal(1.0, 'Estándar (11 pt)'),
  comfortable(1.15, 'Lectura amplia (13 pt)');

  final double scale;
  final String label;
  const DocFontScaleOption(this.scale, this.label);
}

/// Configuración inmutable para convertir archivos `.txt` o `.md` a PDF en un [Isolate].
class MarkdownToPdfConfig {
  final String rawContent;
  final String documentTitle;
  final bool isMarkdown;
  final String outputPdfPath;
  final PdfPageSizeOption pageSize;
  final PdfMarginOption margin;
  final DocFontScaleOption fontScale;
  final bool showPageNumbers;
  final PdfFontBundle? fontBundle;

  const MarkdownToPdfConfig({
    required this.rawContent,
    required this.documentTitle,
    required this.isMarkdown,
    required this.outputPdfPath,
    this.pageSize = PdfPageSizeOption.a4,
    this.margin = PdfMarginOption.large,
    this.fontScale = DocFontScaleOption.normal,
    this.showPageNumbers = true,
    this.fontBundle,
  });
}



