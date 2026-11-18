import 'dart:io';
import 'package:path/path.dart' as p;

/// Resuelve las rutas de los ejecutables empaquetados `ffmpeg.exe` y
/// `ffprobe.exe` junto al binario principal en Windows, o usa el fallback
/// del `PATH` en otros entornos.
class FfmpegBinaryResolver {
  static String get ffmpegPath =>
      _resolveWindowsBinary('ffmpeg.exe', fallback: 'ffmpeg');
  static String get ffprobePath =>
      _resolveWindowsBinary('ffprobe.exe', fallback: 'ffprobe');

  static String _resolveWindowsBinary(
    String fileName, {
    required String fallback,
  }) {
    if (!Platform.isWindows) return fallback;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final bundledBinary = File(p.join(exeDir, fileName));

    if (bundledBinary.existsSync()) {
      return bundledBinary.path;
    }
    return fallback;
  }
}
