import 'dart:io';
import 'dart:isolate';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/protect_pdf_config.dart';

/// Servicio local 100% offline para cifrar o desbloquear documentos PDF en un [Isolate].
class ProtectPdfService {
  final SandboxCleanerService _sandboxCleaner;

  ProtectPdfService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  Future<String> processPdf(ProtectPdfConfig config) async {
    try {
      final sourceFile = File(config.sourcePdfPath);
      if (!await sourceFile.exists()) {
        throw FileSystemException(
          'El archivo PDF de origen no existe',
          config.sourcePdfPath,
        );
      }

      if (config.mode == ProtectPdfMode.encrypt &&
          config.userPassword.isEmpty &&
          config.ownerPassword.isEmpty) {
        throw const FormatException(
          'Ingresa al menos una contraseña de apertura o de propietario.',
        );
      }

      await Isolate.run(() => _runInIsolate(config));
      return config.outputPdfPath;
    } catch (_) {
      await _sandboxCleaner.deleteTempFile(config.outputPdfPath);
      rethrow;
    }
  }

  static Future<void> _runInIsolate(ProtectPdfConfig config) async {
    final bytes = await File(config.sourcePdfPath).readAsBytes();
    final password =
        config.currentPassword.isEmpty ? null : config.currentPassword;
    final doc = sfpdf.PdfDocument(inputBytes: bytes, password: password);

    try {
      if (config.mode == ProtectPdfMode.encrypt) {
        doc.security.algorithm = switch (config.cipherLevel) {
          PdfCipherLevel.aes128 => sfpdf.PdfEncryptionAlgorithm.aesx128Bit,
          PdfCipherLevel.aes256 => sfpdf.PdfEncryptionAlgorithm.aesx256Bit,
          PdfCipherLevel.rc4_128 => sfpdf.PdfEncryptionAlgorithm.rc4x128Bit,
        };
        doc.security.userPassword = config.userPassword;
        doc.security.ownerPassword = config.ownerPassword.isNotEmpty
            ? config.ownerPassword
            : config.userPassword;

        doc.security.permissions.clear();

        final granted = <sfpdf.PdfPermissionsFlags>[];
        if (config.allowPrint) {
          granted.add(sfpdf.PdfPermissionsFlags.print);
          granted.add(sfpdf.PdfPermissionsFlags.fullQualityPrint);
        }
        if (config.allowCopy) {
          granted.add(sfpdf.PdfPermissionsFlags.copyContent);
          granted.add(sfpdf.PdfPermissionsFlags.accessibilityCopyContent);
        }
        if (config.allowEdit) {
          granted.add(sfpdf.PdfPermissionsFlags.editContent);
          granted.add(sfpdf.PdfPermissionsFlags.editAnnotations);
          granted.add(sfpdf.PdfPermissionsFlags.assembleDocument);
        }
        if (granted.isNotEmpty) {
          doc.security.permissions.addAll(granted);
        }
      } else {
        doc.security.userPassword = '';
        doc.security.ownerPassword = '';
      }

      final outBytes = await doc.save();
      final outFile = File(config.outputPdfPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(outBytes, flush: true);
    } finally {
      doc.dispose();
    }
  }
}
