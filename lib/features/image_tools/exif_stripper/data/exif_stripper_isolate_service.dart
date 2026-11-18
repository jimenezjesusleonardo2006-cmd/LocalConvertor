import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../../format_converter/data/image_format_isolate_service.dart';
import '../../format_converter/domain/image_format_config.dart';
import '../domain/exif_stripper_config.dart';

/// Servicio local por lotes en [Isolate] que inspecciona y elimina metadatos
/// sensibles (EXIF, GPS, cámara, software, fechas, ICC/textData) sin salir del equipo.
class ExifStripperIsolateService {
  final SandboxCleanerService _sandboxCleaner;

  Isolate? _activeIsolate;
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  String? _activeSessionDir;

  ExifStripperIsolateService({
    required SandboxCleanerService sandboxCleaner,
  }) : _sandboxCleaner = sandboxCleaner;

  /// Extrae un resumen legible de las etiquetas EXIF/textData detectadas en [bytes].
  static List<String> inspectExifTags(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [];

    final tags = <String>[];
    final exif = decoded.exif;

    for (final dirName in exif.directories.keys) {
      final directory = exif.directories[dirName];
      if (directory == null) continue;
      for (final tagId in directory.keys) {
        final name = exif.getTagName(tagId);
        final label = name == '<unknown>'
            ? 'Tag 0x${tagId.toRadixString(16).toUpperCase()}'
            : name;
        final value = directory[tagId];
        tags.add('$dirName/$label: $value');
      }
      for (final subName in directory.sub.keys) {
        final subDir = directory.sub[subName];
        for (final tagId in subDir.keys) {
          final name = exif.getTagName(tagId);
          final label = name == '<unknown>'
              ? 'Tag 0x${tagId.toRadixString(16).toUpperCase()}'
              : name;
          final value = subDir[tagId];
          tags.add('$dirName.$subName/$label: $value');
        }
      }
    }

    if (decoded.textData != null) {
      decoded.textData!.forEach((k, v) {
        tags.add('text/$k: $v');
      });
    }

    return tags;
  }

  /// Decodifica, hornea orientación visual, limpia todo contenedor EXIF/ICC/texto
  /// y re-codifica la imagen en limpio.
  static ({Uint8List bytes, List<String> removedTags}) stripMetadataBytes(
    Uint8List rawBytes, {
    required String extension,
    int maxDimensionPx = 4096,
    int jpegQuality = 95,
  }) {
    final removedTags = inspectExifTags(rawBytes);
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw const FormatException('No se pudo decodificar la imagen.');
    }

    var clean = img.bakeOrientation(decoded);
    if (clean.width > maxDimensionPx || clean.height > maxDimensionPx) {
      clean = clean.width >= clean.height
          ? img.copyResize(clean, width: maxDimensionPx)
          : img.copyResize(clean, height: maxDimensionPx);
    }

    clean.exif.clear();
    clean.exif.thumbnailData = null;
    clean.iccProfile = null;
    clean.textData = null;

    final normalizedExt = extension.toLowerCase();
    Uint8List outBytes;
    if (normalizedExt == '.png') {
      outBytes = Uint8List.fromList(img.encodePng(clean, level: 6));
    } else if (normalizedExt == '.webp') {
      outBytes = ImageFormatIsolateService.encodeImageToFormat(
        image: clean,
        targetFormat: TargetImageFormat.webp,
        quality: jpegQuality,
      );
    } else if (normalizedExt == '.tif' || normalizedExt == '.tiff') {
      outBytes = Uint8List.fromList(img.encodeTiff(clean));
    } else {
      img.Image target = clean;
      if (clean.hasAlpha) {
        final whiteBg = img.Image(width: clean.width, height: clean.height);
        img.fill(whiteBg, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(whiteBg, clean);
        target = whiteBg;
      }
      outBytes = Uint8List.fromList(
        img.encodeJpg(target, quality: jpegQuality.clamp(50, 100)),
      );
    }

    return (bytes: outBytes, removedTags: removedTags);
  }

