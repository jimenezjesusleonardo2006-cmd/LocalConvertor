import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../../core/rust_ffi/local_convert_rust_bridge.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/image_to_pdf_config.dart';

/// Servicio Facade FFI de conversión de Imágenes a PDF ejecutado fuera del UI thread
/// delegando el procesamiento paralelo de imágenes (`image` + `rayon`) y ensamblado
/// (`printpdf`) al motor nativo en Rust (`local_convert_core`).
class ImageToPdfIsolateService {
  final SandboxCleanerService _sandboxCleaner;

  Isolate? _activeIsolate;
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  String? _activeTempFilePath;

  ImageToPdfIsolateService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  /// Indica si hay un proceso de conversión activo en segundo plano.
  bool get isRunning => _activeIsolate != null;

  /// Ejecuta la conversión en un [Isolate] y devuelve un [Stream] con el progreso determinista.
  Stream<ImageToPdfProgressEvent> convertImagesToPdf(ImageToPdfConfig config) {
    cancel();

    final controller = StreamController<ImageToPdfProgressEvent>();
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _activeTempFilePath = config.outputFilePath;

    _receivePort!.listen((dynamic message) {
      if (message is ImageToPdfProgressEvent) {
        if (!controller.isClosed) {
          controller.add(message);
        }

        if (message.stage == ConversionStage.completed ||
            message.stage == ConversionStage.failed) {
          _disposeIsolateResources();
          controller.close();
        }
      }
    });

    _errorPort!.listen((dynamic errorData) async {
      final errorMsg = errorData is List && errorData.isNotEmpty
          ? errorData.first.toString()
          : 'Error inesperado en el Isolate de conversión.';

      await _sandboxCleaner.deleteTempFile(_activeTempFilePath);

      if (!controller.isClosed) {
        controller.add(
          ImageToPdfProgressEvent(
            stage: ConversionStage.failed,
            currentIndex: 0,
            totalImages: config.imagePaths.length,
            errorMessage: errorMsg,
          ),
        );
        await controller.close();
      }
      _disposeIsolateResources();
    });

    Isolate.spawn<ImageToPdfIsolateRequest>(
      _isolateEntryPoint,
      ImageToPdfIsolateRequest(
        mainSendPort: _receivePort!.sendPort,
        config: config,
      ),
      onError: _errorPort!.sendPort,
      debugName: 'LocalConvert_ImageToPdf_RustFFI_Isolate',
    ).then((isolate) {
      _activeIsolate = isolate;
    }).catchError((Object error) async {
      await _sandboxCleaner.deleteTempFile(_activeTempFilePath);
      if (!controller.isClosed) {
        controller.add(
          ImageToPdfProgressEvent(
            stage: ConversionStage.failed,
            currentIndex: 0,
            totalImages: config.imagePaths.length,
            errorMessage: 'No se pudo iniciar el Isolate: $error',
          ),
        );
        await controller.close();
      }
      _disposeIsolateResources();
    });

    controller.onCancel = () {
      if (_activeIsolate != null) {
        cancel();
      }
    };

    return controller.stream;
  }

  /// Aborta inmediatamente el [Isolate] en ejecución y elimina residuos del Sandbox.
  Future<void> cancel() async {
    final tempPathToDelete = _activeTempFilePath;
    _disposeIsolateResources();
    if (tempPathToDelete != null) {
      await _sandboxCleaner.deleteTempFile(tempPathToDelete);
    }
  }

  void _disposeIsolateResources() {
    _activeIsolate?.kill(priority: Isolate.immediate);
    _activeIsolate = null;
    _receivePort?.close();
    _receivePort = null;
    _errorPort?.close();
    _errorPort = null;
    _activeTempFilePath = null;
  }

  @pragma('vm:entry-point')
  static Future<void> _isolateEntryPoint(
    ImageToPdfIsolateRequest request,
  ) async {
    final sendPort = request.mainSendPort;
    final config = request.config;
    final total = config.imagePaths.length;

    try {
      if (total == 0) {
        Isolate.exit(
          sendPort,
          const ImageToPdfProgressEvent(
            stage: ConversionStage.failed,
            currentIndex: 0,
            totalImages: 0,
            errorMessage: 'No se seleccionaron imágenes para convertir.',
          ),
        );
      }

      sendPort.send(
        ImageToPdfProgressEvent(
          stage: ConversionStage.initializing,
          currentIndex: 0,
          totalImages: total,
        ),
      );

      for (int i = 0; i < total; i++) {
        final imagePath = config.imagePaths[i];
        final fileName = p.basename(imagePath);

        if (!await File(imagePath).exists()) {
          throw FileSystemException(
            'El archivo de origen no existe o no es accesible',
            imagePath,
          );
        }

        sendPort.send(
          ImageToPdfProgressEvent(
            stage: ConversionStage.processingImage,
            currentIndex: i + 1,
            totalImages: total,
            currentFileName: fileName,
          ),
        );
      }

      sendPort.send(
        ImageToPdfProgressEvent(
          stage: ConversionStage.writingPdf,
          currentIndex: total,
          totalImages: total,
        ),
      );

      final result = LocalConvertRustBridge.invokeJsonSync({
        'action': 'images_to_pdf',
        'image_paths': config.imagePaths,
        'output_file_path': config.outputFilePath,
        'page_size': config.pageSize.name,
        'orientation': config.orientation.name,
        'margin_points': config.margin.points,
        'jpeg_quality': config.jpegQuality,
        'max_dimension_px': config.maxDimensionPx,
      });

      final outputFile = File(config.outputFilePath);
      final outputBytesLen = (result['output_size_bytes'] as num?)?.toInt() ??
          await outputFile.length();

      Isolate.exit(
        sendPort,
        ImageToPdfProgressEvent(
          stage: ConversionStage.completed,
          currentIndex: total,
          totalImages: total,
          outputFilePath: outputFile.path,
          outputSizeBytes: outputBytesLen,
        ),
      );
    } catch (e) {
      try {
        final partialFile = File(config.outputFilePath);
        if (partialFile.existsSync()) {
          partialFile.deleteSync();
        }
      } catch (_) {}

      Isolate.exit(
        sendPort,
        ImageToPdfProgressEvent(
          stage: ConversionStage.failed,
          currentIndex: 0,
          totalImages: total,
          errorMessage: e.toString(),
        ),
      );
    }
  }
}
