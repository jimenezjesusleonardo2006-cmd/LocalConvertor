import '../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import '../../markdown_to_pdf/domain/markdown_to_pdf_config.dart';

enum DocxOutputFormat {
  pdf('PDF', 'pdf', 'Documento paginado Unicode'),
  markdown('Markdown', 'md', 'Encabezados, listas y tablas'),
  txt('TXT', 'txt', 'Texto limpio sin etiquetas');

  final String label;
  final String extension;
  final String description;
  const DocxOutputFormat(this.label, this.extension, this.description);
}

class DocxInspectionResult {
  final int paragraphCount;
  final int tableCount;
  final String previewMarkdown;

  const DocxInspectionResult({
    required this.paragraphCount,
    required this.tableCount,
    required this.previewMarkdown,
  });
}

class DocxConvertConfig {
  final String sourceFilePath;
  final DocxOutputFormat targetFormat;
  final String outputFilePath;
  final PdfPageSizeOption pageSize;
  final PdfMarginOption margin;
  final DocFontScaleOption fontScale;
  final bool showPageNumbers;

  const DocxConvertConfig({
    required this.sourceFilePath,
    required this.targetFormat,
    required this.outputFilePath,
    this.pageSize = PdfPageSizeOption.a4,
    this.margin = PdfMarginOption.large,
    this.fontScale = DocFontScaleOption.normal,
    this.showPageNumbers = true,
  });
}

class DocxConvertResult {
  final String outputFilePath;
  final int paragraphCount;
  final int tableCount;
  final int outputBytes;

  const DocxConvertResult({
    required this.outputFilePath,
    required this.paragraphCount,
    required this.tableCount,
    required this.outputBytes,
  });
}
