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
import '../../data/pdf_to_images_service.dart';
import '../../domain/pdf_to_images_config.dart';

final pdfToImagesServiceProvider =
    Provider.autoDispose<PdfToImagesService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = PdfToImagesService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class PdfToImagesState {
  final String? selectedPdfPath;
  final List<Uint8List> pageThumbnails;
  final bool isLoadingPreview;
  final PdfImageOutputFormat outputFormat;
  final PdfImagePackagingMode packagingMode;
  final PdfRasterDpiOption dpiOption;
  final int jpgQuality;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const PdfToImagesState({
    this.selectedPdfPath,
    this.pageThumbnails = const [],
    this.isLoadingPreview = false,
    this.outputFormat = PdfImageOutputFormat.png,
    this.packagingMode = PdfImagePackagingMode.zipArchive,
    this.dpiOption = PdfRasterDpiOption.high,
    this.jpgQuality = 90,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  int get totalPages => pageThumbnails.length;

  PdfToImagesState copyWith({
    String? selectedPdfPath,
    bool clearSelectedPdf = false,
    List<Uint8List>? pageThumbnails,
    bool? isLoadingPreview,
    PdfImageOutputFormat? outputFormat,
    PdfImagePackagingMode? packagingMode,
    PdfRasterDpiOption? dpiOption,
    int? jpgQuality,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return PdfToImagesState(
      selectedPdfPath:
          clearSelectedPdf ? null : (selectedPdfPath ?? this.selectedPdfPath),
      pageThumbnails: pageThumbnails ?? this.pageThumbnails,
      isLoadingPreview: isLoadingPreview ?? this.isLoadingPreview,
      outputFormat: outputFormat ?? this.outputFormat,
      packagingMode: packagingMode ?? this.packagingMode,
      dpiOption: dpiOption ?? this.dpiOption,
      jpgQuality: jpgQuality ?? this.jpgQuality,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class PdfToImagesNotifier extends Notifier<PdfToImagesState> {
  StreamSubscription<PdfToImagesProgress>? _subscription;
  String? _currentSessionId;

  @override
  PdfToImagesState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const PdfToImagesState();
  }

  /// Carga un archivo PDF y genera miniaturas ligeras en baja resolución (45 DPI)
  /// para mostrar la vista previa en cuadrícula.
  Future<void> selectPdfFile(String filePath) async {
    if (p.extension(filePath).toLowerCase() != '.pdf') return;

    state = state.copyWith(
      selectedPdfPath: filePath,
      pageThumbnails: const [],
      isLoadingPreview: true,
      statusMessage: 'Generando vista previa de páginas...',
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

      final detectedCount = thumbs.isNotEmpty ? thumbs.length : totalPageCount;
      state = state.copyWith(
        isLoadingPreview: false,
        statusMessage:
            'Documento listo ($detectedCount páginas detectadas).',
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingPreview: false,
        errorMessage: 'No se pudo leer el PDF: $e',
      );
    }
  }

  void clearSelection() {
    state = state.copyWith(
      clearSelectedPdf: true,
      pageThumbnails: const [],
    );
  }

  void updateConfig({
    PdfImageOutputFormat? outputFormat,
    PdfImagePackagingMode? packagingMode,
    PdfRasterDpiOption? dpiOption,
    int? jpgQuality,
  }) {
    state = state.copyWith(
      outputFormat: outputFormat,
      packagingMode: packagingMode,
      dpiOption: dpiOption,
      jpgQuality: jpgQuality,
    );
  }

  Future<void> extractAndExport() async {
    if (state.selectedPdfPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(pdfToImagesServiceProvider);

    _currentSessionId = 'pdf2img_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando extracción de páginas...',
    );

    final config = PdfToImagesConfig(
      sourcePdfPath: state.selectedPdfPath!,
      sessionDirPath: sessionDir.path,
      outputFormat: state.outputFormat,
      packagingMode: state.packagingMode,
      dpiOption: state.dpiOption,
      jpgQuality: state.jpgQuality,
    );

    _subscription = service
        .extractPdfToImages(
          config,
          knownTotalPages:
              state.totalPages > 0 ? state.totalPages : null,
        )
        .listen((event) async {
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
        await _exportResultAndCleanup(event);
      }
    });
  }

  Future<void> cancelExtraction() async {
    ref.read(pdfToImagesServiceProvider).cancel();
    await _subscription?.cancel();
    await _cleanupActiveSession();

    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Extracción cancelada y archivos temporales eliminados.',
    );
  }

  Future<void> _exportResultAndCleanup(PdfToImagesProgress event) async {
    try {
      final baseName = p.basenameWithoutExtension(state.selectedPdfPath!);

      // Si se generó un archivo ZIP
      if (event.zipFilePath != null) {
        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar archivo ZIP de imágenes',
          fileName: '${baseName}_imagenes.zip',
          sourceFilePath: event.zipFilePath!,
          mimeType: 'application/zip',
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'ZIP con ${event.processedPages} imágenes exportado y caché limpiada.'
              : 'Exportación cancelada. Archivos temporales destruidos.',
        );
      } else {
        // Exportar imágenes individuales a una carpeta en Escritorio
        final exported = await LocalFileExporter.exportImagesToDirectory(
          dialogTitle: 'Seleccionar carpeta para guardar las imágenes',
          tempImagePaths: event.extractedImagePaths,
        );

        state = state.copyWith(
          isProcessing: false,
          progress: exported ? 1.0 : 0.0,
          statusMessage: exported
              ? '${event.extractedImagePaths.length} imágenes guardadas y caché temporal limpiada.'
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

final pdfToImagesNotifierProvider =
    NotifierProvider.autoDispose<PdfToImagesNotifier, PdfToImagesState>(
  PdfToImagesNotifier.new,
);




