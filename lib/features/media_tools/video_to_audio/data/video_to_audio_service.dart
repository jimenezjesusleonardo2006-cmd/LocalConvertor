import 'dart:io';

import '../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../core/media/media_processing_engine.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/video_to_audio_config.dart';

/// Servicio local que extrae audio desde archivos de video con modo Stream Copy opcional.
class VideoToAudioService {
  final MediaProcessingEngine _engine;
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  VideoToAudioService({
    required MediaProcessingEngine engine,
    required SandboxCleanerService sandboxCleaner,
  })  : _engine = engine,
        _sandboxCleaner = sandboxCleaner;

  Stream<MediaProgressEvent> extractAudio(VideoToAudioConfig config) async* {
    _isCancelled = false;
    try {
      if (!await File(config.inputVideoPath).exists()) {
        throw FileSystemException(
          'No se encontró el archivo de video',
          config.inputVideoPath,
        );
      }

      if (config.streamCopyFastMode &&
          config.format == AudioExtractFormat.m4a) {
        final copyArgs = FfmpegCliBuilder.buildAudioExtractionArgs(
          inputPath: config.inputVideoPath,
          outputPath: config.outputAudioPath,
          format: config.format,
          streamCopy: true,
          bitrate: config.bitrate,
        );

        MediaProgressEvent? lastCopyEvent;
        await for (final ev in _engine.executeCommand(
          arguments: copyArgs,
          outputPath: config.outputAudioPath,
          statusPrefix: 'Extrayendo audio sin pérdida (Stream Copy)',
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
            return;
          }
          lastCopyEvent = ev;
          if (ev.errorMessage == null) {
            yield ev;
          }
        }

        if (lastCopyEvent?.isCompleted == true) {
          return;
        }
        yield const MediaProgressEvent(
          progress: 0.1,
          statusMessage:
              'Códec no compatible con Stream Copy directo; recodificando a AAC...',
        );
      }

      final transcodeArgs = FfmpegCliBuilder.buildAudioExtractionArgs(
        inputPath: config.inputVideoPath,
        outputPath: config.outputAudioPath,
        format: config.format,
        streamCopy: false,
        bitrate: config.bitrate,
      );

      await for (final ev in _engine.executeCommand(
        arguments: transcodeArgs,
        outputPath: config.outputAudioPath,
        statusPrefix: 'Extrayendo pista a .${config.format.extension.toUpperCase()}',
      )) {
        if (_isCancelled) {
          await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
          return;
        }
        yield ev;
      }
    } catch (e) {
      await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
      yield MediaProgressEvent(
        progress: 0.0,
        statusMessage: 'Error al extraer el audio del video.',
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> cancel() async {
    _isCancelled = true;
    await _engine.cancelCurrent();
  }
}
