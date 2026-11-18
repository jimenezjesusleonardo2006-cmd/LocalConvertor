import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/merge_pdf_config.dart';

/// Servicio local (Facade FFI) para unir múltiples documentos PDF conservando texto
/// seleccionable, fuentes y vectores originales mediante el motor nativo en Rust (`lopdf`).
class MergePdfService {
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  MergePdfService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  void cancel() {
    _isCancelled = true;
  }

  Stream<MergePdfProgress> mergeDocuments({
    required List<MergePdfDocumentItem> documents,
    required String outputPdfPath,
    required MergePdfQualityPreset qualityPreset,
  }) async* {
    _isCancelled = false;

    final totalDocs = documents.length;
    final totalPages = documents.fold<int>(
      0,
      (sum, item) => sum + (item.pageCount > 0 ? item.pageCount : 1),
    );

    try {
      final filePaths = <String>[];
      for (int docIdx = 0; docIdx < totalDocs; docIdx++) {
        if (_isCancelled) {
          await _sandboxCleaner.deleteTempFile(outputPdfPath);
          return;
        }

        final doc = documents[docIdx];
        final file = File(doc.filePath);
        if (!await file.exists()) {
          throw FileSystemException(
            'El documento PDF no fue encontrado',
            doc.filePath,
          );
        }
        filePaths.add(doc.filePath);
      }

      yield MergePdfProgress(
        currentDocIndex: 1,
        totalDocs: totalDocs,
        processedPages: 0,
        totalPages: totalPages,
        statusMessage:
            'Uniendo $totalDocs PDFs en motor nativo Rust (preservando texto y vectores)...',
      );

      final mergedPageCount = await Isolate.run(() {
        final data = LocalConvertRustBridge.invokeJsonSync({
          'action': 'merge_pdfs',
          'input_paths': filePaths,
          'output_pdf_path': outputPdfPath,
          'quality_preset': qualityPreset.name,
        });
        return (data['merged_pages'] as num?)?.toInt() ?? 0;
      });

      if (_isCancelled) {
        await _sandboxCleaner.deleteTempFile(outputPdfPath);
        return;
      }

      yield MergePdfProgress(
        currentDocIndex: totalDocs,
        totalDocs: totalDocs,
        processedPages: mergedPageCount,
        totalPages: mergedPageCount,
        statusMessage:
            'PDF unido con éxito en Rust conservando vectores ($mergedPageCount páginas).',
        isCompleted: true,
        outputPdfPath: outputPdfPath,
      );
    } catch (e) {
      await _sandboxCleaner.deleteTempFile(outputPdfPath);
      yield MergePdfProgress(
        currentDocIndex: 0,
        totalDocs: totalDocs,
        processedPages: 0,
        totalPages: totalPages,
        statusMessage: 'Error durante la unión de PDFs.',
        errorMessage: e.toString(),
      );
    }
  }
}
