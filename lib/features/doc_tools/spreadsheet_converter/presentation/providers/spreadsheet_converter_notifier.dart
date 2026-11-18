import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/spreadsheet_converter_service.dart';
import '../../domain/spreadsheet_converter_config.dart';

final spreadsheetConverterServiceProvider =
    Provider.autoDispose<SpreadsheetConverterService>((ref) {
  return SpreadsheetConverterService();
});

class SpreadsheetConverterState {
  final String? selectedFilePath;
  final List<String> sheetNames;
  final String? selectedSheet;
  final int rowCount;
  final int colCount;
  final List<List<String>> previewRows;
  final SpreadsheetOutputFormat targetFormat;
  final String csvDelimiter;
  final PdfPageSizeOption pageSize;
  final PdfPageOrientationOption orientation;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const SpreadsheetConverterState({
    this.selectedFilePath,
    this.sheetNames = const [],
    this.selectedSheet,
    this.rowCount = 0,
    this.colCount = 0,
    this.previewRows = const [],
    this.targetFormat = SpreadsheetOutputFormat.csv,
    this.csvDelimiter = ',',
    this.pageSize = PdfPageSizeOption.a4,
    this.orientation = PdfPageOrientationOption.landscape,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  SpreadsheetConverterState copyWith({
    String? selectedFilePath,
    bool clearFilePath = false,
    List<String>? sheetNames,
    String? selectedSheet,
    bool clearSheet = false,
    int? rowCount,
    int? colCount,
    List<List<String>>? previewRows,
    SpreadsheetOutputFormat? targetFormat,
    String? csvDelimiter,
    PdfPageSizeOption? pageSize,
    PdfPageOrientationOption? orientation,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return SpreadsheetConverterState(
      selectedFilePath:
          clearFilePath ? null : (selectedFilePath ?? this.selectedFilePath),
      sheetNames: sheetNames ?? this.sheetNames,
      selectedSheet: clearSheet ? null : (selectedSheet ?? this.selectedSheet),
      rowCount: rowCount ?? this.rowCount,
      colCount: colCount ?? this.colCount,
      previewRows: previewRows ?? this.previewRows,
      targetFormat: targetFormat ?? this.targetFormat,
      csvDelimiter: csvDelimiter ?? this.csvDelimiter,
      pageSize: pageSize ?? this.pageSize,
      orientation: orientation ?? this.orientation,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class SpreadsheetConverterNotifier extends Notifier<SpreadsheetConverterState> {
  String? _currentSessionId;

  @override
  SpreadsheetConverterState build() {
    ref.onDispose(_cleanupSession);
    return const SpreadsheetConverterState();
  }

  Future<void> loadWorkbook(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (!{'.xlsx', '.xls', '.ods', '.xlsm', '.xlsb'}.contains(ext)) return;
    if (!await File(filePath).exists()) return;

    state = state.copyWith(
      selectedFilePath: filePath,
      isProcessing: true,
      progress: 0.3,
      statusMessage: 'Analizando hojas de "${p.basename(filePath)}" en Rust...',
    );

    try {
      final info = await ref
          .read(spreadsheetConverterServiceProvider)
          .inspectWorkbook(filePath);
      state = state.copyWith(
        sheetNames: info.sheetNames,
        selectedSheet: info.activeSheet,
        rowCount: info.rowCount,
        colCount: info.colCount,
        previewRows: info.previewRows,
        isProcessing: false,
        progress: 0.0,
        statusMessage:
            'Libro cargado (${info.sheetNames.length} hoja(s), ${info.rowCount} filas × ${info.colCount} columnas).',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'No se pudo analizar la hoja de cálculo: $e',
      );
    }
  }

  Future<void> selectSheet(String sheetName) async {
    final filePath = state.selectedFilePath;
    if (filePath == null) return;
    try {
      final info = await ref
          .read(spreadsheetConverterServiceProvider)
          .inspectWorkbook(filePath, sheetName: sheetName);
      state = state.copyWith(
        selectedSheet: info.activeSheet,
        rowCount: info.rowCount,
        colCount: info.colCount,
        previewRows: info.previewRows,
        statusMessage:
            'Hoja "${info.activeSheet}": ${info.rowCount} filas × ${info.colCount} columnas.',
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error cambiando de hoja: $e');
    }
  }

  void updateSettings({
    SpreadsheetOutputFormat? targetFormat,
    String? csvDelimiter,
    PdfPageSizeOption? pageSize,
    PdfPageOrientationOption? orientation,
  }) {
    state = state.copyWith(
      targetFormat: targetFormat,
      csvDelimiter: csvDelimiter,
      pageSize: pageSize,
      orientation: orientation,
    );
  }

  void clear() {
    state = const SpreadsheetConverterState();
  }

  Future<void> convertAndExport() async {
    final srcPath = state.selectedFilePath;
    if (srcPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    _currentSessionId = 'sheet_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(srcPath);
    final ext = state.targetFormat.extension;
    final tempOut = p.join(sessionDir.path, '${baseName}_export.$ext');

    state = state.copyWith(
      isProcessing: true,
      progress: 0.45,
      statusMessage:
          'Convirtiendo hoja "${state.selectedSheet ?? ""}" a ${state.targetFormat.label} en Rust...',
    );

    try {
      final fonts = state.targetFormat == SpreadsheetOutputFormat.pdf
          ? await PdfFontAssetLoader.loadBundledFonts()
          : null;

      final res = await ref
          .read(spreadsheetConverterServiceProvider)
          .convertWorkbook(
            SpreadsheetConvertConfig(
              sourceFilePath: srcPath,
              sheetName: state.selectedSheet,
              targetFormat: state.targetFormat,
              outputFilePath: tempOut,
              csvDelimiter: state.csvDelimiter,
              pageSize: state.pageSize,
              orientation: state.orientation,
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
            ? 'Hoja "${res.sheetName}" exportada a .${ext.toUpperCase()} con éxito.'
            : 'Exportación cancelada. Archivos temporales destruidos.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error durante la conversión: $e',
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

final spreadsheetConverterNotifierProvider = NotifierProvider.autoDispose<
    SpreadsheetConverterNotifier, SpreadsheetConverterState>(
  SpreadsheetConverterNotifier.new,
);
