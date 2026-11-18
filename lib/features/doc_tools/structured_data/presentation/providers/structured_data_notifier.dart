import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/structured_data_isolate_service.dart';
import '../../domain/structured_data_config.dart';

final structuredDataIsolateServiceProvider =
    Provider.autoDispose<StructuredDataIsolateService>((ref) {
  return StructuredDataIsolateService();
});

class StructuredDataState {
  final String? selectedFilePath;
  final String inputContent;
  final StructuredDataFormat sourceFormat;
  final StructuredDataFormat targetFormat;
  final String csvDelimiter;
  final bool prettyPrint;
  final String? syntaxError;
  final String? livePreviewText;
  final int? rowCount;
  final int? columnCount;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const StructuredDataState({
    this.selectedFilePath,
    this.inputContent = '',
    this.sourceFormat = StructuredDataFormat.csv,
    this.targetFormat = StructuredDataFormat.json,
    this.csvDelimiter = ',',
    this.prettyPrint = true,
    this.syntaxError,
    this.livePreviewText,
    this.rowCount,
    this.columnCount,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  StructuredDataState copyWith({
    String? selectedFilePath,
    bool clearFilePath = false,
    String? inputContent,
    StructuredDataFormat? sourceFormat,
    StructuredDataFormat? targetFormat,
    String? csvDelimiter,
    bool? prettyPrint,
    String? syntaxError,
    bool clearSyntaxError = false,
    String? livePreviewText,
    bool clearPreview = false,
    int? rowCount,
    int? columnCount,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return StructuredDataState(
      selectedFilePath:
          clearFilePath ? null : (selectedFilePath ?? this.selectedFilePath),
      inputContent: inputContent ?? this.inputContent,
      sourceFormat: sourceFormat ?? this.sourceFormat,
      targetFormat: targetFormat ?? this.targetFormat,
      csvDelimiter: csvDelimiter ?? this.csvDelimiter,
      prettyPrint: prettyPrint ?? this.prettyPrint,
      syntaxError:
          clearSyntaxError ? null : (syntaxError ?? this.syntaxError),
      livePreviewText:
          clearPreview ? null : (livePreviewText ?? this.livePreviewText),
      rowCount: rowCount ?? this.rowCount,
      columnCount: columnCount ?? this.columnCount,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class StructuredDataNotifier extends Notifier<StructuredDataState> {
  String? _currentSessionId;

  @override
  StructuredDataState build() {
    ref.onDispose(_cleanupSession);
    return const StructuredDataState();
  }

  Future<void> loadFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    StructuredDataFormat? detected;
    if (ext == '.csv') detected = StructuredDataFormat.csv;
    if (ext == '.json') detected = StructuredDataFormat.json;
    if (ext == '.xml') detected = StructuredDataFormat.xml;
    if (detected == null) return;

    final file = File(filePath);
    if (!await file.exists()) return;

    final text = await file.readAsString();
    final nextTarget = detected == state.targetFormat
        ? (detected == StructuredDataFormat.csv
            ? StructuredDataFormat.json
            : StructuredDataFormat.csv)
        : state.targetFormat;

    updateInputContent(
      text,
      filePath: filePath,
      sourceFormat: detected,
      targetFormat: nextTarget,
    );
  }

  void loadSampleCsv() {
    const sample = 'id,nombre,ciudad,monto\n'
        '1,Ana López,Madrid,120.50\n'
        '2,Carlos Peña,Ciudad de México,89.00\n'
        '3,Lucía Núñez,Bogotá,310.75';
    updateInputContent(
      sample,
      sourceFormat: StructuredDataFormat.csv,
      targetFormat: StructuredDataFormat.json,
    );
  }

  void updateInputContent(
    String text, {
    String? filePath,
    StructuredDataFormat? sourceFormat,
    StructuredDataFormat? targetFormat,
  }) {
    final src = sourceFormat ?? state.sourceFormat;
    final tgt = targetFormat ?? state.targetFormat;
    final validation = text.trim().isEmpty
        ? null
        : StructuredDataIsolateService.validateSyntax(text, src);

    int? rowsCount;
    int? colsCount;
    if (validation == null && text.trim().isNotEmpty) {
      try {
        final parsed = StructuredDataIsolateService.parseToNormalizedRows(
          text,
          src,
          csvDelimiter: state.csvDelimiter,
        );
        rowsCount = parsed.rows.length;
        colsCount = parsed.headers.length;
      } catch (_) {}
    }

    state = state.copyWith(
      selectedFilePath: filePath ?? state.selectedFilePath,
      inputContent: text,
      sourceFormat: src,
      targetFormat: tgt,
      syntaxError: validation,
      clearSyntaxError: validation == null,
      rowCount: rowsCount,
      columnCount: colsCount,
    );
  }

  void updateSettings({
    StructuredDataFormat? sourceFormat,
    StructuredDataFormat? targetFormat,
    String? csvDelimiter,
    bool? prettyPrint,
  }) {
    final nextSrc = sourceFormat ?? state.sourceFormat;
    final nextDelim = csvDelimiter ?? state.csvDelimiter;
    final validation = state.inputContent.trim().isEmpty
        ? null
        : StructuredDataIsolateService.validateSyntax(
            state.inputContent,
            nextSrc,
          );

    state = state.copyWith(
      sourceFormat: nextSrc,
      targetFormat: targetFormat ?? state.targetFormat,
      csvDelimiter: nextDelim,
      prettyPrint: prettyPrint ?? state.prettyPrint,
      syntaxError: validation,
      clearSyntaxError: validation == null,
    );
  }

  void clear() {
    state = const StructuredDataState();
  }

  Future<void> convertAndExport() async {
    if (state.inputContent.trim().isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(structuredDataIsolateServiceProvider);

    _currentSessionId = 'sdata_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = state.selectedFilePath != null
        ? p.basenameWithoutExtension(state.selectedFilePath!)
        : 'datos_localconvert';
    final outFileName = '${baseName}_convertido.${state.targetFormat.extension}';
    final tempOut = p.join(sessionDir.path, outFileName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.35,
      statusMessage:
          'Convirtiendo ${state.sourceFormat.label} → ${state.targetFormat.label} en Isolate...',
    );

    try {
      final fonts = state.targetFormat == StructuredDataFormat.pdfTable
          ? await PdfFontAssetLoader.loadBundledFonts()
          : null;

      final result = await service.convertInIsolate(
        StructuredDataConfig(
          inputContent: state.inputContent,
          sourceFormat: state.sourceFormat,
          targetFormat: state.targetFormat,
          outputFilePath: tempOut,
          csvDelimiter: state.csvDelimiter,
          prettyPrint: state.prettyPrint,
          documentTitle: baseName,
          fontBundle: fonts,
        ),
      );

      final savedUri = await LocalFileExporter.saveBytes(
        dialogTitle:
            'Guardar ${state.targetFormat.label} convertido (LocalConvert)',
        fileName: outFileName,
        bytes: result.outputBytes,
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        livePreviewText: result.previewText,
        rowCount: result.rowCount,
        columnCount: result.columnCount,
        statusMessage: savedUri != null
            ? 'Exportado "$outFileName" (${result.rowCount} filas × ${result.columnCount} cols).'
            : 'Conversión lista (${result.rowCount} filas). Guardado cancelado.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error de sintaxis o conversión: $e',
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

final structuredDataNotifierProvider =
    NotifierProvider<StructuredDataNotifier, StructuredDataState>(
  StructuredDataNotifier.new,
);
