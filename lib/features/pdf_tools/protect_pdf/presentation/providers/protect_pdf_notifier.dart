import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/utils/local_file_exporter.dart';
import '../../../images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/protect_pdf_service.dart';
import '../../domain/protect_pdf_config.dart';

final protectPdfServiceProvider =
    Provider.autoDispose<ProtectPdfService>((ref) {
  final cleaner = ref.watch(sandboxCleanerProvider);
  return ProtectPdfService(sandboxCleaner: cleaner);
});

class ProtectPdfState {
  final String? sourcePdfPath;
  final ProtectPdfMode mode;
  final String userPassword;
  final String ownerPassword;
  final String currentPassword;
  final PdfCipherLevel cipherLevel;
  final bool allowPrint;
  final bool allowCopy;
  final bool allowEdit;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const ProtectPdfState({
    this.sourcePdfPath,
    this.mode = ProtectPdfMode.encrypt,
    this.userPassword = '',
    this.ownerPassword = '',
    this.currentPassword = '',
    this.cipherLevel = PdfCipherLevel.aes128,
    this.allowPrint = true,
    this.allowCopy = false,
    this.allowEdit = false,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  ProtectPdfState copyWith({
    String? sourcePdfPath,
    bool clearSource = false,
    ProtectPdfMode? mode,
    String? userPassword,
    String? ownerPassword,
    String? currentPassword,
    PdfCipherLevel? cipherLevel,
    bool? allowPrint,
    bool? allowCopy,
    bool? allowEdit,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return ProtectPdfState(
      sourcePdfPath:
          clearSource ? null : (sourcePdfPath ?? this.sourcePdfPath),
      mode: mode ?? this.mode,
      userPassword: userPassword ?? this.userPassword,
      ownerPassword: ownerPassword ?? this.ownerPassword,
      currentPassword: currentPassword ?? this.currentPassword,
      cipherLevel: cipherLevel ?? this.cipherLevel,
      allowPrint: allowPrint ?? this.allowPrint,
      allowCopy: allowCopy ?? this.allowCopy,
      allowEdit: allowEdit ?? this.allowEdit,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class ProtectPdfNotifier extends Notifier<ProtectPdfState> {
  String? _currentSessionId;

  @override
  ProtectPdfState build() {
    ref.onDispose(_cleanupSession);
    return const ProtectPdfState();
  }

  void loadPdfFile(String filePath) {
    if (p.extension(filePath).toLowerCase() != '.pdf') return;
    if (!File(filePath).existsSync()) return;
    state = state.copyWith(
      sourcePdfPath: filePath,
      statusMessage: 'PDF "${p.basename(filePath)}" listo para configurar seguridad.',
    );
  }

  void clear() {
    state = state.copyWith(clearSource: true);
  }

  void updateConfig({
    ProtectPdfMode? mode,
    String? userPassword,
    String? ownerPassword,
    String? currentPassword,
    PdfCipherLevel? cipherLevel,
    bool? allowPrint,
    bool? allowCopy,
    bool? allowEdit,
  }) {
    state = state.copyWith(
      mode: mode,
      userPassword: userPassword,
      ownerPassword: ownerPassword,
      currentPassword: currentPassword,
      cipherLevel: cipherLevel,
      allowPrint: allowPrint,
      allowCopy: allowCopy,
      allowEdit: allowEdit,
    );
  }

  Future<void> processAndExport() async {
    if (state.sourcePdfPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(protectPdfServiceProvider);

    _currentSessionId = 'protectpdf_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(state.sourcePdfPath!);
    final suffix =
        state.mode == ProtectPdfMode.encrypt ? 'protegido' : 'desbloqueado';
    final fileName = '${baseName}_$suffix.pdf';
    final tempOut = p.join(sessionDir.path, fileName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.35,
      statusMessage: state.mode == ProtectPdfMode.encrypt
          ? 'Cifrando documento PDF localmente...'
          : 'Desbloqueando restricciones del PDF...',
    );

    try {
      final outPath = await service.processPdf(
        ProtectPdfConfig(
          sourcePdfPath: state.sourcePdfPath!,
          outputPdfPath: tempOut,
          mode: state.mode,
          userPassword: state.userPassword,
          ownerPassword: state.ownerPassword,
          currentPassword: state.currentPassword,
          cipherLevel: state.cipherLevel,
          allowPrint: state.allowPrint,
          allowCopy: state.allowCopy,
          allowEdit: state.allowEdit,
        ),
      );

      final savedUri = await LocalFileExporter.saveTempFile(
        dialogTitle: state.mode == ProtectPdfMode.encrypt
            ? 'Guardar PDF protegido (LocalConvert)'
            : 'Guardar PDF desbloqueado (LocalConvert)',
        fileName: fileName,
        sourceFilePath: outPath,
      );

      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        statusMessage: savedUri != null
            ? 'PDF $suffix y guardado correctamente.'
            : 'Guardado cancelado.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        progress: 0.0,
        errorMessage: 'No se pudo procesar el PDF (verifica la contraseña): $e',
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

final protectPdfNotifierProvider =
    NotifierProvider<ProtectPdfNotifier, ProtectPdfState>(
  ProtectPdfNotifier.new,
);
