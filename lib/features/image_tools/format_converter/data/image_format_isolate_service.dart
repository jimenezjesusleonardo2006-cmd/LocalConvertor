import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/image_format_config.dart';
import 'svg_rasterizer.dart';

/// Servicio Facade FFI para conversión de lotes de imágenes en paralelo (`rayon` + `image` en Rust).
class ImageFormatIsolateService {
  final SandboxCleanerService _sandboxCleaner;

  Isolate? _activeIsolate;
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  String? _activeSessionDir;

  ImageFormatIsolateService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  Stream<ImageFormatProgressEvent> convertBatch(ImageFormatBatchConfig config) {
    cancel();

    final controller = StreamController<ImageFormatProgressEvent>();
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _activeSessionDir = config.sessionDirPath;

    _receivePort!.listen((dynamic message) {
      if (message is ImageFormatProgressEvent) {
        if (!controller.isClosed) {
          controller.add(message);
        }
        if (message.isCompleted || message.errorMessage != null) {
          _disposeIsolate();
          controller.close();
        }
      }
    });

    _errorPort!.listen((dynamic err) async {
      await _sandboxCleaner.deleteSessionDir(_activeSessionDir);
      if (!controller.isClosed) {
        controller.add(
          ImageFormatProgressEvent(
            currentIndex: 0,
            totalFiles: config.inputPaths.length,
            statusMessage: 'Fallo en el Isolate de conversión.',
            errorMessage: err.toString(),
          ),
        );
        await controller.close();
      }
      _disposeIsolate();
    });

    Isolate.spawn<ImageFormatIsolateRequest>(
      _isolateEntryPoint,
      ImageFormatIsolateRequest(
        sendPort: _receivePort!.sendPort,
        config: config,
      ),
      onError: _errorPort!.sendPort,
      debugName: 'LocalConvert_ImageFormat_RustFFI_Isolate',
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
    ImageFormatIsolateRequest request,
  ) async {
    final sendPort = request.sendPort;
    final config = request.config;
    final total = config.inputPaths.length;
    Directory? svgStagingDir;

    try {
      sendPort.send(
        ImageFormatProgressEvent(
          currentIndex: total > 0 ? 1 : 0,
          totalFiles: total,
          statusMessage:
              'Procesando $total imágenes en paralelo (Rust + Rayon) hacia .${config.targetFormat.extension.toUpperCase()}...',
        ),
      );

      final normalizedInputPaths = <String>[];
      for (int i = 0; i < total; i++) {
        final inputPath = config.inputPaths[i];
        final ext = p.extension(inputPath).toLowerCase();
        if (ext == '.svg') {
          svgStagingDir ??= await Directory(
            p.join(config.sessionDirPath, '.svg_staging'),
          ).create(recursive: true);

          final rawBytes = await File(inputPath).readAsBytes();
          final decodedSvg = SvgRasterizer.decodeSvgToImage(
            utf8.decode(rawBytes, allowMalformed: true),
            scaleMultiplier: config.svgScaleMultiplier,
            maxDimensionPx: config.maxDimensionPx,
          );
          final pngBytes = encodeImageToFormat(
            image: decodedSvg,
            targetFormat: TargetImageFormat.png,
            quality: 100,
          );
          final stagedPath = p.join(
            svgStagingDir.path,
            '${p.basenameWithoutExtension(inputPath)}.png',
          );
          await File(stagedPath).writeAsBytes(pngBytes, flush: true);
          normalizedInputPaths.add(stagedPath);
        } else {
          normalizedInputPaths.add(inputPath);
        }
      }

      final result = LocalConvertRustBridge.invokeJsonSync({
        'action': 'convert_image_batch',
        'input_paths': normalizedInputPaths,
        'session_dir_path': config.sessionDirPath,
        'target_format': config.targetFormat.extension,
        'quality': config.quality,
        'max_dimension_px': config.maxDimensionPx,
        'package_as_zip': config.packageAsZip,
      });

      final outputPaths = ((result['output_files'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList();
      final zipPath = result['zip_file_path']?.toString();

      Isolate.exit(
        sendPort,
        ImageFormatProgressEvent(
          currentIndex: total,
          totalFiles: total,
          statusMessage: 'Conversión paralela en Rust de $total imágenes completada.',
          isCompleted: true,
          outputFiles: outputPaths,
          zipFilePath: zipPath,
        ),
      );
    } catch (e) {
      Isolate.exit(
        sendPort,
        ImageFormatProgressEvent(
          currentIndex: 0,
          totalFiles: total,
          statusMessage: 'Error durante la conversión de formatos.',
          errorMessage: e.toString(),
        ),
      );
    } finally {
      if (svgStagingDir != null) {
        try {
          if (svgStagingDir.existsSync()) {
            svgStagingDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  /// Codifica un `img.Image` en memoria delegando al motor nativo en Rust (`image`).
  static Uint8List encodeImageToFormat({
    required img.Image image,
    required TargetImageFormat targetFormat,
    required int quality,
  }) {
    final img.Image rgbaImg =
        (image.numChannels == 4 && image.format == img.Format.uint8)
            ? image
            : image.convert(
                format: img.Format.uint8,
                numChannels: 4,
                alpha: 255,
              );
    final rgbaBytes = rgbaImg.getBytes(order: img.ChannelOrder.rgba);

    return LocalConvertRustBridge.encodeRgbaBufferSync(
      rgbaBytes: rgbaBytes,
      width: rgbaImg.width,
      height: rgbaImg.height,
      format: targetFormat.extension,
      quality: quality,
    );
  }
}
