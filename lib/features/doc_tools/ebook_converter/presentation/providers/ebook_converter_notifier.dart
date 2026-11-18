import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/ebook_converter_isolate_service.dart';
import '../../domain/ebook_converter_config.dart';

final ebookConverterIsolateServiceProvider =
    Provider.autoDispose<EbookConverterIsolateService>((ref) {
  return EbookConverterIsolateService();
});

class EbookConverterState {
  final String? selectedFilePath;
  final String? rawHtmlSample;
  final String extractedTitle;
  final int chapterCount;
  final String previewText;
  final EbookTargetFormat targetFormat;
  final double fontScale;
  final bool includePageNumbers;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const EbookConverterState({
    this.selectedFilePath,
    this.rawHtmlSample,
    this.extractedTitle = '',
    this.chapterCount = 0,
    this.previewText = '',
    this.targetFormat = EbookTargetFormat.pdf,
    this.fontScale = 1.0,
    this.includePageNumbers = true,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  bool get hasInput =>
      selectedFilePath != null ||
      (rawHtmlSample != null && rawHtmlSample!.isNotEmpty);

  EbookConverterState copyWith({
    String? selectedFilePath,
    bool clearSelectedFile = false,
    String? rawHtmlSample,
    bool clearSample = false,
    String? extractedTitle,
    int? chapterCount,
    String? previewText,
    EbookTargetFormat? targetFormat,
    double? fontScale,
    bool? includePageNumbers,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return EbookConverterState(
      selectedFilePath: clearSelectedFile
          ? null
          : (selectedFilePath ?? this.selectedFilePath),
      rawHtmlSample:
          clearSample ? null : (rawHtmlSample ?? this.rawHtmlSample),
      extractedTitle: extractedTitle ?? this.extractedTitle,
      chapterCount: chapterCount ?? this.chapterCount,
      previewText: previewText ?? this.previewText,
      targetFormat: targetFormat ?? this.targetFormat,
      fontScale: fontScale ?? this.fontScale,
      includePageNumbers: includePageNumbers ?? this.includePageNumbers,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class EbookConverterNotifier extends Notifier<EbookConverterState> {
  String? _currentSessionId;

  @override
  EbookConverterState build() {
    ref.onDispose(_cleanupSession);
    return const EbookConverterState();
  }

  Future<void> loadFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (!{'.html', '.htm', '.xhtml', '.epub'}.contains(ext)) return;
    final file = File(filePath);
    if (!await file.exists()) return;

    state = state.copyWith(
      selectedFilePath: filePath,
      clearSample: true,
      statusMessage: 'Extrayendo capítulos y texto de "${p.basename(filePath)}"...',
    );

    try {
      final parsed = await Isolate.run(() async {
        if (ext == '.epub') {
          final bytes = await File(filePath).readAsBytes();
          final r = EbookConverterIsolateService.extractFromEpubBytes(bytes);
          return (
            title: r.title,
            chapters: r.chapterCount,
            preview: EbookConverterIsolateService.blocksToCleanText(r.blocks),
          );
        } else {
          final html = await File(filePath).readAsString();
          final r = EbookConverterIsolateService.parseHtmlToBlocks(html);
          return (
            title: r.title,
            chapters: 1,
            preview: EbookConverterIsolateService.blocksToCleanText(r.blocks),
          );
        }
      });

      state = state.copyWith(
        extractedTitle: parsed.title,
        chapterCount: parsed.chapters,
        previewText: parsed.preview,
        statusMessage:
            'Extraídos ${parsed.chapters} capítulo(s) (${parsed.preview.length} caracteres).',
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Error al analizar HTML/EPUB: $e',
      );
    }
  }

  void loadSampleHtml() {
    const sample = '''
<html>
  <head><title>Guía Rápida LocalConvert</title></head>
  <body>
    <h1>Procesamiento Editorial 100% Offline</h1>
    <p>Este documento HTML demuestra la extracción local de capítulos, listas y citas sin usar servidores externos.</p>
    <h2>Ventajas Principales</h2>
    <ul>
      <li>Soporte nativo Unicode: ñ, á, €, —</li>
      <li>Exportación directa a PDF paginado o TXT limpio</li>
    </ul>
    <blockquote>La privacidad del usuario comienza procesando todo en su propio dispositivo.</blockquote>
  </body>
</html>''';
    final parsed = EbookConverterIsolateService.parseHtmlToBlocks(sample);
    final text = EbookConverterIsolateService.blocksToCleanText(parsed.blocks);
    state = state.copyWith(
      clearSelectedFile: true,
      rawHtmlSample: sample,
      extractedTitle: parsed.title,
      chapterCount: 1,
      previewText: text,
      statusMessage: 'Ejemplo HTML cargado (${text.length} caracteres).',
    );
  }

  void clear() {
    state = const EbookConverterState();
  }

  void updateSettings({
    EbookTargetFormat? targetFormat,
    double? fontScale,
    bool? includePageNumbers,
  }) {
    state = state.copyWith(
      targetFormat: targetFormat,
      fontScale: fontScale,
      includePageNumbers: includePageNumbers,
    );
  }

  Future<void> convertAndExport() async {
    if (!state.hasInput || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(ebookConverterIsolateServiceProvider);

    _currentSessionId = 'ebook_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = state.selectedFilePath != null
        ? p.basenameWithoutExtension(state.selectedFilePath!)
        : 'documento_editorial';
    final outName = '$baseName.${state.targetFormat.extension}';
    final tempOut = p.join(sessionDir.path, outName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.35,
      statusMessage:
          'Compilando a .${state.targetFormat.extension.toUpperCase()} en Isolate...',
    );

    try {
      final fonts = state.targetFormat == EbookTargetFormat.pdf
          ? await PdfFontAssetLoader.loadBundledFonts()
          : null;

      final result = await service.convertInIsolate(
        EbookConverterConfig(
          sourceFilePath: state.selectedFilePath,
          rawHtmlOverride: state.rawHtmlSample,
          targetFormat: state.targetFormat,
          outputFilePath: tempOut,
          fontScale: state.fontScale,
          includePageNumbers: state.includePageNumbers,
          fontBundle: fonts,
        ),
      );

      final savedUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar documento convertido (LocalConvert)',
        fileName: outName,
        sourceFilePath: result.outputFilePath,
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        statusMessage: savedUri != null
            ? 'Exportado "$outName" (${result.chapterCount} cap., ${result.characterCount} caracteres).'
            : 'Guardado cancelado.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error durante la conversión HTML/EPUB: $e',
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

final ebookConverterNotifierProvider =
    NotifierProvider<EbookConverterNotifier, EbookConverterState>(
  EbookConverterNotifier.new,
);
