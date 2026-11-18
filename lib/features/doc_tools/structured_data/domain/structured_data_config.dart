import 'dart:typed_data';

import '../../../../core/utils/pdf_font_asset_loader.dart';

/// Formatos soportados en el conversor de datos estructurados.
enum StructuredDataFormat {
  csv('CSV', 'csv'),
  json('JSON', 'json'),
  xml('XML', 'xml'),
  pdfTable('Tabla PDF', 'pdf');

  final String label;
  final String extension;
  const StructuredDataFormat(this.label, this.extension);
}

/// Configuración para conversión de CSV / JSON / XML / Tabla PDF en Isolate.
class StructuredDataConfig {
  final String inputContent;
  final StructuredDataFormat sourceFormat;
  final StructuredDataFormat targetFormat;
  final String outputFilePath;
  final String csvDelimiter;
  final bool prettyPrint;
  final String documentTitle;
  final PdfFontBundle? fontBundle;

  const StructuredDataConfig({
    required this.inputContent,
    required this.sourceFormat,
    required this.targetFormat,
    required this.outputFilePath,
    this.csvDelimiter = ',',
    this.prettyPrint = true,
    this.documentTitle = 'Tabla de Datos — LocalConvert',
    this.fontBundle,
  });
}

/// Resultado generado tras la conversión y validación de datos estructurados.
class StructuredDataConversionResult {
  final String outputFilePath;
  final String previewText;
  final int rowCount;
  final int columnCount;
  final Uint8List outputBytes;

  const StructuredDataConversionResult({
    required this.outputFilePath,
    required this.previewText,
    required this.rowCount,
    required this.columnCount,
    required this.outputBytes,
  });
}
