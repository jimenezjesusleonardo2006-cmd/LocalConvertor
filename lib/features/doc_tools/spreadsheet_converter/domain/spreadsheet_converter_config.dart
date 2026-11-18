import '../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';

enum SpreadsheetOutputFormat {
  csv('CSV', 'csv', 'Texto tabular universal'),
  json('JSON', 'json', 'Objetos estructurados por fila'),
  pdf('PDF', 'pdf', 'Documento tabular paginado listo para imprimir');

  final String label;
  final String extension;
  final String description;
  const SpreadsheetOutputFormat(this.label, this.extension, this.description);
}

class SpreadsheetInspectionResult {
  final List<String> sheetNames;
  final String activeSheet;
  final int rowCount;
  final int colCount;
  final List<String> headers;
  final List<List<String>> previewRows;

  const SpreadsheetInspectionResult({
    required this.sheetNames,
    required this.activeSheet,
    required this.rowCount,
    required this.colCount,
    required this.headers,
    required this.previewRows,
  });
}

class SpreadsheetConvertConfig {
  final String sourceFilePath;
  final String? sheetName;
  final SpreadsheetOutputFormat targetFormat;
  final String outputFilePath;
  final String csvDelimiter;
  final PdfPageSizeOption pageSize;
  final PdfPageOrientationOption orientation;

  const SpreadsheetConvertConfig({
    required this.sourceFilePath,
    this.sheetName,
    required this.targetFormat,
    required this.outputFilePath,
    this.csvDelimiter = ',',
    this.pageSize = PdfPageSizeOption.a4,
    this.orientation = PdfPageOrientationOption.landscape,
  });
}

class SpreadsheetConvertResult {
  final String outputFilePath;
  final String sheetName;
  final int rowCount;
  final int colCount;
  final int outputBytes;

  const SpreadsheetConvertResult({
    required this.outputFilePath,
    required this.sheetName,
    required this.rowCount,
    required this.colCount,
    required this.outputBytes,
  });
}
