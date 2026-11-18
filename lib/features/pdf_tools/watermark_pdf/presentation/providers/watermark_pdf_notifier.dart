import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../../core/utils/pdf_font_asset_loader.dart';
import '../../../images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/watermark_pdf_service.dart';
import '../../domain/watermark_pdf_config.dart';

final watermarkPdfServiceProvider =
    Provider.autoDispose<WatermarkPdfService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  return WatermarkPdfService(sandboxCleaner: cleaner);
});

class WatermarkPdfState {
  final String? sourcePdfPath;
  final WatermarkType type;
  final String text;
  final String? watermarkImagePath;
  final double fontSize;
  final double opacity;
  final double rotationDegrees;
  final double scale;
  final WatermarkPosition position;
  final int colorHex;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const WatermarkPdfState({
    this.sourcePdfPath,
    this.type = WatermarkType.text,
    this.text = 'CONFIDENCIAL • LocalConvert',
    this.watermarkImagePath,
    this.fontSize = 40.0,
    this.opacity = 0.28,
    this.rotationDegrees = -45.0,
    this.scale = 0.45,
    this.position = WatermarkPosition.center,
    this.colorHex = 0xFFDC2626,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  WatermarkPdfState copyWith({
    String? sourcePdfPath,
    bool clearSource = false,
    WatermarkType? type,
    String? text,
    String? watermarkImagePath,
    bool clearWatermarkImage = false,
    double? fontSize,
    double? opacity,
    double? rotationDegrees,
    double? scale,
    WatermarkPosition? position,
    int? colorHex,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return WatermarkPdfState(
      sourcePdfPath:
          clearSource ? null : (sourcePdfPath ?? this.sourcePdfPath),
      type: type ?? this.type,
      text: text ?? this.text,
      watermarkImagePath: clearWatermarkImage
          ? null
          : (watermarkImagePath ?? this.watermarkImagePath),
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      scale: scale ?? this.scale,
      position: position ?? this.position,
      colorHex: colorHex ?? this.colorHex,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class WatermarkPdfNotifier extends Notifier<WatermarkPdfState> {
  String? _currentSessionId;

  @override
  WatermarkPdfState build() {
    ref.onDispose(_cleanupSession);
    return const WatermarkPdfState();
  }

  void loadPdfFile(String filePath) {
    if (p.extension(filePath).toLowerCase() != '.pdf') return;
    if (!File(filePath).existsSync()) return;
    state = state.copyWith(
      sourcePdfPath: filePath,
      statusMessage:
          'PDF "${p.basename(filePath)}" listo para estampar marca de agua.',
    );
  }

  void setWatermarkImage(String imagePath) {
    if (!File(imagePath).existsSync()) return;
    state = state.copyWith(
      type: WatermarkType.image,
      watermarkImagePath: imagePath,
    );
  }

  void clear() {
    state = state.copyWith(clearSource: true, clearWatermarkImage: true);
  }

  void updateConfig({
    WatermarkType? type,
    String? text,
    double? fontSize,
    double? opacity,
    double? rotationDegrees,
    double? scale,
    WatermarkPosition? position,
    int? colorHex,
  }) {
    state = state.copyWith(
      type: type,
      text: text,
      fontSize: fontSize,
      opacity: opacity,
      rotationDegrees: rotationDegrees,
      scale: scale,
      position: position,
      colorHex: colorHex,
    );
  }

  Future<void> applyAndExport() async {
    if (state.sourcePdfPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(watermarkPdfServiceProvider);

    _currentSessionId = 'wmpdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(state.sourcePdfPath!);
    final fileName = '${baseName}_marca_agua.pdf';
    final tempOut = p.join(sessionDir.path, fileName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.35,
      statusMessage: 'Estampando marca de agua en Isolate...',
    );

    try {
      final fonts = await PdfFontAssetLoader.loadBundledFonts();
      final outPath = await service.applyWatermark(
        WatermarkPdfConfig(
          sourcePdfPath: state.sourcePdfPath!,
          outputPdfPath: tempOut,
          type: state.type,
          text: state.text,
          watermarkImagePath: state.watermarkImagePath,
          fontSize: state.fontSize,
          opacity: state.opacity,
          rotationDegrees: state.rotationDegrees,
          scale: state.scale,
          position: state.position,
          colorHex: state.colorHex,
          fontBundle: fonts,
        ),
      );

      final savedUri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar PDF con marca de agua (LocalConvert)',
        fileName: fileName,
        sourceFilePath: outPath,
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        statusMessage: savedUri != null
            ? 'Marca de agua aplicada y guardada correctamente.'
            : 'Guardado cancelado.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'Error al aplicar marca de agua: $e',
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

final watermarkPdfNotifierProvider =
    NotifierProvider<WatermarkPdfNotifier, WatermarkPdfState>(
  WatermarkPdfNotifier.new,
);
