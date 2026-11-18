import '../../../../core/media/ffmpeg_cli_builder.dart';

/// Configuración para extracción de pista de audio desde un archivo de video.
class VideoToAudioConfig {
  final String inputVideoPath;
  final String outputAudioPath;
  final String sessionDirPath;
  final AudioExtractFormat format;
  final bool streamCopyFastMode;
  final AudioBitrateOption bitrate;

  const VideoToAudioConfig({
    required this.inputVideoPath,
    required this.outputAudioPath,
    required this.sessionDirPath,
    this.format = AudioExtractFormat.mp3,
    this.streamCopyFastMode = false,
    this.bitrate = AudioBitrateOption.k192,
  });
}
