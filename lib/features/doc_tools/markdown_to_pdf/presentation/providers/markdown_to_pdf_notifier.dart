import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/markdown_to_pdf_isolate_service.dart';
import '../../domain/markdown_to_pdf_config.dart';

final markdownToPdfServiceProvider =
    Provider.autoDispose<MarkdownToPdfIsolateService>((ref) {
  return MarkdownToPdfIsolateService();
});

class MarkdownToPdfState {
  final String? selectedFilePath;
  final String content;
  final bool isMarkdown;
  final PdfPageSizeOption pageSize;
  final PdfMarginOption margin;
  final DocFontScaleOption fontScale;
  final bool showPageNumbers;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const MarkdownToPdfState({
    this.selectedFilePath,
    this.content = '',
    this.isMarkdown = true,
    this.pageSize = PdfPageSizeOption.a4,
    this.margin = PdfMarginOption.large,
    this.fontScale = DocFontScaleOption.normal,
    this.showPageNumbers = true,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  MarkdownToPdfState copyWith({
    String? selectedFilePath,
    bool clearSelectedFile = false,
    String? content,
    bool? isMarkdown,
    PdfPageSizeOption? pageSize,
    PdfMarginOption? margin,
    DocFontScaleOption? fontScale,
    bool? showPageNumbers,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return MarkdownToPdfState(
      selectedFilePath: clearSelectedFile
          ? null
          : (selectedFilePath ?? this.selectedFilePath),
      content: content ?? this.content,
      isMarkdown: isMarkdown ?? this.isMarkdown,
      pageSize: pageSize ?? this.pageSize,
      margin: margin ?? this.margin,
      fontScale: fontScale ?? this.fontScale,
      showPageNumbers: showPageNumbers ?? this.showPageNumbers,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class MarkdownToPdfNotifier extends Notifier<MarkdownToPdfState> {
  String? _currentSessionId;

  @override
  MarkdownToPdfState build() {
    ref.onDispose(_cleanupActiveSession);
    return const MarkdownToPdfState();
  }

  Future<void> loadDocumentFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext != '.md' && ext != '.markdown' && ext != '.txt') return;

    try {
      final raw = await File(filePath).readAsString();
      state = state.copyWith(
        selectedFilePath: filePath,
        content: raw,
        isMarkdown: ext == '.md' || ext == '.markdown',
        statusMessage: 'Archivo "${p.basename(filePath)}" cargado en memoria.',
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'No se pudo leer el archivo de texto: $e',
      );
    }
  }

  void updateTextContent(String newContent) {
    state = state.copyWith(content: newContent);
  }

  void clearFile() {
    state = state.copyWith(
      clearSelectedFile: true,
      content: '',
    );
  }

  void updateSettings({
    bool? isMarkdown,
    PdfPageSizeOption? pageSize,
    PdfMarginOption? margin,
    DocFontScaleOption? fontScale,
    bool? showPageNumbers,
  }) {
    state = state.copyWith(
      isMarkdown: isMarkdown,
      pageSize: pageSize,
      margin: margin,
      fontScale: fontScale,
      showPageNumbers: showPageNumbers,
    );
  }

  Future<void> convertAndExport() async {
    if (state.content.trim().isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(markdownToPdfServiceProvider);

    _currentSessionId = 'md2pdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final tempPdfPath = p.join(sessionDir.path, 'doc_compiled.pdf');

    state = state.copyWith(
      isProcessing: true,
      progress: 0.45,
      statusMessage:
          'Compilando ${state.isMarkdown ? "AST Markdown" : "Texto"} a PDF en Isolate...',
    );

    try {
      final baseTitle = state.selectedFilePath != null
          ? p.basenameWithoutExtension(state.selectedFilePath!)
          : 'Documento_LocalConvert';

      final fontBundle = await PdfFontAssetLoader.loadBundledFonts();

      final config = MarkdownToPdfConfig(
        rawContent: state.content,
        documentTitle: baseTitle,
        isMarkdown: state.isMarkdown,
        outputPdfPath: tempPdfPath,
        pageSize: state.pageSize,
        margin: state.margin,
        fontScale: state.fontScale,
        showPageNumbers: state.showPageNumbers,
        fontBundle: fontBundle,
      );

      final outPath = await service.compileToPdfInIsolate(config);

      final saveUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar PDF Formateado',
        fileName: '$baseTitle.pdf',
        sourceFilePath: outPath,
        mimeType: 'application/pdf',
      );

      state = state.copyWith(
        isProcessing: false,
        progress: saveUri != null ? 1.0 : 0.0,
        statusMessage: saveUri != null
            ? 'Documento exportado a PDF con éxito y caché temporal limpiada.'
            : 'Exportación cancelada. Archivos temporales destruidos.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error al compilar el PDF: $e',
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

final markdownToPdfNotifierProvider =
    NotifierProvider.autoDispose<MarkdownToPdfNotifier, MarkdownToPdfState>(
  MarkdownToPdfNotifier.new,
);