  Stream<ExifStripperProgressEvent> stripBatch(
    ExifStripperBatchConfig config,
  ) {
    cancel();

    final controller = StreamController<ExifStripperProgressEvent>();
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _activeSessionDir = config.sessionDirPath;

    _receivePort!.listen((dynamic message) {
      if (message is ExifStripperProgressEvent) {
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
          ExifStripperProgressEvent(
            currentIndex: 0,
            totalFiles: config.inputPaths.length,
            statusMessage: 'Fallo en el Isolate limpiador de EXIF.',
            errorMessage: err.toString(),
          ),
        );
        await controller.close();
      }
      _disposeIsolate();
    });

    Isolate.spawn<ExifStripperIsolateRequest>(
      _isolateEntryPoint,
      ExifStripperIsolateRequest(
        sendPort: _receivePort!.sendPort,
        config: config,
      ),
      onError: _errorPort!.sendPort,
      debugName: 'LocalConvert_ExifStripper_Isolate',
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
    ExifStripperIsolateRequest request,
  ) async {
    final sendPort = request.sendPort;
    final config = request.config;
    final total = config.inputPaths.length;
    final outputPaths = <String>[];
    final perFileTags = <String, List<String>>{};
    int totalTags = 0;

    try {
      for (int i = 0; i < total; i++) {
        final inputPath = config.inputPaths[i];
        final fileName = p.basename(inputPath);
        final ext = p.extension(inputPath).toLowerCase();
        final baseName = p.basenameWithoutExtension(inputPath);

        sendPort.send(
          ExifStripperProgressEvent(
            currentIndex: i + 1,
            totalFiles: total,
            statusMessage:
                'Limpiando metadatos (${i + 1}/$total): $fileName...',
          ),
        );

        final rawBytes = await File(inputPath).readAsBytes();
        final cleaned = stripMetadataBytes(
          rawBytes,
          extension: ext,
          maxDimensionPx: config.maxDimensionPx,
          jpegQuality: config.jpegQuality,
        );

        perFileTags[fileName] = cleaned.removedTags;
        totalTags += cleaned.removedTags.length;

        final outExt =
            (ext == '.png' || ext == '.webp' || ext == '.tif' || ext == '.tiff')
                ? ext
                : '.jpg';
        final outPath = p.join(
          config.sessionDirPath,
          '${baseName}_sin_exif_${i + 1}$outExt',
        );
        await File(outPath).writeAsBytes(cleaned.bytes, flush: true);
        outputPaths.add(outPath);
      }

      String? zipPath;
      if (config.packageAsZip || outputPaths.length > 1) {
        sendPort.send(
          ExifStripperProgressEvent(
            currentIndex: total,
            totalFiles: total,
            statusMessage: 'Empaquetando imágenes limpias en .ZIP...',
          ),
        );

        final archive = Archive();
        for (final path in outputPaths) {
          final bytes = await File(path).readAsBytes();
          archive.addFile(ArchiveFile(p.basename(path), bytes.length, bytes));
        }

        final zipBytes = ZipEncoder().encode(archive);
        zipPath = p.join(
          config.sessionDirPath,
          'LocalConvert_Sin_Metadatos_EXIF.zip',
        );
        await File(zipPath).writeAsBytes(zipBytes, flush: true);
      }

      Isolate.exit(
        sendPort,
        ExifStripperProgressEvent(
          currentIndex: total,
          totalFiles: total,
          statusMessage:
              'Limpieza completada ($total archivos, $totalTags etiquetas eliminadas).',
          isCompleted: true,
          outputFiles: outputPaths,
          zipFilePath: zipPath,
          totalTagsRemoved: totalTags,
          perFileRemovedTags: perFileTags,
        ),
      );
    } catch (e) {
      Isolate.exit(
        sendPort,
        ExifStripperProgressEvent(
          currentIndex: 0,
          totalFiles: total,
          statusMessage: 'Error durante la limpieza de metadatos.',
          errorMessage: e.toString(),
        ),
      );
    }
  }
}
