import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../../markdown_to_pdf/domain/markdown_to_pdf_config.dart';
import '../../data/docx_converter_service.dart';
import '../../domain/docx_converter_config.dart';

final docxConverterServiceProvider =
    Provider.autoDispose<DocxConverterService>((ref) {
  return DocxConverterService();
});

class DocxConverterState {
  final String? selectedFilePath;
  final int paragraphCount;
  final int tableCount;
  final String previewMarkdown;
  final DocxOutputFormat targetFormat;
  final PdfPageSizeOption pageSize;
  final PdfMarginOption margin;
  final DocFontScaleOption fontScale;
  final bool showPageNumbers;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const DocxConverterState({
    this.selectedFilePath,
    this.paragraphCount = 0,
    this.tableCount = 0,
    this.previewMarkdown = '',
    this.targetFormat = DocxOutputFormat.pdf,
    this.pageSize = PdfPageSizeOption.a4,
    this.margin = PdfMarginOption.large,
    this.fontScale = DocFontScaleOption.normal,
    this.showPageNumbers = true,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  DocxConverterState copyWith({
    String? selectedFilePath,
    bool clearFilePath = false,
    int? paragraphCount,
    int? tableCount,
    String? previewMarkdown,
    DocxOutputFormat? targetFormat,
    PdfPageSizeOption? pageSize,
    PdfMarginOption? margin,
    DocFontScaleOption? fontScale,
    bool? showPageNumbers,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return DocxConverterState(
      selectedFilePath:
          clearFilePath ? null : (selectedFilePath ?? this.selectedFilePath),
      paragraphCount: paragraphCount ?? this.paragraphCount,
      tableCount: tableCount ?? this.tableCount,
      previewMarkdown: previewMarkdown ?? this.previewMarkdown,
      targetFormat: targetFormat ?? this.targetFormat,
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

class DocxConverterNotifier extends Notifier<DocxConverterState> {
  String? _currentSessionId;

  @override
  DocxConverterState build() {
    ref.onDispose(_cleanupSession);
    return const DocxConverterState();
  }

  Future<void> loadDocxFile(String filePath) async {
    if (p.extension(filePath).toLowerCase() != '.docx') return;
    if (!await File(filePath).exists()) return;

    state = state.copyWith(
      selectedFilePath: filePath,
      isProcessing: true,
      progress: 0.35,
      statusMessage: 'Analizando "${p.basename(filePath)}" en Rust...',
    );

    try {
      final info = await ref
          .read(docxConverterServiceProvider)
          .inspectDocument(filePath);
      state = state.copyWith(
        paragraphCount: info.paragraphCount,
        tableCount: info.tableCount,
        previewMarkdown: info.previewMarkdown,
        isProcessing: false,
        progress: 0.0,
        statusMessage:
            'DOCX analizado (${info.paragraphCount} párrafos, ${info.tableCount} tabla(s)).',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'No se pudo leer el archivo .docx: $e',
      );
    }
  }

  void updateSettings({
    DocxOutputFormat? targetFormat,
    PdfPageSizeOption? pageSize,
    PdfMarginOption? margin,
    DocFontScaleOption? fontScale,
    bool? showPageNumbers,
  }) {
    state = state.copyWith(
      targetFormat: targetFormat,
      pageSize: pageSize,
      margin: margin,
      fontScale: fontScale,
      showPageNumbers: showPageNumbers,
    );
  }

  void clear() {
    state = const DocxConverterState();
  }

  Future<void> convertAndExport() async {
    final srcPath = state.selectedFilePath;
    if (srcPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    _currentSessionId = 'docx_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(srcPath);
    final ext = state.targetFormat.extension;
    final tempOut = p.join(sessionDir.path, '${baseName}_export.$ext');

    state = state.copyWith(
      isProcessing: true,
      progress: 0.45,
      statusMessage:
          'Convirtiendo DOCX a ${state.targetFormat.label} en Rust...',
    );

    try {
      final fonts = state.targetFormat == DocxOutputFormat.pdf
          ? await PdfFontAssetLoader.loadBundledFonts()
          : null;

      final res = await ref.read(docxConverterServiceProvider).convertDocument(
            DocxConvertConfig(
              sourceFilePath: srcPath,
              targetFormat: state.targetFormat,
              outputFilePath: tempOut,
              pageSize: state.pageSize,
              margin: state.margin,
              fontScale: state.fontScale,
              showPageNumbers: state.showPageNumbers,
            ),
            fontBundle: fonts,
          );

      final saved = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Exportar ${state.targetFormat.label}',
        fileName: '$baseName.$ext',
        sourceFilePath: res.outputFilePath,
      );

      state = state.copyWith(
        isProcessing: false,
        progress: saved != null ? 1.0 : 0.0,
        statusMessage: saved != null
            ? 'Documento exportado a .${ext.toUpperCase()} con éxito.'
            : 'Exportación cancelada. Archivos temporales destruidos.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error durante la conversión de DOCX: $e',
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

final docxConverterNotifierProvider =
    NotifierProvider.autoDispose<DocxConverterNotifier, DocxConverterState>(
  DocxConverterNotifier.new,
);
