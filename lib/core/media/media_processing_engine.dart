import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'ffmpeg_binary_resolver.dart';
import 'ffmpeg_progress_parser.dart';

/// Evento de progreso determinista emitido por el motor multimedia.
class MediaProgressEvent {
  final double progress;
  final String statusMessage;
  final bool isCompleted;
  final String? outputPath;
  final String? zipFilePath;
  final String? errorMessage;

  const MediaProgressEvent({
    required this.progress,
    required this.statusMessage,
    this.isCompleted = false,
    this.outputPath,
    this.zipFilePath,
    this.errorMessage,
  });
}

/// Contrato multiplataforma desacoplado de la UI para ejecutar comandos FFmpeg
/// localmente (binario nativo en escritorio o `ffmpeg_kit_flutter` en móvil).
abstract class MediaProcessingEngine {
  Future<bool> isAvailable();

  Future<String?> resolveExecutablePath();

  Stream<MediaProgressEvent> executeCommand({
    required List<String> arguments,
    required String outputPath,
    Duration? knownDuration,
    String? statusPrefix,
  });

  Future<void> cancelCurrent();
}

/// Motor de escritorio que ejecuta `ffmpeg.exe` / `ffmpeg` mediante `Process.start`,
/// parsea el `stderr` en tiempo real y permite cancelación inmediata (`kill`).
class DesktopFfmpegEngine implements MediaProcessingEngine {
  Process? _activeProcess;
  bool _isCancelled = false;

  String get _binaryName => Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

