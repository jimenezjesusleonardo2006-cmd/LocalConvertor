import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../domain/docx_converter_config.dart';

/// Servicio FFI en Rust para extraer el XML interno de archivos `.docx`
/// (`word/document.xml`) y exportarlos a Markdown, Texto Plano o PDF sin Office.
class DocxConverterService {
  Future<DocxInspectionResult> inspectDocument(String filePath) async {
    return await Isolate.run(() {
      final data = LocalConvertRustBridge.invokeJsonSync({
        'action': 'inspect_docx',
        'file_path': filePath,
      });

      return DocxInspectionResult(
        paragraphCount: (data['paragraph_count'] as num?)?.toInt() ?? 0,
        tableCount: (data['table_count'] as num?)?.toInt() ?? 0,
        previewMarkdown: data['preview_markdown']?.toString() ?? '',
      );
    });
  }

  Future<DocxConvertResult> convertDocument(
    DocxConvertConfig config, {
    PdfFontBundle? fontBundle,
  }) async {
    return await Isolate.run(() {
      Directory? tmpFontDir;
      try {
        final fonts = _resolveFontPaths(
          bundleFallback: fontBundle ?? PdfFontAssetLoader.loadFromDiskSync(),
          onTempDirCreated: (d) => tmpFontDir = d,
        );

        final data = LocalConvertRustBridge.invokeJsonSync({
          'action': 'convert_docx',
          'file_path': config.sourceFilePath,
          'output_format': config.targetFormat.extension,
          'output_path': config.outputFilePath,
          'page_size': config.pageSize.name,
          'margin_points': config.margin.points,
          'font_scale': config.fontScale.scale,
          'show_page_numbers': config.showPageNumbers,
          'regular_font_path': fonts.regular,
          'bold_font_path': fonts.bold,
          'italic_font_path': fonts.italic,
          'mono_font_path': fonts.mono,
        });

        return DocxConvertResult(
          outputFilePath: data['output_path']?.toString() ?? config.outputFilePath,
          paragraphCount: (data['paragraph_count'] as num?)?.toInt() ?? 0,
          tableCount: (data['table_count'] as num?)?.toInt() ?? 0,
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

  static _DocxFontPaths _resolveFontPaths({
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
        final italic = p.join(dir, 'Roboto-Italic.ttf');
        final mono = p.join(dir, 'RobotoMono-Regular.ttf');
        return _DocxFontPaths(
          regular: reg,
          bold: File(bold).existsSync() ? bold : reg,
          italic: File(italic).existsSync() ? italic : reg,
          mono: File(mono).existsSync() ? mono : reg,
        );
      }
    }

    if (bundleFallback != null) {
      final tmp = Directory.systemTemp.createTempSync('lc_docx_fonts_');
      onTempDirCreated(tmp);
      final regPath = p.join(tmp.path, 'Roboto-Regular.ttf');
      final boldPath = p.join(tmp.path, 'Roboto-Bold.ttf');
      final italicPath = p.join(tmp.path, 'Roboto-Italic.ttf');
      final monoPath = p.join(tmp.path, 'RobotoMono-Regular.ttf');
      File(regPath).writeAsBytesSync(bundleFallback.regular, flush: true);
      File(boldPath).writeAsBytesSync(bundleFallback.bold, flush: true);
      File(italicPath).writeAsBytesSync(bundleFallback.italic, flush: true);
      File(monoPath).writeAsBytesSync(bundleFallback.monoRegular, flush: true);
      return _DocxFontPaths(
        regular: regPath,
        bold: boldPath,
        italic: italicPath,
        mono: monoPath,
      );
    }

    return const _DocxFontPaths(regular: '', bold: '', italic: '', mono: '');
  }
}

class _DocxFontPaths {
  final String regular;
  final String bold;
  final String italic;
  final String mono;

  const _DocxFontPaths({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.mono,
  });
}
