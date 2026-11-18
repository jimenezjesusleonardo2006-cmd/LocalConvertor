import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../../../../core/utils/pdf_vector_helpers.dart';
import '../domain/compress_pdf_config.dart';

/// Servicio local 100% offline para optimizar el peso de documentos PDF
/// mediante compresión de flujos vectoriales o remuestreo con límites de memoria.
class CompressPdfService {
  final SandboxCleanerService _sandboxCleaner;

  CompressPdfService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  Future<CompressPdfResult> compressPdf(CompressPdfConfig config) async {
    try {
      final sourceFile = File(config.sourcePdfPath);
      if (!await sourceFile.exists()) {
        throw FileSystemException(
          'El archivo PDF de origen no existe',
          config.sourcePdfPath,
        );
      }

      final sourceBytes = await sourceFile.readAsBytes();
      final originalSize = sourceBytes.length;

      // 1. Optimización vectorial en Isolate (siempre disponible offline y en VM tests)
      final vectorResult = await Isolate.run(
        () => _optimizeVectorBytesInIsolate(sourceBytes),
      );
      Uint8List bestBytes = vectorResult.bytes;
      final pageCount = vectorResult.pageCount;

      // 2. Remuestreo controlado para niveles con pérdida cuando PDFium nativo está activo
      final hasNativeRaster =
          config.level != CompressPdfLevel.losslessVector &&
          WidgetsBinding.instance is WidgetsFlutterBinding;

      if (hasNativeRaster) {
        try {
          final targetDoc = sfpdf.PdfDocument();
          targetDoc.compressionLevel = sfpdf.PdfCompressionLevel.best;
          final dpi = config.level.dpi.toDouble();
          final quality = config.level.jpegQuality;
          final maxDim = config.maxDimensionPx;

          try {
            await for (final PdfRaster raster
                in Printing.raster(sourceBytes, dpi: dpi)) {
              final w = raster.width;
              final h = raster.height;
              final rgba = raster.pixels;

              final encoded = await Isolate.run(
                () => _downsampleAndEncodeJpegInIsolate(
                  width: w,
                  height: h,
                  rgbaPixels: rgba,
                  maxDimensionPx: maxDim,
                  quality: quality,
                ),
              );

              final pageWidthPts = (w * pw_pdf.PdfPageFormat.inch) / dpi;
              final pageHeightPts = (h * pw_pdf.PdfPageFormat.inch) / dpi;

              final section = targetDoc.sections!.add();
              section.pageSettings.size = Size(pageWidthPts, pageHeightPts);
              section.pageSettings.margins.all = 0;
              section.pageSettings.orientation = pageWidthPts > pageHeightPts
                  ? sfpdf.PdfPageOrientation.landscape
                  : sfpdf.PdfPageOrientation.portrait;
              final page = section.pages.add();
              final bitmap = sfpdf.PdfBitmap(encoded);
              page.graphics.drawImage(
                bitmap,
                Rect.fromLTWH(0, 0, pageWidthPts, pageHeightPts),
              );
            }

            final rasterBytes = Uint8List.fromList(await targetDoc.save());
            if (rasterBytes.isNotEmpty &&
                rasterBytes.length < bestBytes.length) {
              bestBytes = rasterBytes;
            }
          } finally {
            targetDoc.dispose();
          }
        } catch (_) {
          // Si falla la rasterización nativa se conserva la optimización vectorial
        }
      }

      final outFile = File(config.outputPdfPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(bestBytes, flush: true);

      return CompressPdfResult(
        outputPdfPath: config.outputPdfPath,
        originalBytes: originalSize,
        compressedBytes: bestBytes.length,
        pageCount: pageCount,
      );
    } catch (_) {
      await _sandboxCleaner.deleteTempFile(config.outputPdfPath);
      rethrow;
    }
  }

  static Future<({Uint8List bytes, int pageCount})>
      _optimizeVectorBytesInIsolate(Uint8List sourceBytes) async {
    final sourceDoc = sfpdf.PdfDocument(inputBytes: sourceBytes);
    final targetDoc = sfpdf.PdfDocument();
    targetDoc.compressionLevel = sfpdf.PdfCompressionLevel.best;

    try {
      final count = sourceDoc.pages.count;
      for (int i = 0; i < count; i++) {
        PdfVectorHelpers.appendVectorPage(targetDoc, sourceDoc.pages[i]);
      }
      final optimized = Uint8List.fromList(await targetDoc.save());
      return (
        bytes: optimized.length <= sourceBytes.length ? optimized : sourceBytes,
        pageCount: count,
      );
    } finally {
      sourceDoc.dispose();
      targetDoc.dispose();
    }
  }

  static Uint8List _downsampleAndEncodeJpegInIsolate({
    required int width,
    required int height,
    required Uint8List rgbaPixels,
    required int maxDimensionPx,
    required int quality,
  }) {
    img.Image decoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbaPixels.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );

    if (decoded.width > maxDimensionPx || decoded.height > maxDimensionPx) {
      decoded = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDimensionPx)
          : img.copyResize(decoded, height: maxDimensionPx);
    }

    final whiteBg = img.Image(width: decoded.width, height: decoded.height);
    img.fill(whiteBg, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(whiteBg, decoded);

    return Uint8List.fromList(
      img.encodeJpg(whiteBg, quality: quality.clamp(30, 98)),
    );
  }
}
