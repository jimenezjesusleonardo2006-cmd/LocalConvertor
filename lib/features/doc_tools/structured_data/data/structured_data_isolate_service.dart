import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../domain/structured_data_config.dart';

/// Servicio local en [Isolate] para validar y convertir datos estructurados
/// entre CSV, JSON, XML y tablas PDF paginadas con fuentes Unicode locales.
class StructuredDataIsolateService {
  /// Valida la sintaxis del contenido de entrada según [format].
  /// Retorna `null` si es válido o un mensaje descriptivo de error.
  static String? validateSyntax(String content, StructuredDataFormat format) {
    if (content.trim().isEmpty) {
      return 'El contenido está vacío.';
    }
    try {
      parseToNormalizedRows(content, format);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('FormatException: ', '');
    }
  }

  /// Normaliza una entrada CSV, JSON o XML a encabezados + filas clave/valor.
  static ({List<String> headers, List<Map<String, String>> rows})
      parseToNormalizedRows(
    String content,
    StructuredDataFormat sourceFormat, {
    String csvDelimiter = ',',
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('No hay datos para analizar.');
    }

    switch (sourceFormat) {
      case StructuredDataFormat.csv:
        final codec = Csv(
          fieldDelimiter: csvDelimiter.isEmpty ? ',' : csvDelimiter,
          autoDetect: csvDelimiter.isEmpty,
          skipEmptyLines: true,
        );
        final matrix = codec.decode(trimmed);
        if (matrix.isEmpty) {
          throw const FormatException('El CSV no contiene filas válidas.');
        }

        final firstRow = matrix.first.map((c) => '${c ?? ''}').toList();
        final headers = [
          for (int i = 0; i < firstRow.length; i++)
            firstRow[i].trim().isEmpty ? 'col_${i + 1}' : firstRow[i].trim(),
        ];

        final rows = <Map<String, String>>[];
        for (int r = 1; r < matrix.length; r++) {
          final rowList = matrix[r];
          final map = <String, String>{};
          for (int c = 0; c < headers.length; c++) {
            map[headers[c]] = c < rowList.length ? '${rowList[c] ?? ''}' : '';
          }
          rows.add(map);
        }
        return (headers: headers, rows: rows);

      case StructuredDataFormat.json:
        final decoded = jsonDecode(trimmed);
        List<dynamic> list;
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map<String, dynamic>) {
          final firstListEntry = decoded.values.whereType<List>().firstOrNull;
          list = firstListEntry ?? [decoded];
        } else {
          throw const FormatException(
            'El JSON debe ser un arreglo de objetos o un objeto raíz.',
          );
        }

        final headersSet = <String>{};
        final rows = <Map<String, String>>[];

        for (final item in list) {
          if (item is Map) {
            final map = <String, String>{};
            item.forEach((k, v) {
              final key = '$k';
              headersSet.add(key);
              map[key] = v == null ? '' : (v is Map || v is List ? jsonEncode(v) : '$v');
            });
            rows.add(map);
          } else if (item is List) {
            final map = <String, String>{};
            for (int i = 0; i < item.length; i++) {
              final key = 'col_${i + 1}';
              headersSet.add(key);
              map[key] = '${item[i] ?? ''}';
            }
            rows.add(map);
          } else {
            headersSet.add('value');
            rows.add({'value': '$item'});
          }
        }

        return (headers: headersSet.toList(), rows: rows);

      case StructuredDataFormat.xml:
        final doc = XmlDocument.parse(trimmed);
        final root = doc.rootElement;
        var itemElements = root.childElements.toList();
        if (itemElements.isEmpty) {
          itemElements = [root];
        }

        final headersSet = <String>{};
        final rows = <Map<String, String>>[];

        for (final elem in itemElements) {
          final map = <String, String>{};
          for (final attr in elem.attributes) {
            final key = '@${attr.name.local}';
            headersSet.add(key);
            map[key] = attr.value;
          }
          if (elem.childElements.isEmpty) {
            if (elem.innerText.trim().isNotEmpty || map.isEmpty) {
              headersSet.add(elem.name.local);
              map[elem.name.local] = elem.innerText.trim();
            }
          } else {
            for (final child in elem.childElements) {
              final key = child.name.local;
              headersSet.add(key);
              map[key] = child.innerText.trim();
            }
          }
          rows.add(map);
        }

        return (headers: headersSet.toList(), rows: rows);

      case StructuredDataFormat.pdfTable:
        throw const FormatException(
          'Tabla PDF es únicamente un formato de exportación.',
        );
    }
  }

  /// Ejecuta la conversión completa dentro de un [Isolate] dedicado.
  Future<StructuredDataConversionResult> convertInIsolate(
    StructuredDataConfig config,
  ) {
    return Isolate.run(() => _convertEntryPoint(config));
  }

  static Future<StructuredDataConversionResult> _convertEntryPoint(
    StructuredDataConfig config,
  ) async {
    final parsed = parseToNormalizedRows(
      config.inputContent,
      config.sourceFormat,
      csvDelimiter: config.csvDelimiter,
    );

    final headers = parsed.headers;
    final rows = parsed.rows;
    late final Uint8List outBytes;
    late final String previewText;

    switch (config.targetFormat) {
      case StructuredDataFormat.csv:
        final matrix = <List<dynamic>>[
          headers,
          for (final row in rows)
            [for (final h in headers) row[h] ?? ''],
        ];
        final encodedCsv = Csv(
          fieldDelimiter: config.csvDelimiter.isEmpty ? ',' : config.csvDelimiter,
          lineDelimiter: '\n',
        ).encode(matrix);
        previewText = encodedCsv;
        outBytes = Uint8List.fromList(utf8.encode(encodedCsv));

      case StructuredDataFormat.json:
        final orderedRecords = [
          for (final row in rows)
            {for (final h in headers) h: row[h] ?? ''},
        ];
        final encodedJson = config.prettyPrint
            ? const JsonEncoder.withIndent('  ').convert(orderedRecords)
            : jsonEncode(orderedRecords);
        previewText = encodedJson;
        outBytes = Uint8List.fromList(utf8.encode(encodedJson));

      case StructuredDataFormat.xml:
        final builder = XmlBuilder();
        builder.processing('xml', 'version="1.0" encoding="UTF-8"');
        builder.element('dataset', nest: () {
          for (final row in rows) {
            builder.element('record', nest: () {
              for (final h in headers) {
                final tag = _sanitizeXmlTagName(h);
                builder.element(tag, nest: row[h] ?? '');
              }
            });
          }
        });
        final xmlDoc = builder.buildDocument();
        final encodedXml = xmlDoc.toXmlString(pretty: config.prettyPrint);
        previewText = encodedXml;
        outBytes = Uint8List.fromList(utf8.encode(encodedXml));

      case StructuredDataFormat.pdfTable:
        outBytes = await _buildPdfTable(
          headers: headers,
          rows: rows,
          title: config.documentTitle,
          fontBundle: config.fontBundle,
        );
        previewText =
            'Tabla PDF generada: ${headers.length} columnas × ${rows.length} filas.';
    }

    final outFile = File(config.outputFilePath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(outBytes, flush: true);

    return StructuredDataConversionResult(
      outputFilePath: config.outputFilePath,
      previewText: previewText,
      rowCount: rows.length,
      columnCount: headers.length,
      outputBytes: outBytes,
    );
  }

  static Future<Uint8List> _buildPdfTable({
    required List<String> headers,
    required List<Map<String, String>> rows,
    required String title,
    PdfFontBundle? fontBundle,
  }) async {
    final themeBundle = PdfFontAssetLoader.buildPdfTheme(fontBundle);
    final doc = pw.Document(
      version: PdfVersion.pdf_1_5,
      compress: true,
      title: title,
      producer: 'LocalConvert Structured Data Engine',
      theme: themeBundle.theme,
    );

    final pageFormat = headers.length > 5
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;

    final tableData = <List<String>>[
      for (final row in rows) [for (final h in headers) row[h] ?? ''],
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal800,
                ),
              ),
              pw.Text(
                '${rows.length} registros',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: tableData,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 5,
            ),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static String _sanitizeXmlTagName(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'^@+'), '').replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (cleaned.isEmpty || RegExp(r'^[0-9-]').hasMatch(cleaned)) {
      cleaned = 'col_$cleaned';
    }
    return cleaned;
  }
}
