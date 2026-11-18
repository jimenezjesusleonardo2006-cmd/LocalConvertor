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
import '../../data/organize_pdf_service.dart';
import '../../domain/organize_pdf_config.dart';

final organizePdfServiceProvider =
    Provider.autoDispose<OrganizePdfService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = OrganizePdfService(sandboxCleaner: cleaner);
  ref.onDispose(service.cancel);
  return service;
});

class OrganizePdfState {
  final String? sourcePdfPath;
  final List<OrganizePdfPageItem> pages;
  final bool isLoadingPreview;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const OrganizePdfState({
    this.sourcePdfPath,
    this.pages = const [],
    this.isLoadingPreview = false,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  OrganizePdfState copyWith({
    String? sourcePdfPath,
    bool clearSource = false,
    List<OrganizePdfPageItem>? pages,
    bool? isLoadingPreview,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return OrganizePdfState(
      sourcePdfPath:
          clearSource ? null : (sourcePdfPath ?? this.sourcePdfPath),
      pages: pages ?? this.pages,
      isLoadingPreview: isLoadingPreview ?? this.isLoadingPreview,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class OrganizePdfNotifier extends Notifier<OrganizePdfState> {
  StreamSubscription<OrganizePdfProgress>? _subscription;
  String? _currentSessionId;
  List<OrganizePdfPageItem> _originalPages = const [];

  @override
  OrganizePdfState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupSession();
    });
    return const OrganizePdfState();
  }

  Future<void> loadPdfFile(String filePath) async {
    if (p.extension(filePath).toLowerCase() != '.pdf') return;

    state = state.copyWith(
      sourcePdfPath: filePath,
      pages: const [],
      isLoadingPreview: true,
      statusMessage: 'Analizando estructura vectorial del PDF...',
    );

    try {
      final bytes = await File(filePath).readAsBytes();
      final totalPages = PdfVectorHelpers.readPageCount(bytes);
      final initialPages = List<OrganizePdfPageItem>.generate(
        totalPages,
        (i) => OrganizePdfPageItem(id: i, originalPageIndex: i),
      );
      _originalPages = initialPages;

      state = state.copyWith(
        pages: initialPages,
        isLoadingPreview: true,
        statusMessage: 'Generando miniaturas ($totalPages páginas)...',
      );

      final thumbs = <int, Uint8List>{};
      try {
        int pageIdx = 0;
        await for (final raster in Printing.raster(
          bytes,
          dpi: MemoryGuardConfig.pdfPreviewDpi,
        )) {
          if (pageIdx >= totalPages) break;
          thumbs[pageIdx] = await raster.toPng();
          pageIdx++;
        }
      } catch (_) {}

      final enriched = [
        for (final item in initialPages)
          item.copyWith(thumbnailBytes: thumbs[item.originalPageIndex]),
      ];
      _originalPages = enriched;

      state = state.copyWith(
        pages: enriched,
        isLoadingPreview: false,
        statusMessage:
            'PDF listo ($totalPages páginas). Arrastra para reordenar o rota cada página.',
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingPreview: false,
        errorMessage: 'No se pudo cargar el PDF: $e',
      );
    }
  }

  void rotatePage(int index, {int deltaDegrees = 90}) {
    if (index < 0 || index >= state.pages.length || state.isProcessing) return;
    final updated = List<OrganizePdfPageItem>.from(state.pages);
    final current = updated[index];
    final nextDeg =
        (((current.rotationDeltaDegrees + deltaDegrees) % 360) + 360) % 360;
    updated[index] = current.copyWith(rotationDeltaDegrees: nextDeg);
    state = state.copyWith(pages: updated);
  }

  void rotateAllPages({int deltaDegrees = 90}) {
    if (state.pages.isEmpty || state.isProcessing) return;
    final updated = state.pages.map((item) {
      final nextDeg =
          (((item.rotationDeltaDegrees + deltaDegrees) % 360) + 360) % 360;
      return item.copyWith(rotationDeltaDegrees: nextDeg);
    }).toList();
    state = state.copyWith(pages: updated);
  }

  void reorderPages(int oldIndex, int newIndex) {
    if (state.isProcessing) return;
    final updated = List<OrganizePdfPageItem>.from(state.pages);
    if (newIndex > oldIndex && newIndex > updated.length - 1) {
      newIndex = updated.length - 1;
    }
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    state = state.copyWith(pages: updated);
  }

  void removePageAt(int index) {
    if (state.pages.length <= 1 || state.isProcessing) return;
    final updated = List<OrganizePdfPageItem>.from(state.pages)
      ..removeAt(index);
    state = state.copyWith(pages: updated);
  }

  void resetOrder() {
    if (_originalPages.isEmpty || state.isProcessing) return;
    state = state.copyWith(
      pages: List<OrganizePdfPageItem>.from(_originalPages),
      statusMessage: 'Orden y rotación restablecidos.',
    );
  }

  void clear() {
    _originalPages = const [];
    state = state.copyWith(
      clearSource: true,
      pages: const [],
    );
  }

  Future<void> organizeAndExport() async {
    if (state.sourcePdfPath == null ||
        state.pages.isEmpty ||
        state.isProcessing) {
      return;
    }

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(organizePdfServiceProvider);

    _currentSessionId = 'orgpdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(state.sourcePdfPath!);
    final tempOut = p.join(sessionDir.path, '${baseName}_organizado.pdf');

    state = state.copyWith(
      isProcessing: true,
      progress: 0.05,
      statusMessage: 'Reorganizando páginas vectoriales...',
    );

    _subscription = service
        .organizePdf(
          OrganizePdfConfig(
            sourcePdfPath: state.sourcePdfPath!,
            outputPdfPath: tempOut,
            pages: state.pages,
          ),
        )
        .listen((event) async {
      if (event.errorMessage != null) {
        state = state.copyWith(
          isProcessing: false,
          progress: 0.0,
          errorMessage: event.errorMessage,
        );
        await _cleanupSession();
        return;
      }

      if (event.isCompleted && event.outputPdfPath != null) {
        await _exportResult(event.outputPdfPath!, '${baseName}_organizado.pdf');
        return;
      }

      state = state.copyWith(
        isProcessing: true,
        progress: event.progress,
        statusMessage: event.statusMessage,
      );
    });
  }

  Future<void> _exportResult(String tempPath, String suggestedName) async {
    try {
      final savedUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar PDF organizado (LocalConvert)',
        fileName: suggestedName,
        sourceFilePath: tempPath,
      );
      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        statusMessage: savedUri != null
            ? 'PDF guardado con éxito (${state.pages.length} páginas).'
            : 'Exportación cancelada.',
      );
    } finally {
      await _cleanupSession();
    }
  }

  void cancelProcess() {
    _subscription?.cancel();
    ref.read(organizePdfServiceProvider).cancel();
    _cleanupSession();
    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Operación cancelada. Sandbox limpio.',
    );
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final organizePdfNotifierProvider =
    NotifierProvider<OrganizePdfNotifier, OrganizePdfState>(
  OrganizePdfNotifier.new,
);
