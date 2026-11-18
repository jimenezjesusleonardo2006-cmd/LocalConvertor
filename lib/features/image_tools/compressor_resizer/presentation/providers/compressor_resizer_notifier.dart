import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../../format_converter/domain/image_format_config.dart';
import '../../data/compressor_resizer_isolate_service.dart';
import '../../domain/compressor_resizer_config.dart';

final compressorResizerServiceProvider =
    Provider.autoDispose<CompressorResizerIsolateService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = CompressorResizerIsolateService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class CompressorResizerState {
  final List<ImageBatchFileItem> files;
  final ImageResizeMode resizeMode;
  final int scalePercent;
  final int? targetWidthPx;
  final int? targetHeightPx;
  final bool maintainAspectRatio;
  final int quality;
  final bool isEstimating;
  final CompressionEstimateResult? liveEstimate;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const CompressorResizerState({
    this.files = const [],
    this.resizeMode = ImageResizeMode.percentage,
    this.scalePercent = 100,
    this.targetWidthPx,
    this.targetHeightPx,
    this.maintainAspectRatio = true,
    this.quality = 80,
    this.isEstimating = false,
    this.liveEstimate,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  CompressorResizerState copyWith({
    List<ImageBatchFileItem>? files,
    ImageResizeMode? resizeMode,
    int? scalePercent,
    int? targetWidthPx,
    bool clearTargetWidth = false,
    int? targetHeightPx,
    bool clearTargetHeight = false,
    bool? maintainAspectRatio,
    int? quality,
    bool? isEstimating,
    CompressionEstimateResult? liveEstimate,
    bool clearEstimate = false,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return CompressorResizerState(
      files: files ?? this.files,
      resizeMode: resizeMode ?? this.resizeMode,
      scalePercent: scalePercent ?? this.scalePercent,
      targetWidthPx:
          clearTargetWidth ? null : (targetWidthPx ?? this.targetWidthPx),
      targetHeightPx:
          clearTargetHeight ? null : (targetHeightPx ?? this.targetHeightPx),
      maintainAspectRatio: maintainAspectRatio ?? this.maintainAspectRatio,
      quality: quality ?? this.quality,
      isEstimating: isEstimating ?? this.isEstimating,
      liveEstimate: clearEstimate ? null : (liveEstimate ?? this.liveEstimate),
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class CompressorResizerNotifier
    extends Notifier<CompressorResizerState> {
  StreamSubscription<CompressorProgressEvent>? _subscription;
  Timer? _estimateDebounce;
  String? _currentSessionId;

  @override
  CompressorResizerState build() {
    ref.onDispose(() {
      _estimateDebounce?.cancel();
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const CompressorResizerState();
  }

  Future<void> addImageFiles(List<String> paths) async {
    const validExts = {'.jpg', '.jpeg', '.png', '.webp'};
    final added = <ImageBatchFileItem>[];

    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      if (!validExts.contains(ext)) continue;

      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        added.add(
          ImageBatchFileItem(
            path: path,
            fileName: p.basename(path),
            originalSizeBytes: stat.size,
            sourceExtension: ext.replaceFirst('.', '').toUpperCase(),
          ),
        );
      }
    }

    if (added.isNotEmpty) {
      final updated = [...state.files, ...added];
      final batchNotice = MemoryGuardConfig.exceedsRecommendedBatch(updated.length)
          ? 'Lote amplio (${updated.length} imágenes). Se aplicará límite seguro de ${MemoryGuardConfig.maxSafeImageDimensionPx}px.'
          : null;
      state = state.copyWith(files: updated, statusMessage: batchNotice);
      _scheduleLiveEstimate();
    }
  }

  void removeFileAt(int index) {
    final updated = List<ImageBatchFileItem>.from(state.files)..removeAt(index);
    state = state.copyWith(
      files: updated,
      clearEstimate: updated.isEmpty,
    );
    if (updated.isNotEmpty) {
      _scheduleLiveEstimate();
    }
  }

  void updateParameters({
    ImageResizeMode? resizeMode,
    int? scalePercent,
    int? targetWidthPx,
    bool clearTargetWidth = false,
    int? targetHeightPx,
    bool clearTargetHeight = false,
    bool? maintainAspectRatio,
    int? quality,
  }) {
    state = state.copyWith(
      resizeMode: resizeMode,
      scalePercent: scalePercent,
      targetWidthPx: targetWidthPx,
      clearTargetWidth: clearTargetWidth,
      targetHeightPx: targetHeightPx,
      clearTargetHeight: clearTargetHeight,
      maintainAspectRatio: maintainAspectRatio,
      quality: quality,
    );
    _scheduleLiveEstimate();
  }

  void _scheduleLiveEstimate() {
    _estimateDebounce?.cancel();
    if (state.files.isEmpty) return;

    state = state.copyWith(isEstimating: true);
    _estimateDebounce = Timer(const Duration(milliseconds: 220), () async {
      final sampleFile = state.files.first;
      final service = ref.read(compressorResizerServiceProvider);

      final result = await service.estimateSingleFile(
        filePath: sampleFile.path,
        resizeMode: state.resizeMode,
        scalePercent: state.scalePercent,
        targetWidthPx: state.targetWidthPx,
        targetHeightPx: state.targetHeightPx,
        maintainAspectRatio: state.maintainAspectRatio,
        quality: state.quality,
        maxDimensionPx: MemoryGuardConfig.maxSafeImageDimensionPx,
      );

      state = state.copyWith(
        isEstimating: false,
        liveEstimate: result,
      );
    });
  }

  Future<void> compressAndExport() async {
    if (state.files.isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(compressorResizerServiceProvider);

    _currentSessionId = 'imgcomp_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando compresión y redimensionamiento en Isolate...',
    );

    final config = CompressorResizerBatchConfig(
      inputPaths: state.files.map((e) => e.path).toList(),
      sessionDirPath: sessionDir.path,
      resizeMode: state.resizeMode,
      scalePercent: state.scalePercent,
      targetWidthPx: state.targetWidthPx,
      targetHeightPx: state.targetHeightPx,
      maintainAspectRatio: state.maintainAspectRatio,
      quality: state.quality,
      maxDimensionPx: MemoryGuardConfig.maxSafeImageDimensionPx,
    );

    _subscription = service.processBatch(config).listen((event) async {
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

  Future<void> cancelCompression() async {
    await _subscription?.cancel();
    await ref.read(compressorResizerServiceProvider).cancel();
    await _cleanupActiveSession();

    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Compresión cancelada. Archivos temporales destruidos.',
    );
  }

  Future<void> _exportResultAndCleanup(CompressorProgressEvent event) async {
    try {
      if (event.outputFiles.length == 1) {
        final outPath = event.outputFiles.first;
        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar imagen optimizada',
          fileName: p.basename(outPath),
          sourceFilePath: outPath,
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'Imagen optimizada exportada con éxito y caché temporal limpiada.'
              : 'Exportación cancelada. Archivos temporales eliminados.',
        );
      } else if (event.zipFilePath != null) {
        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar lote de imágenes optimizadas (.ZIP)',
          fileName: p.basename(event.zipFilePath!),
          sourceFilePath: event.zipFilePath!,
          mimeType: 'application/zip',
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'Lote optimizado exportado (.ZIP) y caché temporal limpiada.'
              : 'Exportación cancelada. Archivos temporales eliminados.',
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

final compressorResizerNotifierProvider = NotifierProvider.autoDispose<
    CompressorResizerNotifier, CompressorResizerState>(
  CompressorResizerNotifier.new,
);