  @override
  Future<String?> resolveExecutablePath() async {
    final resolvedFromBundler = FfmpegBinaryResolver.ffmpegPath;
    if (resolvedFromBundler != 'ffmpeg' &&
        await File(resolvedFromBundler).exists()) {
      return resolvedFromBundler;
    }

    final candidates = <String>[
      p.join(Directory.current.path, 'windows', '.cache', 'ffmpeg', _binaryName),
      p.join(Directory.current.path, 'windows', 'bin', _binaryName),
      p.join(Directory.current.path, 'bin', _binaryName),
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    try {
      final result = await Process.run(resolvedFromBundler, const ['-version']);
      if (result.exitCode == 0) {
        return resolvedFromBundler;
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<bool> isAvailable() async {
    return (await resolveExecutablePath()) != null;
  }

  @override
  Stream<MediaProgressEvent> executeCommand({
    required List<String> arguments,
    required String outputPath,
    Duration? knownDuration,
    String? statusPrefix,
  }) async* {
    _isCancelled = false;
    final execPath = await resolveExecutablePath();
    if (execPath == null) {
      yield MediaProgressEvent(
        progress: 0.0,
        statusMessage: 'Motor FFmpeg no encontrado.',
        errorMessage:
            'No se encontró $_binaryName junto al ejecutable, en windows/bin/ ni en el PATH del sistema.',
      );
      return;
    }

    final prefix = statusPrefix ?? 'Procesando multimedia';
    yield MediaProgressEvent(progress: 0.02, statusMessage: '$prefix...');

    final controller = StreamController<MediaProgressEvent>();
    Duration? totalDuration = knownDuration;
    final tailLogs = <String>[];

    try {
      final process = await Process.start(execPath, arguments);
      _activeProcess = process;

      final sub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (tailLogs.length >= 25) tailLogs.removeAt(0);
        tailLogs.add(line);

        totalDuration ??= FfmpegProgressParser.parseDuration(line);
        final current = FfmpegProgressParser.parseCurrentTime(line);
        if (current != null && !controller.isClosed) {
          final pct = FfmpegProgressParser.computeProgress(
            current,
            totalDuration,
          );
          controller.add(
            MediaProgressEvent(
              progress: pct,
              statusMessage:
                  '$prefix (${FfmpegProgressParser.formatDuration(current)})...',
            ),
          );
        }
      });

      unawaited(
        process.exitCode.then((code) async {
          await sub.cancel();
          _activeProcess = null;

          if (!controller.isClosed) {
            if (_isCancelled) {
              controller.add(
                const MediaProgressEvent(
                  progress: 0.0,
                  statusMessage: 'Operación cancelada por el usuario.',
                  errorMessage: 'Operación cancelada por el usuario.',
                ),
              );
            } else if (code == 0 && await File(outputPath).exists()) {
              controller.add(
                MediaProgressEvent(
                  progress: 1.0,
                  statusMessage: '$prefix completado.',
                  isCompleted: true,
                  outputPath: outputPath,
                ),
              );
            } else {
              final reason = tailLogs.isNotEmpty
                  ? tailLogs.last
                  : 'Código de salida FFmpeg: $code';
              controller.add(
                MediaProgressEvent(
                  progress: 0.0,
                  statusMessage: 'Error en transcodificación FFmpeg.',
                  errorMessage: reason,
                ),
              );
            }
            await controller.close();
          }
        }),
      );

      yield* controller.stream;
    } catch (e) {
      _activeProcess = null;
      yield MediaProgressEvent(
        progress: 0.0,
        statusMessage: 'No se pudo iniciar FFmpeg.',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<void> cancelCurrent() async {
    _isCancelled = true;
    final proc = _activeProcess;
    _activeProcess = null;
    if (proc != null) {
      proc.kill(ProcessSignal.sigkill);
    }
  }
}

/// Adaptador móvil (Android / iOS) compatible con el canal nativo de `ffmpeg_kit_flutter`.
class MobileFfmpegKitAdapterEngine implements MediaProcessingEngine {
  static const MethodChannel _methodChannel = MethodChannel(
    'local_convert/ffmpeg_kit',
  );
  static const EventChannel _progressChannel = EventChannel(
    'local_convert/ffmpeg_kit_progress',
  );

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> resolveExecutablePath() async => 'ffmpeg_kit_flutter';

  @override
  Stream<MediaProgressEvent> executeCommand({
    required List<String> arguments,
    required String outputPath,
    Duration? knownDuration,
    String? statusPrefix,
  }) async* {
    final prefix = statusPrefix ?? 'Procesando en móvil';
    yield MediaProgressEvent(progress: 0.05, statusMessage: '$prefix...');

    StreamSubscription<dynamic>? progressSub;
    final controller = StreamController<MediaProgressEvent>();

    try {
      progressSub = _progressChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is num && !controller.isClosed) {
            final pct = event.toDouble().clamp(0.0, 0.98);
            controller.add(
              MediaProgressEvent(
                progress: pct,
                statusMessage: '$prefix (${(pct * 100).round()}%)...',
              ),
            );
          }
        },
        onError: (_) {},
      );

      unawaited(
        _methodChannel
            .invokeMethod<bool>('execute', {
          'arguments': arguments,
          'outputPath': outputPath,
          'durationMs': knownDuration?.inMilliseconds,
        }).then((ok) async {
          await progressSub?.cancel();
          if (!controller.isClosed) {
            if (ok == true) {
              controller.add(
                MediaProgressEvent(
                  progress: 1.0,
                  statusMessage: '$prefix completado.',
                  isCompleted: true,
                  outputPath: outputPath,
                ),
              );
            } else {
              controller.add(
                const MediaProgressEvent(
                  progress: 0.0,
                  statusMessage: 'FFmpegKit no pudo completar la conversión.',
                  errorMessage: 'Error ejecutando sesión FFmpegKit.',
                ),
              );
            }
            await controller.close();
          }
        }).catchError((Object err) async {
          await progressSub?.cancel();
          if (!controller.isClosed) {
            controller.add(
              MediaProgressEvent(
                progress: 0.0,
                statusMessage: 'Adaptador móvil FFmpegKit no disponible.',
                errorMessage: err.toString(),
              ),
            );
            await controller.close();
          }
        }),
      );

      yield* controller.stream;
    } catch (e) {
      await progressSub?.cancel();
      yield MediaProgressEvent(
        progress: 0.0,
        statusMessage: 'Error en motor multimedia móvil.',
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<void> cancelCurrent() async {
    try {
      await _methodChannel.invokeMethod<void>('cancel');
    } catch (_) {}
  }
}

/// Proveedor del motor multimedia adaptativo según plataforma (Escritorio vs. Móvil).
final mediaProcessingEngineProvider = Provider<MediaProcessingEngine>((ref) {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return MobileFfmpegKitAdapterEngine();
  }
  return DesktopFfmpegEngine();
});
