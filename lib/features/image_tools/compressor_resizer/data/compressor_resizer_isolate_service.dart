import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/compressor_resizer_config.dart';

/// Servicio Facade FFI para compresión, redimensionamiento Lanczos3 y estimación
/// en tiempo real delegando al motor nativo paralelo en Rust (`image` + `rayon`).
class CompressorResizerIsolateService {
  final SandboxCleanerService _sandboxCleaner;

  Isolate? _activeIsolate;
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  String? _activeSessionDir;

  CompressorResizerIsolateService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  /// Calcula en un [Isolate] efímero vía Rust FFI el peso final estimado de una
  /// imagen de muestra al mover el slider de calidad (1–100) o cambiar dimensiones.
  Future<CompressionEstimateResult?> estimateSingleFile({
    required String filePath,
    required ImageResizeMode resizeMode,
    required int scalePercent,
    int? targetWidthPx,
    int? targetHeightPx,
    required bool maintainAspectRatio,
    required int quality,
    int maxDimensionPx = 4096,
  }) async {
    try {
      return await Isolate.run(() {
        if (!File(filePath).existsSync()) return null;

        final data = LocalConvertRustBridge.invokeJsonSync({
          'action': 'estimate_single_image',
          'file_path': filePath,
          'resize_mode': resizeMode.name,
          'scale_percent': scalePercent,
          'target_width_px': targetWidthPx,
          'target_height_px': targetHeightPx,
          'maintain_aspect_ratio': maintainAspectRatio,
          'quality': quality,
          'max_dimension_px': maxDimensionPx,
        });

        return CompressionEstimateResult(
          originalBytes: (data['original_bytes'] as num).toInt(),
          estimatedBytes: (data['estimated_bytes'] as num).toInt(),
          originalWidth: (data['original_width'] as num).toInt(),
          originalHeight: (data['original_height'] as num).toInt(),
          targetWidth: (data['target_width'] as num).toInt(),
          targetHeight: (data['target_height'] as num).toInt(),
        );
      });
    } catch (_) {
      return null;
    }
  }

  /// Ejecuta la compresión y redimensionamiento de todo el lote en un [Isolate]
  /// delegando el procesamiento multinúcleo a Rust (`rayon`).
  Stream<CompressorProgressEvent> processBatch(
    CompressorResizerBatchConfig config,
  ) {
    cancel();

    final controller = StreamController<CompressorProgressEvent>();
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _activeSessionDir = config.sessionDirPath;

    _receivePort!.listen((dynamic msg) {
      if (msg is CompressorProgressEvent) {
        if (!controller.isClosed) {
          controller.add(msg);
        }
        if (msg.isCompleted || msg.errorMessage != null) {
          _disposeIsolate();
          controller.close();
        }
      }
    });

    _errorPort!.listen((dynamic err) async {
      await _sandboxCleaner.deleteSessionDir(_activeSessionDir);
      if (!controller.isClosed) {
        controller.add(
          CompressorProgressEvent(
            currentIndex: 0,
            totalFiles: config.inputPaths.length,
            statusMessage: 'Error en el Isolate de compresión.',
            errorMessage: err.toString(),
          ),
        );
        await controller.close();
      }
      _disposeIsolate();
    });

    Isolate.spawn<CompressorIsolateRequest>(
      _isolateEntryPoint,
      CompressorIsolateRequest(
        sendPort: _receivePort!.sendPort,
        config: config,
      ),
      onError: _errorPort!.sendPort,
      debugName: 'LocalConvert_CompressorResizer_RustFFI_Isolate',
    ).then((iso) {
      _activeIsolate = iso;
    });

    controller.onCancel = () {
      if (_activeIsolate != null) {
        cancel();
      }
    };

    return controller.stream;
  }

  Future<void> cancel() async {
    final dirToClean = _activeSessionDir;
    _disposeIsolate();
    if (dirToClean != null) {
      await _sandboxCleaner.deleteSessionDir(dirToClean);
    }
  }

  void _disposeIsolate() {
    _activeIsolate?.kill(priority: Isolate.immediate);
    _activeIsolate = null;
    _receivePort?.close();
    _receivePort = null;
    _errorPort?.close();
    _errorPort = null;
    _activeSessionDir = null;
  }

  @pragma('vm:entry-point')
  static Future<void> _isolateEntryPoint(
    CompressorIsolateRequest request,
  ) async {
    final sendPort = request.sendPort;
    final config = request.config;
    final total = config.inputPaths.length;

    try {
      sendPort.send(
        CompressorProgressEvent(
          currentIndex: total > 0 ? 1 : 0,
          totalFiles: total,
          statusMessage:
              'Comprimiendo y escalando $total imágenes en paralelo con Rust (Lanczos3 + Rayon)...',
        ),
      );

      final result = LocalConvertRustBridge.invokeJsonSync({
        'action': 'compress_resize_batch',
        'input_paths': config.inputPaths,
        'session_dir_path': config.sessionDirPath,
        'resize_mode': config.resizeMode.name,
        'scale_percent': config.scalePercent,
        'target_width_px': config.targetWidthPx,
        'target_height_px': config.targetHeightPx,
        'maintain_aspect_ratio': config.maintainAspectRatio,
        'quality': config.quality,
        'max_dimension_px': config.maxDimensionPx,
      });

      final outputPaths = ((result['output_files'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();

      Isolate.exit(
        sendPort,
        CompressorProgressEvent(
          currentIndex: total,
          totalFiles: total,
          statusMessage: 'Optimización nativa en Rust completada.',
          isCompleted: true,
          outputFiles: outputPaths,
          zipFilePath: result['zip_file_path']?.toString(),
          totalOriginalBytes:
              (result['total_original_bytes'] as num?)?.toInt() ?? 0,
          totalCompressedBytes:
              (result['total_compressed_bytes'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (e) {
      Isolate.exit(
        sendPort,
        CompressorProgressEvent(
          currentIndex: 0,
          totalFiles: total,
          statusMessage: 'Error durante la compresión.',
          errorMessage: e.toString(),
        ),
      );
    }
  }
}
