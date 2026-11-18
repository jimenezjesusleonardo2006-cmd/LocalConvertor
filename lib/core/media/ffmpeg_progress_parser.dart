/// Utilidades puras en Dart para analizar la salida `stderr` de FFmpeg y marcas de tiempo.
class FfmpegProgressParser {
  const FfmpegProgressParser._();

  static final RegExp _durationRegex = RegExp(
    r'Duration:\s*(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)',
  );
  static final RegExp _timeRegex = RegExp(
    r'time=\s*(\d{2}):(\d{2}):(\d{2}(?:\.\d+)?)',
  );

  /// Extrae la duración total del archivo desde la salida `stderr` de FFmpeg.
  static Duration? parseDuration(String text) {
    final match = _durationRegex.firstMatch(text);
    if (match == null) return null;
    return _matchToDuration(match);
  }

  /// Extrae la última marca de tiempo procesada (`time=HH:MM:SS.xx`) en `stderr`.
  static Duration? parseCurrentTime(String text) {
    final matches = _timeRegex.allMatches(text);
    if (matches.isEmpty) return null;
    return _matchToDuration(matches.last);
  }

  /// Calcula el porcentaje determinista (`0.0` a `0.99`) durante transcodificación.
  static double computeProgress(Duration current, Duration? total) {
    if (total == null || total.inMilliseconds <= 0) return 0.0;
    return (current.inMilliseconds / total.inMilliseconds).clamp(0.0, 0.99);
  }

  /// Parsea una marca de tiempo ingresada por el usuario (`"90"`, `"01:30"`, `"00:01:30.5"`).
  static Duration? parseUserTimestamp(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final parts = trimmed.split(':');
    if (parts.length == 1) {
      final secs = double.tryParse(parts[0]);
      if (secs == null || secs < 0) return null;
      return Duration(milliseconds: (secs * 1000).round());
    }
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]);
      final secs = double.tryParse(parts[1]);
      if (mins == null || secs == null || mins < 0 || secs < 0) return null;
      return Duration(
        milliseconds: (mins * 60000 + secs * 1000).round(),
      );
    }
    if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]);
      final mins = int.tryParse(parts[1]);
      final secs = double.tryParse(parts[2]);
      if (hrs == null ||
          mins == null ||
          secs == null ||
          hrs < 0 ||
          mins < 0 ||
          secs < 0) {
        return null;
      }
      return Duration(
        milliseconds: (hrs * 3600000 + mins * 60000 + secs * 1000).round(),
      );
    }
    return null;
  }

  /// Formatea una duración en formato legible (`HH:MM:SS` o `MM:SS`).
  static String formatDuration(Duration d) {
    final totalSecs = d.inSeconds;
    final hrs = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    final mm = mins.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    if (hrs > 0) {
      return '${hrs.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  /// Convierte [Duration] al formato exacto esperado por `-ss` / `-to` de FFmpeg.
  static String toFfmpegTimestamp(Duration d) {
    final totalMs = d.inMilliseconds;
    final hrs = totalMs ~/ 3600000;
    final mins = (totalMs % 3600000) ~/ 60000;
    final secs = ((totalMs % 60000) / 1000.0).toStringAsFixed(3);
    final paddedSecs = secs.indexOf('.') == 1 ? '0$secs' : secs;
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:$paddedSecs';
  }

  static Duration? _matchToDuration(RegExpMatch match) {
    final hrs = int.tryParse(match.group(1)!) ?? 0;
    final mins = int.tryParse(match.group(2)!) ?? 0;
    final secs = double.tryParse(match.group(3)!) ?? 0.0;
    return Duration(
      milliseconds: (hrs * 3600000 + mins * 60000 + secs * 1000).round(),
    );
  }
}
