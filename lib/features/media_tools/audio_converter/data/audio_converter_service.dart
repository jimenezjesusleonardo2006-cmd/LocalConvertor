import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../core/media/media_processing_engine.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/audio_converter_config.dart';

/// Servicio por lotes para conversión local de audio usando [MediaProcessingEngine].
class AudioConverterService {
  final MediaProcessingEngine _engine;
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  AudioConverterService({
    required MediaProcessingEngine engine,
    required SandboxCleanerService sandboxCleaner,
  })  : _engine = engine,
        _sandboxCleaner = sandboxCleaner;

  Stream<MediaProgressEvent> convertBatch(
    AudioConverterBatchConfig config,
  ) async* {
    _isCancelled = false;
    final total = config.inputPaths.length;
    final outputPaths = <String>[];

    try {
      if (total == 0) {
        throw const FormatException('Selecciona al menos un archivo de audio.');
      }

      for (int i = 0; i < total; i++) {
        if (_isCancelled) {
          await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
          return;
        }

        final inputPath = config.inputPaths[i];
        final baseName = p.basenameWithoutExtension(inputPath);
        final outPath = p.join(
          config.sessionDirPath,
          '${baseName}_${i + 1}.${config.targetFormat.extension}',
        );

        final args = FfmpegCliBuilder.buildAudioConversionArgs(
          inputPath: inputPath,
          outputPath: outPath,
          format: config.targetFormat,
          bitrate: config.bitrate,
          sampleRate: config.sampleRate,
        );

        String? stepError;
        await for (final ev in _engine.executeCommand(
          arguments: args,
          outputPath: outPath,
          statusPrefix:
              'Audio ${i + 1}/$total: ${p.basename(inputPath)} → .${config.targetFormat.extension.toUpperCase()}',
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
            return;
          }
          if (ev.errorMessage != null) {
            stepError = ev.errorMessage;
            break;
          }
          final overall = ((i + ev.progress) / total).clamp(0.0, 0.94);
          yield MediaProgressEvent(
            progress: overall,
            statusMessage: ev.statusMessage,
          );
        }

        if (stepError != null) {
          throw Exception(stepError);
        }
        outputPaths.add(outPath);
      }

      if (_isCancelled) {
        await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
        return;
      }

      if (config.packageAsZip || outputPaths.length > 1) {
        yield const MediaProgressEvent(
          progress: 0.96,
          statusMessage: 'Empaquetando lote de audio en archivo .ZIP...',
        );
        final archive = Archive();
        for (final path in outputPaths) {
          final bytes = await File(path).readAsBytes();
          archive.addFile(ArchiveFile(p.basename(path), bytes.length, bytes));
        }
        final zipBytes = ZipEncoder().encode(archive);
        final extUpper = config.targetFormat.extension.toUpperCase();
        final zipPath = p.join(
          config.sessionDirPath,
          'LocalConvert_Audio_$extUpper.zip',
        );
        await File(zipPath).writeAsBytes(zipBytes, flush: true);

        yield MediaProgressEvent(
          progress: 1.0,
          statusMessage: 'Conversión de $total audios completada en .ZIP.',
          isCompleted: true,
          outputPath: outputPaths.first,
          zipFilePath: zipPath,
        );
      } else {
        yield MediaProgressEvent(
          progress: 1.0,
          statusMessage: 'Audio convertido con éxito.',
          isCompleted: true,
          outputPath: outputPaths.first,
        );
      }
    } catch (e) {
      await _sandboxCleaner.deleteSessionDir(config.sessionDirPath);
      yield MediaProgressEvent(
        progress: 0.0,
        statusMessage: 'Error durante la conversión de audio.',
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> cancel() async {
    _isCancelled = true;
    await _engine.cancelCurrent();
  }
}
