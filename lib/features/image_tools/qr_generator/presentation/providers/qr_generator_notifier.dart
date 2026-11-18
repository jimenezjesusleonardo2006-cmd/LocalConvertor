import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/qr_generator_service.dart';
import '../../domain/qr_generator_config.dart';

final qrGeneratorServiceProvider =
    Provider.autoDispose<QrGeneratorService>((ref) {
  return QrGeneratorService();
});

class QrGeneratorState {
  final String rawLinesText;
  final QrOutputFormat outputFormat;
  final QrErrorCorrection errorCorrection;
  final int sizePx;
  final bool packageAsZip;
  final Uint8List? previewPngBytes;
  final int? previewModules;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const QrGeneratorState({
    this.rawLinesText = 'https://localconvert.app\nLocalConvert 100% Offline',
    this.outputFormat = QrOutputFormat.png,
    this.errorCorrection = QrErrorCorrection.medium,
    this.sizePx = 512,
    this.packageAsZip = false,
    this.previewPngBytes,
    this.previewModules,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  List<String> get parsedItems => rawLinesText
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  QrGeneratorState copyWith({
    String? rawLinesText,
    QrOutputFormat? outputFormat,
    QrErrorCorrection? errorCorrection,
    int? sizePx,
    bool? packageAsZip,
    Uint8List? previewPngBytes,
    bool clearPreview = false,
    int? previewModules,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return QrGeneratorState(
      rawLinesText: rawLinesText ?? this.rawLinesText,
      outputFormat: outputFormat ?? this.outputFormat,
      errorCorrection: errorCorrection ?? this.errorCorrection,
      sizePx: sizePx ?? this.sizePx,
      packageAsZip: packageAsZip ?? this.packageAsZip,
      previewPngBytes:
          clearPreview ? null : (previewPngBytes ?? this.previewPngBytes),
      previewModules: previewModules ?? this.previewModules,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class QrGeneratorNotifier extends Notifier<QrGeneratorState> {
  String? _currentSessionId;
  int _previewToken = 0;

  @override
  QrGeneratorState build() {
    ref.onDispose(_cleanupSession);
    Future.microtask(refreshPreview);
    return const QrGeneratorState();
  }

  void updateText(String value) {
    state = state.copyWith(rawLinesText: value);
    refreshPreview();
  }

  Future<void> loadListFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (!{'.txt', '.csv'}.contains(ext)) return;
    if (!await File(filePath).exists()) return;

    final raw = await File(filePath).readAsString();
    final lines = <String>[];
    for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
      final clean = line.trim();
      if (clean.isEmpty) continue;
      if (ext == '.csv') {
        final firstCol = clean.split(',').first.trim().replaceAll('"', '');
        if (firstCol.isNotEmpty) lines.add(firstCol);
      } else {
        lines.add(clean);
      }
    }

    if (lines.isNotEmpty) {
      updateText(lines.join('\n'));
      state = state.copyWith(
        statusMessage:
            'Cargados ${lines.length} elementos desde "${p.basename(filePath)}".',
      );
    }
  }

  void updateSettings({
    QrOutputFormat? outputFormat,
    QrErrorCorrection? errorCorrection,
    int? sizePx,
    bool? packageAsZip,
  }) {
    final ecChanged =
        errorCorrection != null && errorCorrection != state.errorCorrection;
    state = state.copyWith(
      outputFormat: outputFormat,
      errorCorrection: errorCorrection,
      sizePx: sizePx,
      packageAsZip: packageAsZip,
    );
    if (ecChanged) {
      refreshPreview();
    }
  }

  Future<void> refreshPreview() async {
    final items = state.parsedItems;
    if (items.isEmpty) {
      state = state.copyWith(clearPreview: true);
      return;
    }

    final token = ++_previewToken;
    final cleaner = ref.read(sandboxCleanerProvider);
    final previewSession = 'qr_prev_${DateTime.now().microsecondsSinceEpoch}';

    try {
      final dir = await cleaner.createSessionDir(previewSession);
      final outPath = p.join(dir.path, 'preview.png');
      final res = await ref.read(qrGeneratorServiceProvider).generatePreview(
            content: items.first,
            errorCorrection: state.errorCorrection,
            outputPath: outPath,
            sizePx: 320,
          );
      if (token != _previewToken) return;
      final bytes = await File(res.previewPath).readAsBytes();
      state = state.copyWith(
        previewPngBytes: bytes,
        previewModules: res.moduleCount,
      );
    } catch (_) {
    } finally {
      await cleaner.purgeSession(previewSession);
    }
  }

  Future<void> generateAndExport() async {
    final items = state.parsedItems;
    if (items.isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    _currentSessionId = 'qr_batch_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.45,
      statusMessage:
          'Generando ${items.length} código(s) QR en Rust (${state.outputFormat.label})...',
    );

    try {
      final fonts = state.outputFormat == QrOutputFormat.pdf
          ? await PdfFontAssetLoader.loadBundledFonts()
          : null;

      final res = await ref.read(qrGeneratorServiceProvider).generateBatch(
            QrBatchConfig(
              items: items,
              sessionDirPath: sessionDir.path,
              outputFormat: state.outputFormat,
              errorCorrection: state.errorCorrection,
              sizePx: state.sizePx,
              packageAsZip: state.packageAsZip,
            ),
            fontBundle: fonts,
          );

      if (res.zipFilePath != null) {
        final saved = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar Lote de Códigos QR (.ZIP)',
          fileName: 'LocalConvert_QR_Lote.zip',
          sourceFilePath: res.zipFilePath!,
        );
        state = state.copyWith(
          isProcessing: false,
          progress: saved != null ? 1.0 : 0.0,
          statusMessage: saved != null
              ? '${res.generatedCount} códigos QR exportados en .ZIP con éxito.'
              : 'Exportación cancelada.',
        );
      } else if (res.outputFiles.isNotEmpty) {
        final single = res.outputFiles.first;
        final saved = await LocalFileExporter.saveTempFile(
          dialogTitle: 'Guardar Código QR',
          fileName: p.basename(single),
          sourceFilePath: single,
        );
        state = state.copyWith(
          isProcessing: false,
          progress: saved != null ? 1.0 : 0.0,
          statusMessage: saved != null
              ? 'Código QR (${state.outputFormat.label}) exportado con éxito.'
              : 'Exportación cancelada.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error generando códigos QR: $e',
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

final qrGeneratorNotifierProvider =
    NotifierProvider.autoDispose<QrGeneratorNotifier, QrGeneratorState>(
  QrGeneratorNotifier.new,
);
