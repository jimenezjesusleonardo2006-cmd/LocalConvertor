import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/watermark_pdf_config.dart';

/// Servicio local 100% offline para estampar marcas de agua Unicode o de imagen
/// sobre todas las páginas de un documento PDF dentro de un [Isolate].
class WatermarkPdfService {
  final SandboxCleanerService _sandboxCleaner;

  WatermarkPdfService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  Future<String> applyWatermark(WatermarkPdfConfig config) async {
    try {
      final sourceFile = File(config.sourcePdfPath);
      if (!await sourceFile.exists()) {
        throw FileSystemException(
          'El archivo PDF de origen no existe',
          config.sourcePdfPath,
        );
      }

      if (config.type == WatermarkType.text && config.text.trim().isEmpty) {
        throw const FormatException(
          'Ingresa el texto que deseas estampar como marca de agua.',
        );
      }

      if (config.type == WatermarkType.image &&
          (config.watermarkImagePath == null ||
              !await File(config.watermarkImagePath!).exists())) {
        throw const FormatException(
          'Selecciona una imagen PNG o JPG válida para la marca de agua.',
        );
      }

      await Isolate.run(() => _runInIsolate(config));
      return config.outputPdfPath;
    } catch (_) {
      await _sandboxCleaner.deleteTempFile(config.outputPdfPath);
      rethrow;
    }
  }

  static Future<void> _runInIsolate(WatermarkPdfConfig config) async {
    final pdfBytes = await File(config.sourcePdfPath).readAsBytes();
    final doc = sfpdf.PdfDocument(inputBytes: pdfBytes);

    sfpdf.PdfFont? textFont;
    sfpdf.PdfBrush? textBrush;
    sfpdf.PdfBitmap? watermarkBitmap;

    try {
      if (config.type == WatermarkType.text) {
        textFont = config.fontBundle != null
            ? sfpdf.PdfTrueTypeFont(
                config.fontBundle!.bold,
                config.fontSize,
              )
            : sfpdf.PdfStandardFont(
                sfpdf.PdfFontFamily.helvetica,
                config.fontSize,
                style: sfpdf.PdfFontStyle.bold,
              );
        final r = (config.colorHex >> 16) & 0xFF;
        final g = (config.colorHex >> 8) & 0xFF;
        final b = config.colorHex & 0xFF;
        textBrush = sfpdf.PdfSolidBrush(sfpdf.PdfColor(r, g, b));
      } else {
        final imgBytes = await File(config.watermarkImagePath!).readAsBytes();
        watermarkBitmap = sfpdf.PdfBitmap(imgBytes);
      }

      final clampedOpacity = config.opacity.clamp(0.05, 1.0);
      final scale = config.scale.clamp(0.15, 2.0);

      for (int i = 0; i < doc.pages.count; i++) {
        final page = doc.pages[i];
        final pageSize = page.getClientSize();
        final graphics = page.graphics;
        final anchors = _resolveAnchors(config.position, pageSize);

        for (final anchor in anchors) {
          graphics.save();
          graphics.setTransparency(clampedOpacity);
          graphics.translateTransform(anchor.dx, anchor.dy);
          graphics.rotateTransform(config.rotationDegrees);

          if (config.type == WatermarkType.text &&
              textFont != null &&
              textBrush != null) {
            final measured = textFont.measureString(config.text);
            final scaledW = math.max(20.0, measured.width * scale / 0.5);
            final scaledH = math.max(20.0, measured.height * scale / 0.5);
            final format = sfpdf.PdfStringFormat(
              alignment: sfpdf.PdfTextAlignment.center,
              lineAlignment: sfpdf.PdfVerticalAlignment.middle,
            );
            graphics.drawString(
              config.text,
              textFont,
              brush: textBrush,
              bounds: Rect.fromCenter(
                center: Offset.zero,
                width: scaledW + 24,
                height: scaledH + 16,
              ),
              format: format,
            );
          } else if (watermarkBitmap != null) {
            final targetWidth = pageSize.width * 0.45 * scale;
            final aspect = watermarkBitmap.height /
                math.max(1, watermarkBitmap.width);
            final targetHeight = targetWidth * aspect;
            graphics.drawImage(
              watermarkBitmap,
              Rect.fromCenter(
                center: Offset.zero,
                width: targetWidth,
                height: targetHeight,
              ),
            );
          }

          graphics.restore();
        }
      }

      final outBytes = await doc.save();
      final outFile = File(config.outputPdfPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(outBytes, flush: true);
    } finally {
      doc.dispose();
    }
  }

  static List<Offset> _resolveAnchors(
    WatermarkPosition position,
    Size pageSize,
  ) {
    final w = pageSize.width;
    final h = pageSize.height;
    switch (position) {
      case WatermarkPosition.center:
        return [Offset(w / 2, h / 2)];
      case WatermarkPosition.topLeft:
        return [Offset(w * 0.25, h * 0.20)];
      case WatermarkPosition.topRight:
        return [Offset(w * 0.75, h * 0.20)];
      case WatermarkPosition.bottomLeft:
        return [Offset(w * 0.25, h * 0.80)];
      case WatermarkPosition.bottomRight:
        return [Offset(w * 0.75, h * 0.80)];
      case WatermarkPosition.tiled:
        return [
          for (final ry in [0.22, 0.50, 0.78])
            for (final rx in [0.25, 0.75])
              Offset(w * rx, h * ry),
        ];
    }
  }
}
