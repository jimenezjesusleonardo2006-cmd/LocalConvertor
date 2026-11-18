import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/image_format_isolate_service.dart';
import '../../domain/image_format_config.dart';

final imageFormatIsolateServiceProvider =
    Provider.autoDispose<ImageFormatIsolateService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = ImageFormatIsolateService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class ImageFormatConverterState {
  final List<ImageBatchFileItem> files;
  final TargetImageFormat targetFormat;
  final int quality;
  final int svgScaleMultiplier;
  final bool packageAsZip;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const ImageFormatConverterState({
    this.files = const [],
    this.targetFormat = TargetImageFormat.png,
    this.quality = 90,
    this.svgScaleMultiplier = 2,
    this.packageAsZip = false,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  ImageFormatConverterState copyWith({
    List<ImageBatchFileItem>? files,
    TargetImageFormat? targetFormat,
    int? quality,
    int? svgScaleMultiplier,
    bool? packageAsZip,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return ImageFormatConverterState(
      files: files ?? this.files,
      targetFormat: targetFormat ?? this.targetFormat,
      quality: quality ?? this.quality,
      svgScaleMultiplier: svgScaleMultiplier ?? this.svgScaleMultiplier,
      packageAsZip: packageAsZip ?? this.packageAsZip,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class ImageFormatConverterNotifier
    extends Notifier<ImageFormatConverterState> {
  StreamSubscription<ImageFormatProgressEvent>? _subscription;
  String? _currentSessionId;

  @override
  ImageFormatConverterState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const ImageFormatConverterState();
  }

  Future<void> addImageFiles(List<String> paths) async {
    const validExts = {
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.bmp',
      '.tif',
      '.tiff',
      '.ico',
      '.gif',
      '.tga',
      '.svg',
    };
    final items = <ImageBatchFileItem>[];

    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      if (!validExts.contains(ext)) continue;

      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        items.add(
          ImageBatchFileItem(
            path: path,
            fileName: p.basename(path),
            originalSizeBytes: stat.size,
            sourceExtension: ext.replaceFirst('.', '').toUpperCase(),
          ),
        );
      }
    }

    if (items.isNotEmpty) {
      final updated = [...state.files, ...items];
      final batchNotice = MemoryGuardConfig.exceedsRecommendedBatch(updated.length)
          ? 'Lote amplio (${updated.length} archivos). Se aplicará límite seguro de ${MemoryGuardConfig.maxSafeImageDimensionPx}px.'
          : null;
      state = state.copyWith(files: updated, statusMessage: batchNotice);
    }
  }

  void removeFileAt(int index) {
    final updated = List<ImageBatchFileItem>.from(state.files)..removeAt(index);
    state = state.copyWith(files: updated);
  }

  void clearAll() {
    state = state.copyWith(files: const []);
  }

  void updateSettings({
    TargetImageFormat? targetFormat,
    int? quality,
    int? svgScaleMultiplier,
    bool? packageAsZip,
  }) {
    state = state.copyWith(
      targetFormat: targetFormat,
      quality: quality,
      svgScaleMultiplier: svgScaleMultiplier,
      packageAsZip: packageAsZip,
    );
  }

  Future<void> convertAndExport() async {
    if (state.files.isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(imageFormatIsolateServiceProvider);

    _currentSessionId = 'imgfmt_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando Isolate de conversión de formatos...',
    );

    final config = ImageFormatBatchConfig(
      inputPaths: state.files.map((f) => f.path).toList(),
      sessionDirPath: sessionDir.path,
      targetFormat: state.targetFormat,
      quality: state.quality,
      packageAsZip: state.packageAsZip || state.files.length > 1,
      maxDimensionPx: MemoryGuardConfig.maxSafeImageDimensionPx,
      svgScaleMultiplier: state.svgScaleMultiplier,
    );

    _subscription = service.convertBatch(config).listen((event) async {
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

  Future<void> cancelConversion() async {
    await _subscription?.cancel();
    await ref.read(imageFormatIsolateServiceProvider).cancel();
    await _cleanupActiveSession();

    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Conversión cancelada y caché temporal destruida.',
    );
  }

  Future<void> _exportResultAndCleanup(ImageFormatProgressEvent event) async {
    try {
      // Si es 1 solo archivo y el usuario no forzó ZIP
      if (event.outputFiles.length == 1 && !state.packageAsZip) {
        final singlePath = event.outputFiles.first;
        final ext = state.targetFormat.extension;

        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar imagen convertida (.${ext.toUpperCase()})',
          fileName: p.basename(singlePath),
          sourceFilePath: singlePath,
          mimeType: LocalFileExporter.mimeTypeForExtension(ext),
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'Imagen convertida a .${ext.toUpperCase()} con éxito y caché limpiada.'
              : 'Exportación cancelada. Archivos temporales destruidos.',
        );
      } else if (event.zipFilePath != null) {
        final saveUri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar lote convertido (.ZIP)',
          fileName: p.basename(event.zipFilePath!),
          sourceFilePath: event.zipFilePath!,
          mimeType: 'application/zip',
        );

        state = state.copyWith(
          isProcessing: false,
          progress: saveUri != null ? 1.0 : 0.0,
          statusMessage: saveUri != null
              ? 'Lote de ${event.outputFiles.length} imágenes exportado y caché limpiada.'
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

final imageFormatConverterNotifierProvider = NotifierProvider.autoDispose<
    ImageFormatConverterNotifier, ImageFormatConverterState>(
  ImageFormatConverterNotifier.new,
);




