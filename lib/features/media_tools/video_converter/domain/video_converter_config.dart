import '../../../../core/media/ffmpeg_cli_builder.dart';

/// Configuración para transcodificación, compresión CRF y recorte de video.
class VideoConverterConfig {
  final String inputPath;
  final String outputPath;
  final String sessionDirPath;
  final VideoOutputFormat format;
  final VideoResolutionPreset resolution;
  final VideoCrfPreset crfPreset;
  final bool muteAudio;
  final Duration? trimStart;
  final Duration? trimEnd;

  const VideoConverterConfig({
    required this.inputPath,
    required this.outputPath,
    required this.sessionDirPath,
    this.format = VideoOutputFormat.mp4,
    this.resolution = VideoResolutionPreset.original,
    this.crfPreset = VideoCrfPreset.balanced,
    this.muteAudio = false,
    this.trimStart,
    this.trimEnd,
  });
}
