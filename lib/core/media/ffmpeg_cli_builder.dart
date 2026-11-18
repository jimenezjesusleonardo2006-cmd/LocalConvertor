import 'ffmpeg_progress_parser.dart';

/// Formatos de salida para el conversor de audio por lotes.
enum AudioOutputFormat {
  mp3('MP3', 'mp3', 'libmp3lame', true),
  wav('WAV', 'wav', 'pcm_s16le', false),
  m4a('M4A (AAC)', 'm4a', 'aac', true),
  ogg('OGG (Vorbis)', 'ogg', 'libvorbis', true),
  flac('FLAC (Sin pérdida)', 'flac', 'flac', false),
  opus('OPUS', 'opus', 'libopus', true);

  final String label;
  final String extension;
  final String codec;
  final bool usesBitrate;
  const AudioOutputFormat(
    this.label,
    this.extension,
    this.codec,
    this.usesBitrate,
  );
}

enum AudioBitrateOption {
  k128(128, '128 kbps'),
  k192(192, '192 kbps'),
  k320(320, '320 kbps');

  final int kbps;
  final String label;
  const AudioBitrateOption(this.kbps, this.label);
}

enum AudioSampleRateOption {
  hz44100(44100, '44.1 kHz'),
  hz48000(48000, '48 kHz');

  final int hz;
  final String label;
  const AudioSampleRateOption(this.hz, this.label);
}

/// Formatos de salida para el conversor y compresor de video.
enum VideoOutputFormat {
  mp4('MP4 (H.264)', 'mp4'),
  mkv('MKV', 'mkv'),
  webm('WEBM (VP9)', 'webm'),
  mov('MOV', 'mov'),
  avi('AVI', 'avi'),
  gif('GIF Animado', 'gif');

  final String label;
  final String extension;
  const VideoOutputFormat(this.label, this.extension);
}

enum VideoResolutionPreset {
  original('Original', null),
  p1080('1080p', 1080),
  p720('720p', 720),
  p480('480p', 480);

  final String label;
  final int? height;
  const VideoResolutionPreset(this.label, this.height);
}

enum VideoCrfPreset {
  highQuality('Alta calidad (CRF 18)', 18),
  balanced('Balanceado (CRF 23)', 23),
  compact('Tamaño reducido (CRF 28)', 28);

  final String label;
  final int crf;
  const VideoCrfPreset(this.label, this.crf);
}

enum AudioExtractFormat {
  mp3('MP3', 'mp3', AudioOutputFormat.mp3),
  m4a('M4A (AAC)', 'm4a', AudioOutputFormat.m4a),
  wav('WAV (Sin pérdida)', 'wav', AudioOutputFormat.wav);

  final String label;
  final String extension;
  final AudioOutputFormat audioFormat;
  const AudioExtractFormat(this.label, this.extension, this.audioFormat);
}

/// Constructor puro de argumentos CLI para FFmpeg (sin dependencias nativas).
class FfmpegCliBuilder {
  const FfmpegCliBuilder._();

  /// Genera los argumentos de conversión de audio con soporte de etiquetas metadata.
  static List<String> buildAudioConversionArgs({
    required String inputPath,
    required String outputPath,
    required AudioOutputFormat format,
    required AudioBitrateOption bitrate,
    required AudioSampleRateOption sampleRate,
    Map<String, String>? metadata,
  }) {
    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ar',
      '${sampleRate.hz}',
      '-c:a',
      format.codec,
    ];

    if (format.usesBitrate) {
      args.addAll(['-b:a', '${bitrate.kbps}k']);
    }

    if (metadata != null) {
      metadata.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          args.addAll(['-metadata', '$key=$value']);
        }
      });
    }

    args.add(outputPath);
    return args;
  }

  /// Genera argumentos de conversión, escalado, compresión CRF, silencio o recorte Trim de video.
  static List<String> buildVideoConversionArgs({
    required String inputPath,
    required String outputPath,
    required VideoOutputFormat format,
    required VideoResolutionPreset resolution,
    required VideoCrfPreset crfPreset,
    required bool muteAudio,
    Duration? trimStart,
    Duration? trimEnd,
  }) {
    final args = <String>['-y'];

    if (trimStart != null) {
      args.addAll(['-ss', FfmpegProgressParser.toFfmpegTimestamp(trimStart)]);
    }
    if (trimEnd != null && (trimStart == null || trimEnd > trimStart)) {
      args.addAll(['-to', FfmpegProgressParser.toFfmpegTimestamp(trimEnd)]);
    }

    args.addAll(['-i', inputPath]);

    if (format == VideoOutputFormat.gif) {
      final targetHeight = resolution.height ?? 480;
      final filter =
          'fps=12,scale=-1:$targetHeight:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse';
      args.addAll(['-vf', filter, '-loop', '0', outputPath]);
      return args;
    }

    if (resolution.height != null) {
      args.addAll(['-vf', 'scale=-2:${resolution.height}']);
    }

    if (format == VideoOutputFormat.webm) {
      args.addAll([
        '-c:v',
        'libvpx-vp9',
        '-crf',
        '${crfPreset.crf}',
        '-b:v',
        '0',
      ]);
    } else if (format == VideoOutputFormat.avi) {
      final qscale = crfPreset == VideoCrfPreset.highQuality
          ? 3
          : (crfPreset == VideoCrfPreset.balanced ? 6 : 10);
      args.addAll(['-c:v', 'mpeg4', '-q:v', '$qscale']);
    } else {
      args.addAll([
        '-c:v',
        'libx264',
        '-preset',
        'medium',
        '-crf',
        '${crfPreset.crf}',
        '-pix_fmt',
        'yuv420p',
      ]);
    }

    if (muteAudio) {
      args.add('-an');
    } else {
      final audioCodec = format == VideoOutputFormat.webm ? 'libopus' : 'aac';
      args.addAll(['-c:a', audioCodec, '-b:a', '192k']);
    }

    args.add(outputPath);
    return args;
  }

  /// Genera argumentos para extraer la pista de audio desde un video (con opción Stream Copy).
  static List<String> buildAudioExtractionArgs({
    required String inputPath,
    required String outputPath,
    required AudioExtractFormat format,
    required bool streamCopy,
    required AudioBitrateOption bitrate,
  }) {
    if (streamCopy) {
      return ['-y', '-i', inputPath, '-vn', '-c:a', 'copy', outputPath];
    }

    return buildAudioConversionArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      format: format.audioFormat,
      bitrate: bitrate,
      sampleRate: AudioSampleRateOption.hz44100,
    );
  }

  /// Une una pista adaptativa de video (sin audio) con su pista de audio descargada en el sandbox.
  static List<String> buildMuxVideoAndAudioArgs({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) {
    return [
      '-y',
      '-i',
      videoPath,
      '-i',
      audioPath,
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-shortest',
      outputPath,
    ];
  }
}
