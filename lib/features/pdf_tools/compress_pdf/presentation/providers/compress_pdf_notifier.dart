import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_vector_helpers.dart';
import '../../../images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/compress_pdf_service.dart';
import '../../domain/compress_pdf_config.dart';

final compressPdfServiceProvider =
    Provider.autoDispose<CompressPdfService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  return CompressPdfService(sandboxCleaner: cleaner);
});

class CompressPdfState {
  final String? sourcePdfPath;
  final int originalSizeBytes;
  final int pageCount;
  final CompressPdfLevel level;
  final bool isProcessing;
  final double progress;
  final int? lastCompressedBytes;
  final String? statusMessage;
  final String? errorMessage;

  const CompressPdfState({
    this.sourcePdfPath,
    this.originalSizeBytes = 0,
    this.pageCount = 0,
    this.level = CompressPdfLevel.highQuality,
    this.isProcessing = false,
    this.progress = 0.0,
    this.lastCompressedBytes,
    this.statusMessage,
    this.errorMessage,
  });

  CompressPdfState copyWith({
    String? sourcePdfPath,
    bool clearSource = false,
    int? originalSizeBytes,
    int? pageCount,
    CompressPdfLevel? level,
    bool? isProcessing,
    double? progress,
    int? lastCompressedBytes,
    bool clearCompressedBytes = false,
    String? statusMessage,
    String? errorMessage,
  }) {
    return CompressPdfState(
      sourcePdfPath:
          clearSource ? null : (sourcePdfPath ?? this.sourcePdfPath),
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      pageCount: pageCount ?? this.pageCount,
      level: level ?? this.level,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      lastCompressedBytes: clearCompressedBytes
          ? null
          : (lastCompressedBytes ?? this.lastCompressedBytes),
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class CompressPdfNotifier extends Notifier<CompressPdfState> {
  String? _currentSessionId;

  @override
  CompressPdfState build() {
    ref.onDispose(_cleanupSession);
    return const CompressPdfState();
  }

  Future<void> loadPdfFile(String filePath) async {
    if (p.extension(filePath).toLowerCase() != '.pdf') return;
    final file = File(filePath);
    if (!await file.exists()) return;

    try {
      final bytes = await file.readAsBytes();
      final pageCount = PdfVectorHelpers.readPageCount(bytes);
      state = state.copyWith(
        sourcePdfPath: filePath,
        originalSizeBytes: bytes.length,
        pageCount: pageCount,
        clearCompressedBytes: true,
        statusMessage:
            'PDF "${p.basename(filePath)}" cargado ($pageCount páginas).',
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al inspeccionar PDF: $e');
    }
  }

  void clear() {
    state = state.copyWith(
      clearSource: true,
      originalSizeBytes: 0,
      pageCount: 0,
      clearCompressedBytes: true,
    );
  }

  void updateLevel(CompressPdfLevel level) {
    state = state.copyWith(level: level);
  }

  Future<void> compressAndExport() async {
    if (state.sourcePdfPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(compressPdfServiceProvider);

    _currentSessionId = 'cmppdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(state.sourcePdfPath!);
    final fileName = '${baseName}_comprimido.pdf';
    final tempOut = p.join(sessionDir.path, fileName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.35,
      statusMessage: 'Optimizando y comprimiendo PDF en local...',
    );

    try {
      final result = await service.compressPdf(
        CompressPdfConfig(
          sourcePdfPath: state.sourcePdfPath!,
          outputPdfPath: tempOut,
          level: state.level,
          maxDimensionPx: MemoryGuardConfig.maxSafeImageDimensionPx,
        ),
      );

      final savedUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar PDF comprimido (LocalConvert)',
        fileName: fileName,
        sourceFilePath: result.outputPdfPath,
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        lastCompressedBytes: result.compressedBytes,
        statusMessage: savedUri != null
            ? 'PDF comprimido guardado (${result.savedPercent.toStringAsFixed(1)}% de ahorro).'
            : 'Guardado cancelado.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error al comprimir el PDF: $e',
      );
    } finally {
      await _cleanupSession();
    }
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final compressPdfNotifierProvider =
    NotifierProvider<CompressPdfNotifier, CompressPdfState>(
  CompressPdfNotifier.new,
);
