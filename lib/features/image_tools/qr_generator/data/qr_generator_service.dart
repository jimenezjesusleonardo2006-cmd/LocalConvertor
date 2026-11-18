import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../domain/qr_generator_config.dart';

/// Servicio FFI en Rust (`qrcode` + `image` + `rayon` + `printpdf`) para generación
/// individual o por lotes de códigos QR en PNG, SVG vectorial o lámina PDF imprimible.
class QrGeneratorService {
  Future<QrPreviewResult> generatePreview({
    required String content,
    required QrErrorCorrection errorCorrection,
    required String outputPath,
    int sizePx = 384,
  }) async {
    return await Isolate.run(() {
      final data = LocalConvertRustBridge.invokeJsonSync({
        'action': 'generate_qr_preview',
        'content': content,
        'ec_level': errorCorrection.code,
        'size_px': sizePx,
        'output_path': outputPath,
      });

      return QrPreviewResult(
        previewPath: data['preview_path']?.toString() ?? outputPath,
        moduleCount: (data['module_count'] as num?)?.toInt() ?? 0,
        widthPx: (data['width_px'] as num?)?.toInt() ?? sizePx,
      );
    });
  }

  Future<QrBatchResult> generateBatch(
    QrBatchConfig config, {
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
          'action': 'generate_qr_batch',
          'items': config.items,
          'session_dir_path': config.sessionDirPath,
          'output_format': config.outputFormat.extension,
          'ec_level': config.errorCorrection.code,
          'size_px': config.sizePx,
          'package_as_zip': config.packageAsZip,
          'regular_font_path': fonts.$1,
          'bold_font_path': fonts.$2,
        });

        final outputFiles = ((data['output_files'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList();

        return QrBatchResult(
          outputFiles: outputFiles,
          zipFilePath: data['zip_file_path']?.toString(),
          generatedCount:
              (data['generated_count'] as num?)?.toInt() ?? outputFiles.length,
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
      final tmp = Directory.systemTemp.createTempSync('lc_qr_fonts_');
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
