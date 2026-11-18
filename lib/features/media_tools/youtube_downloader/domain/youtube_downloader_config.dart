/// Validador y extractor puro en Dart de enlaces e identificadores de YouTube.
class YoutubeUrlValidator {
  const YoutubeUrlValidator._();

  static final RegExp _idRegex = RegExp(r'^[a-zA-Z0-9_-]{11}$');

  /// Extrae el ID de 11 caracteres de una URL de YouTube (`watch?v=`, `youtu.be/`,
  /// `shorts/`, `embed/`, `live/`) o devuelve `null` si el enlace no es válido.
  static String? extractVideoId(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;
    if (_idRegex.hasMatch(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;

    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      final seg = uri.pathSegments.firstOrNull;
      if (seg != null && _idRegex.hasMatch(seg)) return seg;
      return null;
    }

    if (host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com')) {
      final vParam = uri.queryParameters['v'];
      if (vParam != null && _idRegex.hasMatch(vParam)) {
        return vParam;
      }

      if (uri.pathSegments.length >= 2) {
        final prefix = uri.pathSegments[0].toLowerCase();
        final candidate = uri.pathSegments[1];
        if (const {'shorts', 'embed', 'live', 'v'}.contains(prefix) &&
            _idRegex.hasMatch(candidate)) {
          return candidate;
        }
      }
    }
    return null;
  }

  static bool isValidYoutubeUrl(String rawInput) =>
      extractVideoId(rawInput) != null;
}

enum YoutubeDownloadMode {
  videoMp4('Video (MP4)'),
  audioOnly('Solo Audio');

  final String label;
  const YoutubeDownloadMode(this.label);
}

enum YoutubeVideoQualityOption {
  p1080(1080, '1080p Full HD'),
  p720(720, '720p HD'),
  p480(480, '480p SD'),
  p360(360, '360p Ligero');

  final int height;
  final String label;
  const YoutubeVideoQualityOption(this.height, this.label);
}

enum YoutubeAudioFormatOption {
  m4a('M4A (Nativo rápido)', 'm4a'),
  mp3('MP3 (Con metadatos)', 'mp3');

  final String label;
  final String extension;
  const YoutubeAudioFormatOption(this.label, this.extension);
}

enum YoutubeDownloadStage {
  idle('En espera'),
  fetchingStreams('Obteniendo flujos'),
  downloading('Descargando'),
  assembling('Ensamblando archivo'),
  completed('Completado');

  final String label;
  const YoutubeDownloadStage(this.label);
}

class YoutubeVideoInfo {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final List<int> availableHeights;

  const YoutubeVideoInfo({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    this.availableHeights = const [1080, 720, 480, 360],
  });
}

class YoutubeDownloadProgress {
  final YoutubeDownloadStage stage;
  final double progress;
  final String statusMessage;
  final bool isCompleted;
  final String? outputPath;
  final String? errorMessage;

  const YoutubeDownloadProgress({
    required this.stage,
    required this.progress,
    required this.statusMessage,
    this.isCompleted = false,
    this.outputPath,
    this.errorMessage,
  });
}
