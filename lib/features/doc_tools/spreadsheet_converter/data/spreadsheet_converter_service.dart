import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../domain/spreadsheet_converter_config.dart';

/// Servicio FFI en Rust (`calamine` + `printpdf`) para leer `.xlsx`, `.xls` y `.ods`
/// sin requerir Microsoft Office y exportarlos a CSV, JSON o PDF tabular.
class SpreadsheetConverterService {
  Future<SpreadsheetInspectionResult> inspectWorkbook(
    String filePath, {
    String? sheetName,
  }) async {
    return await Isolate.run(() {
      final data = LocalConvertRustBridge.invokeJsonSync({
        'action': 'inspect_spreadsheet',
        'file_path': filePath,
        'sheet_name': sheetName,
      });

      final sheets = ((data['sheet_names'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();
      final headers = ((data['headers'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();
      final preview = ((data['preview_rows'] as List<dynamic>?) ?? [])
          .map(
            (row) => ((row as List<dynamic>?) ?? [])
                .map((cell) => cell.toString())
                .toList(),
          )
          .toList();

      return SpreadsheetInspectionResult(
        sheetNames: sheets,
        activeSheet: data['active_sheet']?.toString() ?? '',
        rowCount: (data['row_count'] as num?)?.toInt() ?? 0,
        colCount: (data['col_count'] as num?)?.toInt() ?? 0,
        headers: headers,
        previewRows: preview,
      );
    });
  }

  Future<SpreadsheetConvertResult> convertWorkbook(
    SpreadsheetConvertConfig config, {
    PdfFontBundle? fontBundle,
  }) async {
    return await Isolate.run(() {
      Directory? tmpFontDir;
      try {
        final fonts = _resolveRegularAndBoldFonts(
          bundleFallback: fontBundle ?? PdfFontAssetLoader.loadFromDiskSync(),
          onTempDirCreated: (d) => tmpFontDir = d,
        );

        final data = LocalConvertRustBridge.invokeJsonSync({
          'action': 'convert_spreadsheet',
          'file_path': config.sourceFilePath,
          'sheet_name': config.sheetName,
          'output_format': config.targetFormat.extension,
          'output_path': config.outputFilePath,
          'csv_delimiter': config.csvDelimiter,
          'page_size': config.pageSize.name,
          'orientation': config.orientation.name,
          'regular_font_path': fonts.$1,
          'bold_font_path': fonts.$2,
        });

        return SpreadsheetConvertResult(
          outputFilePath: data['output_path']?.toString() ?? config.outputFilePath,
          sheetName: data['sheet_name']?.toString() ?? (config.sheetName ?? ''),
          rowCount: (data['row_count'] as num?)?.toInt() ?? 0,
          colCount: (data['col_count'] as num?)?.toInt() ?? 0,
          outputBytes: (data['output_bytes'] as num?)?.toInt() ?? 0,
        );
      } finally {
        if (tmpFontDir != null) {
          try {
            if (tmpFontDir!.existsSync()) {
              tmpFontDir!.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
    });
  }

  static (String, String) _resolveRegularAndBoldFonts({
    required PdfFontBundle? bundleFallback,
    required void Function(Directory tempDir) onTempDirCreated,
  }) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    for (final dir in [
      p.join(Directory.current.path, 'assets', 'fonts'),
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'fonts'),
    ]) {
      final reg = p.join(dir, 'Roboto-Regular.ttf');
      if (File(reg).existsSync()) {
        final bold = p.join(dir, 'Roboto-Bold.ttf');
        return (reg, File(bold).existsSync() ? bold : reg);
      }
    }

    if (bundleFallback != null) {
      final tmp = Directory.systemTemp.createTempSync('lc_sheet_fonts_');
      onTempDirCreated(tmp);
      final regPath = p.join(tmp.path, 'Roboto-Regular.ttf');
      final boldPath = p.join(tmp.path, 'Roboto-Bold.ttf');
      File(regPath).writeAsBytesSync(bundleFallback.regular, flush: true);
      File(boldPath).writeAsBytesSync(bundleFallback.bold, flush: true);
      return (regPath, boldPath);
    }

    return ('', '');
  }
}
