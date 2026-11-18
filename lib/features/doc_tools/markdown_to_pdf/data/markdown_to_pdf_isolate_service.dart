import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../domain/markdown_to_pdf_config.dart';

/// Servicio Facade FFI ejecutado en un [Isolate] que compila texto plano (`.txt`)
/// o Markdown (`.md`) a PDF multipágina mediante el motor nativo en Rust (`printpdf`)
/// usando las fuentes TTF Roboto locales con soporte Unicode completo.
class MarkdownToPdfIsolateService {
  Future<String> compileToPdfInIsolate(MarkdownToPdfConfig config) async {
    return await Isolate.run(() => _compileEntryPoint(config));
  }

  static Future<String> _compileEntryPoint(MarkdownToPdfConfig config) async {
    Directory? materializedFontDir;

    try {
      final resolvedFonts = _resolveFontPathsOnDisk(
        bundleFallback: config.fontBundle ?? PdfFontAssetLoader.loadFromDiskSync(),
        onTempDirCreated: (dir) => materializedFontDir = dir,
      );

      LocalConvertRustBridge.invokeJsonSync({
        'action': 'markdown_to_pdf',
        'raw_content': config.rawContent,
        'document_title': config.documentTitle,
        'is_markdown': config.isMarkdown,
        'output_pdf_path': config.outputPdfPath,
        'page_size': config.pageSize.name,
        'margin_points': config.margin.points,
        'font_scale': config.fontScale.scale,
        'show_page_numbers': config.showPageNumbers,
        'regular_font_path': resolvedFonts.regular,
        'bold_font_path': resolvedFonts.bold,
        'italic_font_path': resolvedFonts.italic,
        'mono_font_path': resolvedFonts.monoRegular,
      });

      return config.outputPdfPath;
    } finally {
      if (materializedFontDir != null) {
        try {
          if (materializedFontDir!.existsSync()) {
            materializedFontDir!.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  static _ResolvedFontPaths _resolveFontPathsOnDisk({
    required PdfFontBundle? bundleFallback,
    required void Function(Directory tempDir) onTempDirCreated,
  }) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidateDirs = <String>[
      p.join(Directory.current.path, 'assets', 'fonts'),
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'fonts'),
    ];

    for (final dir in candidateDirs) {
      final reg = p.join(dir, 'Roboto-Regular.ttf');
      if (File(reg).existsSync()) {
        final bold = p.join(dir, 'Roboto-Bold.ttf');
        final italic = p.join(dir, 'Roboto-Italic.ttf');
        final mono = p.join(dir, 'RobotoMono-Regular.ttf');
        return _ResolvedFontPaths(
          regular: reg,
          bold: File(bold).existsSync() ? bold : reg,
          italic: File(italic).existsSync() ? italic : reg,
          monoRegular: File(mono).existsSync() ? mono : reg,
        );
      }
    }

    if (bundleFallback != null) {
      final tmpDir = Directory.systemTemp.createTempSync('lc_rust_fonts_');
      onTempDirCreated(tmpDir);
      final regPath = p.join(tmpDir.path, 'Roboto-Regular.ttf');
      final boldPath = p.join(tmpDir.path, 'Roboto-Bold.ttf');
      final italicPath = p.join(tmpDir.path, 'Roboto-Italic.ttf');
      final monoPath = p.join(tmpDir.path, 'RobotoMono-Regular.ttf');

      File(regPath).writeAsBytesSync(bundleFallback.regular, flush: true);
      File(boldPath).writeAsBytesSync(bundleFallback.bold, flush: true);
      File(italicPath).writeAsBytesSync(bundleFallback.italic, flush: true);
      File(monoPath).writeAsBytesSync(bundleFallback.monoRegular, flush: true);

      return _ResolvedFontPaths(
        regular: regPath,
        bold: boldPath,
        italic: italicPath,
        monoRegular: monoPath,
      );
    }

    throw StateError(
      'No se encontraron las fuentes TTF locales en assets/fonts/ ni en flutter_assets.',
    );
  }
}

class _ResolvedFontPaths {
  final String regular;
  final String bold;
  final String italic;
  final String monoRegular;

  const _ResolvedFontPaths({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.monoRegular,
  });
}
