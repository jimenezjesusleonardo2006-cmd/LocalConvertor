import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_vector_helpers.dart';
import '../../../images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/split_pdf_service.dart';
import '../../domain/page_range_parser.dart';
import '../../domain/split_pdf_config.dart';

final splitPdfServiceProvider = Provider.autoDispose<SplitPdfService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = SplitPdfService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class SplitPdfState {
  final String? selectedPdfPath;
  final List<Uint8List> pageThumbnails;
  final bool isLoadingPreview;
  final String rangeExpression;
  final ParsedPageRangesResult parsedRanges;
  final SplitOutputMode outputMode;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const SplitPdfState({
    this.selectedPdfPath,
    this.pageThumbnails = const [],
    this.isLoadingPreview = false,
    this.rangeExpression = '1',
    this.parsedRanges = const ParsedPageRangesResult(),
    this.outputMode = SplitOutputMode.singleCombinedPdf,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  int get totalPages => pageThumbnails.length;

  SplitPdfState copyWith({
    String? selectedPdfPath,
    bool clearSelectedPdf = false,
    List<Uint8List>? pageThumbnails,
    bool? isLoadingPreview,
    String? rangeExpression,
    ParsedPageRangesResult? parsedRanges,
    SplitOutputMode? outputMode,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return SplitPdfState(
      selectedPdfPath:
          clearSelectedPdf ? null : (selectedPdfPath ?? this.selectedPdfPath),
      pageThumbnails: pageThumbnails ?? this.pageThumbnails,
      isLoadingPreview: isLoadingPreview ?? this.isLoadingPreview,
      rangeExpression: rangeExpression ?? this.rangeExpression,
      parsedRanges: parsedRanges ?? this.parsedRanges,
      outputMode: outputMode ?? this.outputMode,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class SplitPdfNotifier extends Notifier<SplitPdfState> {
  StreamSubscription<SplitPdfProgress>? _subscription;
  String? _currentSessionId;

  @override
  SplitPdfState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const SplitPdfState();
  }

  Future<void> selectPdfFile(String filePath) async {
    if (p.extension(filePath).toLowerCase() != '.pdf') return;

    state = state.copyWith(
      selectedPdfPath: filePath,
      pageThumbnails: const [],
      isLoadingPreview: true,
      statusMessage: 'Analizando páginas del documento...',
    );

    try {
      final bytes = await File(filePath).readAsBytes();
      final totalPageCount = PdfVectorHelpers.readPageCount(bytes);
      final thumbs = <Uint8List>[];

      try {
        await for (final page in Printing.raster(
          bytes,
          dpi: MemoryGuardConfig.pdfPreviewDpi,
        )) {
          final png = await page.toPng();
          thumbs.add(png);
          state = state.copyWith(
            pageThumbnails: List<Uint8List>.from(thumbs),
            isLoadingPreview: true,
          );
        }
      } catch (_) {}

      final effectiveCount =
          thumbs.isNotEmpty ? thumbs.length : totalPageCount;
      final defaultRange = effectiveCount > 1 ? '1-$effectiveCount' : '1';
      final parsed = PageRangeParser.parse(
        defaultRange,
        maxPages: effectiveCount,
      );

      state = state.copyWith(
        isLoadingPreview: false,
        rangeExpression: defaultRange,
        parsedRanges: parsed,
        statusMessage:
            'PDF cargado ($effectiveCount páginas). Selecciona rangos o haz clic en las miniaturas.',
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingPreview: false,
        errorMessage: 'Error al leer el PDF: $e',
      );
    }
  }

  void clearSelection() {
    state = state.copyWith(
      clearSelectedPdf: true,
      pageThumbnails: const [],
      rangeExpression: '',
      parsedRanges: const ParsedPageRangesResult(),
    );
  }

  void updateRangeExpression(String expression) {
    final parsed = PageRangeParser.parse(
      expression,
      maxPages: state.totalPages,
    );
    state = state.copyWith(
      rangeExpression: expression,
      parsedRanges: parsed,
    );
  }

  /// Permite activar/desactivar una página haciendo clic directamente sobre su miniatura.
  void togglePageSelection(int pageNumber) {
    final currentSet = Set<int>.from(state.parsedRanges.uniqueSortedPages);
    if (currentSet.contains(pageNumber)) {
      currentSet.remove(pageNumber);
    } else {
      currentSet.add(pageNumber);
    }

    final newExpression = PageRangeParser.formatPagesToRangeString(currentSet);
    updateRangeExpression(newExpression);
  }

  void updateOutputMode(SplitOutputMode mode) {
    state = state.copyWith(outputMode: mode);
  }

  Future<void> splitAndExport() async {
    if (state.selectedPdfPath == null ||
        !state.parsedRanges.isValid ||
        state.isProcessing) {
      return;
    }

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(splitPdfServiceProvider);

    _currentSessionId = 'splitpdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando extracción de rangos...',
    );

    final config = SplitPdfConfig(
      sourcePdfPath: state.selectedPdfPath!,
      sessionDirPath: sessionDir.path,
      segments: state.parsedRanges.segments,
      uniquePagesToExtract: state.parsedRanges.uniqueSortedPages,
      outputMode: state.outputMode,
    );

    _subscription = service.splitPdf(config).listen((event) async {
      if (event.errorMessage != null) {
        await _cleanupActiveSession();
        state = state.copyWith(
          isProcessing: false,
          progress: 0.0,
          errorMessage: event.errorMessage,
        );
        return;
      }

      if (!event.isCompleted) {
        state = state.copyWith(
          isProcessing: true,
          progress: event.progress,
          statusMessage: event.statusMessage,
        );
      } else {
        await _exportSplitOutputAndCleanup(event);
      }
    });
  }

  Future<void> cancelSplit() async {
    ref.read(splitPdfServiceProvider).cancel();
    await _subscription?.cancel();
    await _cleanupActiveSession();

    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'División cancelada y archivos temporales eliminados.',
    );
  }

  Future<void> _exportSplitOutputAndCleanup(SplitPdfProgress event) async {
    try {
      final baseName = p.basenameWithoutExtension(state.selectedPdfPath!);

      if (event.singleOutputPdfPath != null) {
        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar PDF Extraído',
          fileName: '${baseName}_extraido.pdf',
          sourceFilePath: event.singleOutputPdfPath!,
          mimeType: 'application/pdf',
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'PDF extraído exportado con éxito y caché temporal limpiada.'
              : 'Exportación cancelada. Archivos temporales destruidos.',
        );
      } else if (event.zipOutputPath != null) {
        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar ZIP de Rangos PDF',
          fileName: '${baseName}_rangos.zip',
          sourceFilePath: event.zipOutputPath!,
          mimeType: 'application/zip',
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'ZIP con PDFs divididos exportado y caché temporal limpiada.'
              : 'Exportación cancelada. Archivos temporales destruidos.',
        );
      }
    } finally {
      await _cleanupActiveSession();
    }
  }

  Future<void> _cleanupActiveSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final splitPdfNotifierProvider =
    NotifierProvider.autoDispose<SplitPdfNotifier, SplitPdfState>(
  SplitPdfNotifier.new,
);




