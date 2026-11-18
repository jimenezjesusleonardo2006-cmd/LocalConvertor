/// Modo de operación de seguridad sobre el PDF.
enum ProtectPdfMode {
  encrypt('Proteger con Contraseña'),
  unlock('Desbloquear PDF');

  final String label;
  const ProtectPdfMode(this.label);
}

/// Algoritmo criptográfico de protección del PDF.
enum PdfCipherLevel {
  aes128('AES 128-bit (Estándar compatible)'),
  aes256('AES 256-bit (Alta seguridad)'),
  rc4_128('RC4 128-bit (Lectores clásicos)');

  final String label;
  const PdfCipherLevel(this.label);
}

/// Configuración enviada al [Isolate] de cifrado/desbloqueo de PDFs.
class ProtectPdfConfig {
  final String sourcePdfPath;
  final String outputPdfPath;
  final ProtectPdfMode mode;
  final String userPassword;
  final String ownerPassword;
  final String currentPassword;
  final PdfCipherLevel cipherLevel;
  final bool allowPrint;
  final bool allowCopy;
  final bool allowEdit;

  const ProtectPdfConfig({
    required this.sourcePdfPath,
    required this.outputPdfPath,
    this.mode = ProtectPdfMode.encrypt,
    this.userPassword = '',
    this.ownerPassword = '',
    this.currentPassword = '',
    this.cipherLevel = PdfCipherLevel.aes128,
    this.allowPrint = true,
    this.allowCopy = false,
    this.allowEdit = false,
  });
}
