import 'dart:io';

import 'package:path/path.dart' as p;

import '../../shared/models/tool_item.dart';

/// Ruta resuelta desde argumentos de línea de comandos (ej. *"Abrir con"* o
/// menú contextual del Explorador de Windows).
class CliLaunchRoute {
  final ToolId toolId;
  final ToolCategory category;
  final List<String> filePaths;

  const CliLaunchRoute({
    required this.toolId,
    required this.category,
    required this.filePaths,
  });
}

/// Analiza los argumentos CLI recibidos al iniciar `local_convert.exe` y determina
/// automáticamente qué herramienta abrir y qué archivos precargar en su workspace.
class CliLaunchRouter {
  const CliLaunchRouter._();

  static const Set<String> _imageExts = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.tiff',
    '.tif',
    '.gif',
    '.ico',
    '.tga',
    '.svg',
  };

  static const Set<String> _spreadsheetExts = {
    '.xlsx',
    '.xls',
    '.ods',
    '.xlsm',
    '.xlsb',
  };
  static const Set<String> _docxExts = {'.docx'};
  static const Set<String> _structuredExts = {'.csv', '.json', '.xml'};
  static const Set<String> _markdownExts = {'.md', '.markdown', '.txt'};
  static const Set<String> _ebookExts = {'.epub', '.html', '.htm'};
  static const Set<String> _audioExts = {
    '.mp3',
    '.wav',
    '.flac',
    '.ogg',
    '.opus',
    '.m4a',
  };
  static const Set<String> _videoExts = {'.mp4', '.mkv', '.webm', '.mov', '.avi'};

  /// Resuelve la herramienta recomendada a partir de rutas pasadas por CLI.
  ///
  /// Cuando [verifyExists] es `true` (en tiempo de ejecución real), descarta banderas
  /// o rutas inexistentes en disco. En pruebas unitarias puede usarse `verifyExists: false`.
  static CliLaunchRoute? resolveFromArgs(
    List<String> args, {
    bool verifyExists = true,
  }) {
    if (args.isEmpty) return null;

    final resolvedPaths = <String>[];
    for (final raw in args) {
      final trimmed = raw.trim().replaceAll('"', '');
      if (trimmed.isEmpty || trimmed.startsWith('-')) continue;
      if (verifyExists) {
        final file = File(trimmed);
        if (!file.existsSync()) continue;
        resolvedPaths.add(file.absolute.path);
      } else {
        resolvedPaths.add(trimmed);
      }
    }

    if (resolvedPaths.isEmpty) return null;

    final primaryExt = p.extension(resolvedPaths.first).toLowerCase();

    if (primaryExt == '.pdf') {
      final pdfPaths = resolvedPaths
          .where((path) => p.extension(path).toLowerCase() == '.pdf')
          .toList();
      final toolId = pdfPaths.length >= 2 ? ToolId.mergePdf : ToolId.splitPdf;
      return CliLaunchRoute(
        toolId: toolId,
        category: ToolCategory.pdf,
        filePaths: pdfPaths,
      );
    }

    if (_imageExts.contains(primaryExt)) {
      final imagePaths = resolvedPaths
          .where((path) => _imageExts.contains(p.extension(path).toLowerCase()))
          .toList();
      return CliLaunchRoute(
        toolId: ToolId.imageFormatConverter,
        category: ToolCategory.images,
        filePaths: imagePaths,
      );
    }

    if (_spreadsheetExts.contains(primaryExt)) {
      return CliLaunchRoute(
        toolId: ToolId.spreadsheetConverter,
        category: ToolCategory.documents,
        filePaths: [resolvedPaths.first],
      );
    }

    if (_docxExts.contains(primaryExt)) {
      return CliLaunchRoute(
        toolId: ToolId.docxConverter,
        category: ToolCategory.documents,
        filePaths: [resolvedPaths.first],
      );
    }

    if (_structuredExts.contains(primaryExt)) {
      return CliLaunchRoute(
        toolId: ToolId.structuredDataConverter,
        category: ToolCategory.documents,
        filePaths: [resolvedPaths.first],
      );
    }

    if (_markdownExts.contains(primaryExt)) {
      return CliLaunchRoute(
        toolId: ToolId.markdownToPdf,
        category: ToolCategory.documents,
        filePaths: [resolvedPaths.first],
      );
    }

    if (_ebookExts.contains(primaryExt)) {
      return CliLaunchRoute(
        toolId: ToolId.ebookToPdf,
        category: ToolCategory.documents,
        filePaths: [resolvedPaths.first],
      );
    }

    if (_audioExts.contains(primaryExt)) {
      final audioPaths = resolvedPaths
          .where((path) => _audioExts.contains(p.extension(path).toLowerCase()))
          .toList();
      return CliLaunchRoute(
        toolId: ToolId.audioConverter,
        category: ToolCategory.multimedia,
        filePaths: audioPaths,
      );
    }

    if (_videoExts.contains(primaryExt)) {
      return CliLaunchRoute(
        toolId: ToolId.videoConverter,
        category: ToolCategory.multimedia,
        filePaths: [resolvedPaths.first],
      );
    }

    return null;
  }
}
