import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Utilidad compartida para exportar archivos generados en el Sandbox local
/// mediante los diálogos nativos de `file_picker` sin opciones deprecadas.
class LocalFileExporter {
  const LocalFileExporter._();

  /// Resuelve el MIME type estándar a partir de la extensión del archivo.
  static String mimeTypeForExtension(String ext) {
    switch (ext.toLowerCase().replaceFirst('.', '')) {
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'ico':
        return 'image/x-icon';
      case 'gif':
        return 'image/gif';
      case 'tga':
        return 'image/x-tga';
      case 'svg':
        return 'image/svg+xml';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'txt':
        return 'text/plain';
      case 'md':
      case 'markdown':
        return 'text/markdown';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'epub':
        return 'application/epub+zip';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'opus':
        return 'audio/opus';
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  /// Abre el diálogo nativo para guardar [bytes] y retorna el [Uri] de destino
  /// o `null` si el usuario canceló la exportación.
  static Future<Uri?> saveBytes({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) {
    final resolvedMime =
        mimeType ?? mimeTypeForExtension(p.extension(fileName));
    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      mimeType: resolvedMime,
      bytes: bytes,
    );
  }

  /// Lee un archivo temporal del Sandbox y lo exporta con el diálogo nativo.
  static Future<Uri?> saveTempFile({
    required String dialogTitle,
    required String fileName,
    required String sourceFilePath,
    String? mimeType,
  }) async {
    final bytes = await File(sourceFilePath).readAsBytes();
    return saveBytes(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  /// Exporta múltiples imágenes temporales hacia una carpeta elegida en Escritorio.
  static Future<bool> exportImagesToDirectory({
    required String dialogTitle,
    required List<String> tempImagePaths,
  }) async {
    final targetDir = await FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
    );
    if (targetDir == null) return false;

    for (final tempImgPath in tempImagePaths) {
      final destPath = p.join(targetDir, p.basename(tempImgPath));
      await File(tempImgPath).copy(destPath);
    }
    return true;
  }
}
