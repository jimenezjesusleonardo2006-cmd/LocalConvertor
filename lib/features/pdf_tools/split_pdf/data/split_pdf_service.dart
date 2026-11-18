import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/split_pdf_config.dart';

/// Servicio local (Facade FFI) para extraer páginas o rangos específicos (ej. 1-3, 5, 8-10)
/// conservando texto seleccionable, fuentes y vectores originales mediante Rust (`lopdf`).
class SplitPdfService {
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  SplitPdfService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  void cancel() {
    _isCancelled = true;
  }

  Stream<SplitPdfProgress> splitPdf(SplitPdfConfig config) async* {
    _isCancelled = false;
    final totalToExtract = config.uniquePagesToExtract.length;

    try {
      final sourceFile = File(config.sourcePdfPath);
      if (!await sourceFile.exists()) {
        throw FileSystemException(
          'El archivo PDF de origen no existe',
          config.sourcePdfPath,
        );
      }

      final baseName = p.basenameWithoutExtension(config.sourcePdfPath);
      final serializedSegments = <Map<String, dynamic>>[
        for (final segment in config.segments)
          {
            'label': segment.label,
            'pages': segment.pages,
          },
      ];

      if (config.outputMode == SplitOutputMode.singleCombinedPdf) {
        final outputPdfPath = p.join(
          config.sessionDirPath,
          '${baseName}_extraido.pdf',
        );

        yield SplitPdfProgress(
          processedPages: 0,
          totalPagesToExtract: totalToExtract,
          statusMessage:
              'Extrayendo $totalToExtract páginas en Rust preservando texto y vectores...',
        );

        await Isolate.run(() {
          LocalConvertRustBridge.invokeJsonSync({
            'action': 'split_pdf',
            'source_pdf_path': config.sourcePdfPath,
            'output_mode': 'single_combined_pdf',
            'output_path': outputPdfPath,
            'base_name': baseName,
            'segments': serializedSegments,
          });
        });

        if (_isCancelled) {
          await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
          return;
        }

        yield SplitPdfProgress(
          processedPages: totalToExtract,
          totalPagesToExtract: totalToExtract,
          statusMessage:
              'Extracción vectorial en Rust completada ($totalToExtract páginas).',
          isCompleted: true,
          singleOutputPdfPath: outputPdfPath,
        );
      } else {
        final outputZipPath = p.join(
          config.sessionDirPath,
          '${baseName}_rangos_divididos.zip',
        );

        yield SplitPdfProgress(
          processedPages: 0,
          totalPagesToExtract: totalToExtract,
          statusMessage:
              'Generando ${config.segments.length} PDFs vectoriales en paralelo (Rust + Rayon) y empaquetando ZIP...',
        );

        await Isolate.run(() {
          LocalConvertRustBridge.invokeJsonSync({
            'action': 'split_pdf',
            'source_pdf_path': config.sourcePdfPath,
            'output_mode': 'separate_pdfs_per_range_zip',
            'output_path': outputZipPath,
            'base_name': baseName,
            'segments': serializedSegments,
          });
        });

        if (_isCancelled) {
          await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
          return;
        }

        yield SplitPdfProgress(
          processedPages: totalToExtract,
          totalPagesToExtract: totalToExtract,
          statusMessage: 'División vectorial en múltiples PDFs (.ZIP) completada.',
          isCompleted: true,
          zipOutputPath: outputZipPath,
        );
      }
    } catch (e) {
      await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
      yield SplitPdfProgress(
        processedPages: 0,
        totalPagesToExtract: totalToExtract,
        statusMessage: 'Error durante la división del PDF.',
        errorMessage: e.toString(),
      );
    }
  }
}
