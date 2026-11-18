import 'dart:io';

import '../../../../core/constants/memory_guard_config.dart';
import '../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../core/media/media_processing_engine.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/video_converter_config.dart';

/// Servicio local de transcodificación y compresión de video con límite de concurrencia.
class VideoConverterService {
  static int _activeTranscodes = 0;

  final MediaProcessingEngine _engine;
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  VideoConverterService({
    required MediaProcessingEngine engine,
    required SandboxCleanerService sandboxCleaner,
  })  : _engine = engine,
        _sandboxCleaner = sandboxCleaner;

  Stream<MediaProgressEvent> convertVideo(VideoConverterConfig config) async* {
    _isCancelled = false;
    if (_activeTranscodes >= MemoryGuardConfig.maxConcurrentVideoTranscodes) {
      yield MediaProgressEvent(
        progress: 0.0,
        statusMessage: 'Límite de concurrencia de video alcanzado.',
        errorMessage:
            'Solo se permiten ${MemoryGuardConfig.maxConcurrentVideoTranscodes} transcodificación(es) simultáneas en este dispositivo.',
      );
      return;
    }

    _activeTranscodes++;
    try {
      if (!await File(config.inputPath).exists()) {
        throw FileSystemException('Archivo de video no encontrado', config.inputPath);
      }

      if (config.trimStart != null &&
          config.trimEnd != null &&
          config.trimEnd! <= config.trimStart!) {
        throw const FormatException(
          'El tiempo final de recorte (Trim) debe ser mayor al inicial.',
        );
      }

      final args = FfmpegCliBuilder.buildVideoConversionArgs(
        inputPath: config.inputPath,
        outputPath: config.outputPath,
        format: config.format,
        resolution: config.resolution,
        crfPreset: config.crfPreset,
        muteAudio: config.muteAudio,
        trimStart: config.trimStart,
        trimEnd: config.trimEnd,
      );

      await for (final ev in _engine.executeCommand(
        arguments: args,
        outputPath: config.outputPath,
        statusPrefix: 'Transcodificando video a ${config.format.label}',
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
        statusMessage: 'Error durante la conversión de video.',
        errorMessage: e.toString(),
      );
    } finally {
      _activeTranscodes = (_activeTranscodes - 1).clamp(0, 10);
    }
  }

  Future<void> cancel() async {
    _isCancelled = true;
    await _engine.cancelCurrent();
  }
}
