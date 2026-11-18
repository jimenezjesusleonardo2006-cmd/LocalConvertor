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
import '../../data/merge_pdf_service.dart';
import '../../domain/merge_pdf_config.dart';

final mergePdfServiceProvider = Provider.autoDispose<MergePdfService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = MergePdfService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class MergePdfState {
  final List<MergePdfDocumentItem> documents;
  final MergePdfQualityPreset qualityPreset;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const MergePdfState({
    this.documents = const [],
    this.qualityPreset = MergePdfQualityPreset.high,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  int get totalCombinedPages =>
      documents.fold<int>(0, (sum, doc) => sum + doc.pageCount);

  MergePdfState copyWith({
    List<MergePdfDocumentItem>? documents,
    MergePdfQualityPreset? qualityPreset,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return MergePdfState(
      documents: documents ?? this.documents,
      qualityPreset: qualityPreset ?? this.qualityPreset,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class MergePdfNotifier extends Notifier<MergePdfState> {
  StreamSubscription<MergePdfProgress>? _subscription;
  String? _currentSessionId;

  @override
  MergePdfState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupActiveSession();
    });
    return const MergePdfState();
  }

  /// Añade múltiples PDFs y calcula en segundo plano la portada y el conteo de páginas.
  Future<void> addPdfFiles(List<String> paths) async {
    final pdfPaths = paths
        .where((path) => p.extension(path).toLowerCase() == '.pdf')
        .toList();
    if (pdfPaths.isEmpty) return;

    final newDocs = <MergePdfDocumentItem>[];
    for (final filePath in pdfPaths) {
      final id = '${DateTime.now().microsecondsSinceEpoch}_${p.basename(filePath)}';
      final item = MergePdfDocumentItem(
        id: id,
        filePath: filePath,
        fileName: p.basename(filePath),
        pageCount: 0,
      );
      newDocs.add(item);
    }

    state = state.copyWith(
      documents: [...state.documents, ...newDocs],
    );

    // Inspeccionar portada y número de páginas de cada documento nuevo
    for (final item in newDocs) {
      try {
        final bytes = await File(item.filePath).readAsBytes();
        int count = PdfVectorHelpers.readPageCount(bytes);
        Uint8List? coverPng;

        try {
          await for (final page in Printing.raster(
            bytes,
            pages: const [0],
            dpi: MemoryGuardConfig.pdfPreviewDpi,
          )) {
            coverPng ??= await page.toPng();
            break;
          }
        } catch (_) {}

        final updatedList = state.documents.map((doc) {
          if (doc.id == item.id) {
            return doc.copyWith(pageCount: count, coverThumbnail: coverPng);
          }
          return doc;
        }).toList();

        state = state.copyWith(documents: updatedList);
      } catch (_) {}
    }
  }

  void reorderDocuments(int oldIndex, int newIndex) {
    final items = List<MergePdfDocumentItem>.from(state.documents);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    state = state.copyWith(documents: items);
  }

  void removeDocumentAt(int index) {
    final items = List<MergePdfDocumentItem>.from(state.documents)
      ..removeAt(index);
    state = state.copyWith(documents: items);
  }

  void updateQualityPreset(MergePdfQualityPreset preset) {
    state = state.copyWith(qualityPreset: preset);
  }

  Future<void> mergeAndExport() async {
    if (state.documents.length < 2 || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(mergePdfServiceProvider);

    _currentSessionId = 'mergepdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final tempOutputPath = p.join(sessionDir.path, 'merged_output.pdf');

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando unión de ${state.documents.length} PDFs...',
    );

    _subscription = service
        .mergeDocuments(
          documents: state.documents,
          outputPdfPath: tempOutputPath,
          qualityPreset: state.qualityPreset,
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
        await _exportMergedPdfAndCleanup(event.outputPdfPath!);
      }
    });
  }

  Future<void> cancelMerge() async {
    ref.read(mergePdfServiceProvider).cancel();
    await _subscription?.cancel();
    await _cleanupActiveSession();

    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Unión cancelada. Archivos temporales destruidos.',
    );
  }

  Future<void> _exportMergedPdfAndCleanup(String tempPdfPath) async {
    try {
      final saveUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar PDF Unido',
        fileName: 'LocalConvert_Unido_${DateTime.now().millisecondsSinceEpoch}.pdf',
        sourceFilePath: tempPdfPath,
        mimeType: 'application/pdf',
      );

      state = state.copyWith(
        isProcessing: false,
        progress: saveUri != null ? 1.0 : 0.0,
        statusMessage: saveUri != null
            ? 'PDF combinado exportado con éxito y caché temporal limpiada.'
            : 'Exportación cancelada. Archivos temporales eliminados.',
      );
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

final mergePdfNotifierProvider =
    NotifierProvider.autoDispose<MergePdfNotifier, MergePdfState>(
  MergePdfNotifier.new,
);




