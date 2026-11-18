import '../../../../../core/sandbox/sandbox_cleaner_service.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../data/image_to_pdf_isolate_service.dart';
import '../../domain/image_to_pdf_config.dart';

/// Proveedor global del servicio de limpieza del Sandbox Local.
final sandboxCleanerProvider = Provider<SandboxCleanerService>((ref) {
  return SandboxCleanerService();
});

/// Proveedor del servicio de conversión en Isolate para Imágenes a PDF.
final imageToPdfIsolateServiceProvider =
    Provider.autoDispose<ImageToPdfIsolateService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = ImageToPdfIsolateService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

/// Estado inmutable de la herramienta "Imágenes a PDF".
class ImageToPdfState {
  final List<String> selectedImages;
  final PdfPageOrientationOption orientation;
  final PdfPageSizeOption pageSize;
  final PdfMarginOption margin;
  final int jpegQuality;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const ImageToPdfState({
    this.selectedImages = const [],
    this.orientation = PdfPageOrientationOption.portrait,
    this.pageSize = PdfPageSizeOption.a4,
    this.margin = PdfMarginOption.small,
    this.jpegQuality = 88,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  ImageToPdfState copyWith({
    List<String>? selectedImages,
    PdfPageOrientationOption? orientation,
    PdfPageSizeOption? pageSize,
    PdfMarginOption? margin,
    int? jpegQuality,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return ImageToPdfState(
      selectedImages: selectedImages ?? this.selectedImages,
      orientation: orientation ?? this.orientation,
      pageSize: pageSize ?? this.pageSize,
      margin: margin ?? this.margin,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

/// Controlador Riverpod que coordina la selección, reordenamiento Drag & Drop,
/// ejecución en el [Isolate], exportación final y destrucción del Sandbox temporal.
class ImageToPdfNotifier extends Notifier<ImageToPdfState> {
  StreamSubscription<ImageToPdfProgressEvent>? _subscription;
  String? _currentSessionId;

  @override
  ImageToPdfState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const ImageToPdfState();
  }

  /// Añade archivos desde `file_picker` o zona Drag & Drop de escritorio.
  void addImages(List<String> paths) {
    final validExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
    final filtered = paths.where((path) {
      final ext = p.extension(path).toLowerCase();
      return validExtensions.contains(ext);
    }).toList();

    final updated = [...state.selectedImages, ...filtered];
    final batchNotice = MemoryGuardConfig.exceedsRecommendedBatch(updated.length)
        ? 'Lote amplio (${updated.length} imágenes). Se aplicará límite seguro de ${MemoryGuardConfig.maxSafeImageDimensionPx}px para proteger la memoria.'
        : null;

    state = state.copyWith(
      selectedImages: updated,
      statusMessage: batchNotice,
    );
  }

  /// Reordena páginas mediante Drag & Drop en la cuadrícula de previsualización.
  void reorderImages(int oldIndex, int newIndex) {
    final items = List<String>.from(state.selectedImages);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    state = state.copyWith(selectedImages: items);
  }

  void removeImageAt(int index) {
    final items = List<String>.from(state.selectedImages)..removeAt(index);
    state = state.copyWith(selectedImages: items);
  }

  void updateConfig({
    PdfPageOrientationOption? orientation,
    PdfPageSizeOption? pageSize,
    PdfMarginOption? margin,
    int? jpegQuality,
  }) {
    state = state.copyWith(
      orientation: orientation,
      pageSize: pageSize,
      margin: margin,
      jpegQuality: jpegQuality,
    );
  }

  /// Ejecuta el flujo completo:
  /// 1. Crea sesión aislada en `CacheDir`
  /// 2. Procesa imágenes en el [Isolate] con barra de progreso determinista
  /// 3. Solicita destino de guardado al usuario y destruye los temporales inmediatamente
  Future<void> convertAndExport() async {
    if (state.selectedImages.isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final isolateService = ref.read(imageToPdfIsolateServiceProvider);

    _currentSessionId = 'img2pdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final tempOutputPath = p.join(sessionDir.path, 'output_temp.pdf');

    state = state.copyWith(
      isProcessing: true,
      progress: 0.0,
      statusMessage: 'Iniciando motor local en segundo plano...',
    );

    final config = ImageToPdfConfig(
      imagePaths: state.selectedImages,
      outputFilePath: tempOutputPath,
      orientation: state.orientation,
      pageSize: state.pageSize,
      margin: state.margin,
      jpegQuality: state.jpegQuality,
      maxDimensionPx: MemoryGuardConfig.maxSafeImageDimensionPx,
    );

    _subscription = isolateService.convertImagesToPdf(config).listen(
      (event) async {
        switch (event.stage) {
          case ConversionStage.initializing:
            state = state.copyWith(
              isProcessing: true,
              progress: 0.02,
              statusMessage: 'Preparando documento PDF...',
            );
          case ConversionStage.processingImage:
            state = state.copyWith(
              isProcessing: true,
              progress: event.progress,
              statusMessage:
                  'Procesando ${event.currentIndex}/${event.totalImages}: ${event.currentFileName}',
            );
          case ConversionStage.writingPdf:
            state = state.copyWith(
              isProcessing: true,
              progress: event.progress,
              statusMessage: 'Empaquetando y comprimiendo PDF...',
            );
          case ConversionStage.completed:
            await _handleExportAndCleanup(event.outputFilePath!);
          case ConversionStage.failed:
            await _cleanupActiveSession();
            state = state.copyWith(
              isProcessing: false,
              progress: 0.0,
              errorMessage: event.errorMessage ?? 'Error durante la conversión.',
            );
        }
      },
    );
  }

  /// Cancela el procesamiento activo y purga inmediatamente el Sandbox temporal.
  Future<void> cancelConversion() async {
    await _subscription?.cancel();
    await ref.read(imageToPdfIsolateServiceProvider).cancel();
    await _cleanupActiveSession();

    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Conversión cancelada. Archivos temporales destruidos.',
    );
  }

  Future<void> _handleExportAndCleanup(String tempPdfPath) async {
    try {
      final saveUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar PDF generado',
        fileName: 'LocalConvert_${DateTime.now().millisecondsSinceEpoch}.pdf',
        sourceFilePath: tempPdfPath,
        mimeType: 'application/pdf',
      );

      state = state.copyWith(
        isProcessing: false,
        progress: saveUri != null ? 1.0 : 0.0,
        statusMessage: saveUri != null
            ? 'PDF exportado con éxito y caché temporal limpiada.'
            : 'Exportación cancelada. Archivos temporales eliminados.',
      );
    } finally {
      // Destrucción estricta e inmediata del archivo temporal sin importar el resultado.
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

final imageToPdfNotifierProvider =
     NotifierProvider.autoDispose<ImageToPdfNotifier, ImageToPdfState>(
  ImageToPdfNotifier.new,
);





