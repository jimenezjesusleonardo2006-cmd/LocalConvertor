import '../../../../core/media/ffmpeg_cli_builder.dart';

/// Elemento de audio cargado en la cola de conversión por lotes.
class AudioBatchItem {
  final String path;
  final String fileName;
  final int sizeBytes;
  final String sourceExtension;

  const AudioBatchItem({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.sourceExtension,
  });
}

/// Configuración del lote de conversión de audio mediante FFmpeg local.
class AudioConverterBatchConfig {
  final List<String> inputPaths;
  final String sessionDirPath;
  final AudioOutputFormat targetFormat;
  final AudioBitrateOption bitrate;
  final AudioSampleRateOption sampleRate;
  final bool packageAsZip;

  const AudioConverterBatchConfig({
    required this.inputPaths,
    required this.sessionDirPath,
    this.targetFormat = AudioOutputFormat.mp3,
    this.bitrate = AudioBitrateOption.k192,
    this.sampleRate = AudioSampleRateOption.hz44100,
    this.packageAsZip = false,
  });
}
