import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/pdf_to_images_config.dart';

/// Servicio híbrido PDFium + Rust para extraer páginas de un PDF a PNG/JPG y ZIP.
///
/// Utiliza `Printing.raster` (`pdfium.dll`) para rasterizar cada página a RGBA crudo
/// y delega a [LocalConvertRustBridge] en un [Isolate] la codificación rápida PNG/JPG
/// y el empaquetado `.ZIP` en Rust sin bloquear el hilo de interfaz.
class PdfToImagesService {
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  PdfToImagesService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  void cancel() {
    _isCancelled = true;
  }

  Stream<PdfToImagesProgress> extractPdfToImages(
    PdfToImagesConfig config, {
    int? knownTotalPages,
  }) async* {
    _isCancelled = false;

    try {
      final pdfFile = File(config.sourcePdfPath);
      if (!await pdfFile.exists()) {
        yield const PdfToImagesProgress(
          processedPages: 0,
          statusMessage: 'El archivo PDF seleccionado no existe.',
          errorMessage: 'El archivo PDF seleccionado no existe.',
        );
        return;
      }

      yield PdfToImagesProgress(
        processedPages: 0,
        totalPages: knownTotalPages,
        statusMessage: 'Leyendo documento PDF en memoria local...',
      );

      final pdfBytes = await pdfFile.readAsBytes();
      final baseName = p.basenameWithoutExtension(config.sourcePdfPath);
      final extractedPaths = <String>[];
      int pageIndex = 0;

      await for (final PdfRaster page
          in Printing.raster(pdfBytes, dpi: config.dpiOption.dpi)) {
        if (_isCancelled) {
          await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
          return;
        }

        pageIndex++;
        yield PdfToImagesProgress(
          processedPages: pageIndex,
          totalPages: knownTotalPages,
          statusMessage:
              'Rasterizando (PDFium) y codificando en Rust página $pageIndex${knownTotalPages != null ? " de $knownTotalPages" : ""}...',
        );

        final payload = RawRasterPagePayload(
          pageNumber: pageIndex,
          width: page.width,
          height: page.height,
          rgbaPixels: page.pixels,
          format: config.outputFormat,
          jpgQuality: config.jpgQuality,
        );
        final Uint8List encodedBytes = await Isolate.run(
          () => _encodeRgbaInRustIsolate(payload),
        );

        final paddedNum = pageIndex.toString().padLeft(3, '0');
        final fileName =
            '${baseName}_pagina_$paddedNum.${config.outputFormat.extension}';
        final filePath = p.join(config.sessionDirPath, fileName);

        final outFile = File(filePath);
        await outFile.writeAsBytes(encodedBytes, flush: true);
        extractedPaths.add(filePath);
      }

      if (_isCancelled) return;

      String? zipOutputPath;
      final needsZip =
          config.packagingMode == PdfImagePackagingMode.zipArchive ||
              Platform.isAndroid ||
              Platform.isIOS;

      if (needsZip) {
        yield PdfToImagesProgress(
          processedPages: pageIndex,
          totalPages: pageIndex,
          statusMessage:
              'Empaquetando $pageIndex imágenes en archivo .ZIP con motor Rust...',
        );

        final candidateZipPath =
            p.join(config.sessionDirPath, '${baseName}_imagenes.zip');

        await Isolate.run(
          () => LocalConvertRustBridge.invokeJsonSync({
            'action': 'create_zip',
            'input_paths': extractedPaths,
            'output_zip_path': candidateZipPath,
          }),
        );
        zipOutputPath = candidateZipPath;
      }

      yield PdfToImagesProgress(
        processedPages: pageIndex,
        totalPages: pageIndex,
        statusMessage: 'Extracción PDFium + Rust completada ($pageIndex páginas).',
        isCompleted: true,
        zipFilePath: zipOutputPath,
        extractedImagePaths: extractedPaths,
      );
    } catch (e) {
      yield PdfToImagesProgress(
        processedPages: 0,
        statusMessage: 'Error al extraer imágenes del PDF.',
        errorMessage: e.toString(),
      );
    }
  }

  /// Codifica un buffer RGBA proveniente de PDFium usando `rust_encode_rgba_buffer`.
  static Uint8List _encodeRgbaInRustIsolate(RawRasterPagePayload payload) {
    return LocalConvertRustBridge.encodeRgbaBufferSync(
      rgbaBytes: payload.rgbaPixels,
      width: payload.width,
      height: payload.height,
      format: payload.format.extension,
      quality: payload.jpgQuality,
    );
  }
}
