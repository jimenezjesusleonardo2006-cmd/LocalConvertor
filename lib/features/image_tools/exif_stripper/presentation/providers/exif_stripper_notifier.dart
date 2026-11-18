import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/exif_stripper_isolate_service.dart';
import '../../domain/exif_stripper_config.dart';

final exifStripperIsolateServiceProvider =
    Provider.autoDispose<ExifStripperIsolateService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = ExifStripperIsolateService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class ExifStripperState {
  final List<ExifImageItem> files;
  final bool packageAsZip;
  final bool isProcessing;
  final double progress;
  final int? lastTotalTagsRemoved;
  final String? statusMessage;
  final String? errorMessage;

  const ExifStripperState({
    this.files = const [],
    this.packageAsZip = false,
    this.isProcessing = false,
    this.progress = 0.0,
    this.lastTotalTagsRemoved,
    this.statusMessage,
    this.errorMessage,
  });

  int get totalDetectedTags => files.fold<int>(
        0,
        (sum, item) => sum + item.detectedTags.length,
      );

  ExifStripperState copyWith({
    List<ExifImageItem>? files,
    bool? packageAsZip,
    bool? isProcessing,
    double? progress,
    int? lastTotalTagsRemoved,
    bool clearRemovedCount = false,
    String? statusMessage,
    String? errorMessage,
  }) {
    return ExifStripperState(
      files: files ?? this.files,
      packageAsZip: packageAsZip ?? this.packageAsZip,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      lastTotalTagsRemoved: clearRemovedCount
          ? null
          : (lastTotalTagsRemoved ?? this.lastTotalTagsRemoved),
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class ExifStripperNotifier extends Notifier<ExifStripperState> {
  StreamSubscription<ExifStripperProgressEvent>? _subscription;
  String? _currentSessionId;

  @override
  ExifStripperState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const ExifStripperState();
  }

  Future<void> addImageFiles(List<String> paths) async {
    const validExts = {'.jpg', '.jpeg', '.png', '.webp', '.tif', '.tiff'};
    final items = <ExifImageItem>[];

    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      if (!validExts.contains(ext)) continue;

      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final tags = await Isolate.run(
          () => ExifStripperIsolateService.inspectExifTags(bytes),
        );
        items.add(
          ExifImageItem(
            path: path,
            fileName: p.basename(path),
            originalSizeBytes: bytes.length,
            detectedTags: tags,
          ),
        );
      }
    }

    if (items.isNotEmpty) {
      final updated = [...state.files, ...items];
      state = state.copyWith(
        files: updated,
        clearRemovedCount: true,
        statusMessage: MemoryGuardConfig.exceedsRecommendedBatch(updated.length)
            ? 'Lote amplio (${updated.length} archivos). Protegido con MemoryGuard (${MemoryGuardConfig.maxSafeImageDimensionPx}px).'
            : null,
      );
    }
  }

  void removeFileAt(int index) {
    final updated = List<ExifImageItem>.from(state.files)..removeAt(index);
    state = state.copyWith(files: updated);
  }

  void clearAll() {
    state = state.copyWith(
      files: const [],
      clearRemovedCount: true,
    );
  }

  void updateSettings({bool? packageAsZip}) {
    state = state.copyWith(packageAsZip: packageAsZip);
  }

  Future<void> stripAndExport() async {
    if (state.files.isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(exifStripperIsolateServiceProvider);

    _currentSessionId = 'exif_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando eliminación segura de metadatos EXIF...',
    );

    _subscription = service
        .stripBatch(
      ExifStripperBatchConfig(
        inputPaths: state.files.map((f) => f.path).toList(),
        sessionDirPath: sessionDir.path,
        packageAsZip: state.packageAsZip || state.files.length > 1,
        maxDimensionPx: MemoryGuardConfig.maxSafeImageDimensionPx,
      ),
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

      if (event.isCompleted) {
        await _exportOutput(event);
        return;
      }

      state = state.copyWith(
        isProcessing: true,
        progress: event.progress,
        statusMessage: event.statusMessage,
      );
    });
  }

  Future<void> _exportOutput(ExifStripperProgressEvent event) async {
    try {
      String? savedName;
      if (event.zipFilePath != null) {
        final uri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar imágenes limpias en .ZIP (LocalConvert)',
          fileName: p.basename(event.zipFilePath!),
          sourceFilePath: event.zipFilePath!,
        );
        savedName = uri != null ? p.basename(event.zipFilePath!) : null;
      } else if (event.outputFiles.isNotEmpty) {
        final path = event.outputFiles.first;
        final uri = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar imagen sin metadatos EXIF (LocalConvert)',
          fileName: p.basename(path),
          sourceFilePath: path,
        );
        savedName = uri != null ? p.basename(path) : null;
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        lastTotalTagsRemoved: event.totalTagsRemoved,
        statusMessage: savedName != null
            ? 'Guardado "$savedName" (${event.totalTagsRemoved} etiquetas EXIF/GPS eliminadas).'
            : 'Limpieza completada (exportación cancelada).',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error al exportar las imágenes limpias: $e',
      );
    } finally {
      await _cleanupActiveSession();
    }
  }

  void cancelProcess() {
    _subscription?.cancel();
    ref.read(exifStripperIsolateServiceProvider).cancel();
    _cleanupActiveSession();
    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Operación cancelada. Sandbox limpio.',
    );
  }

  Future<void> _cleanupActiveSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final exifStripperNotifierProvider =
    NotifierProvider<ExifStripperNotifier, ExifStripperState>(
  ExifStripperNotifier.new,
);
