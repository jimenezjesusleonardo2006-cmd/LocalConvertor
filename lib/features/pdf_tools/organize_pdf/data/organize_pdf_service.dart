import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../../../../core/utils/pdf_vector_helpers.dart';
import '../domain/organize_pdf_config.dart';

/// Servicio local para rotar, reordenar y eliminar páginas PDF en un [Isolate]
/// conservando texto seleccionable y gráficos vectoriales originales.
class OrganizePdfService {
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  OrganizePdfService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  void cancel() {
    _isCancelled = true;
  }

  Stream<OrganizePdfProgress> organizePdf(OrganizePdfConfig config) async* {
    _isCancelled = false;
    final total = config.pages.length;

    try {
      if (total == 0) {
        throw const FormatException('Debe conservar al menos 1 página.');
      }

      final sourceFile = File(config.sourcePdfPath);
      if (!await sourceFile.exists()) {
        throw FileSystemException(
          'No se encontró el PDF de origen',
          config.sourcePdfPath,
        );
      }

      yield OrganizePdfProgress(
        processedPages: 0,
        totalPages: total,
        statusMessage:
            'Reorganizando y rotando $total páginas vectoriales en Isolate...',
      );

      final pageSpecs = config.pages
          .map(
            (item) => (
              index: item.originalPageIndex,
              rotationDelta: item.rotationDeltaDegrees,
            ),
          )
          .toList();

      await Isolate.run(
        () => _organizeInIsolate(
          sourcePdfPath: config.sourcePdfPath,
          outputPdfPath: config.outputPdfPath,
          pageSpecs: pageSpecs,
        ),
      );

      if (_isCancelled) {
        await _sandboxCleaner.deleteTempFile(config.outputPdfPath);
        return;
      }

      yield OrganizePdfProgress(
        processedPages: total,
        totalPages: total,
        statusMessage: 'PDF organizado con éxito ($total páginas finales).',
        isCompleted: true,
        outputPdfPath: config.outputPdfPath,
      );
    } catch (e) {
      await _sandboxCleaner.deleteTempFile(config.outputPdfPath);
      yield OrganizePdfProgress(
        processedPages: 0,
        totalPages: total,
        statusMessage: 'Error al organizar las páginas del PDF.',
        errorMessage: e.toString(),
      );
    }
  }

  static Future<void> _organizeInIsolate({
    required String sourcePdfPath,
    required String outputPdfPath,
    required List<({int index, int rotationDelta})> pageSpecs,
  }) async {
    final bytes = await File(sourcePdfPath).readAsBytes();
    final sourceDoc = sfpdf.PdfDocument(inputBytes: bytes);
    final targetDoc = sfpdf.PdfDocument();
    targetDoc.compressionLevel = sfpdf.PdfCompressionLevel.aboveNormal;

    try {
      for (final spec in pageSpecs) {
        if (spec.index >= 0 && spec.index < sourceDoc.pages.count) {
          PdfVectorHelpers.appendVectorPage(
            targetDoc,
            sourceDoc.pages[spec.index],
            additionalRotationDegrees: spec.rotationDelta,
          );
        }
      }

      final outBytes = await targetDoc.save();
      final outFile = File(outputPdfPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(outBytes, flush: true);
    } finally {
      sourceDoc.dispose();
      targetDoc.dispose();
    }
  }
}
