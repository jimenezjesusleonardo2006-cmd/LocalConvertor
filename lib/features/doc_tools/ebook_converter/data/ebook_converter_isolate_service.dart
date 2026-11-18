import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import '../../../../core/utils/pdf_font_asset_loader.dart';
import '../domain/ebook_converter_config.dart';

/// Servicio local en [Isolate] que extrae contenido limpio desde `.epub` (ZIP + XML/OPF)
/// y archivos `.html`/`.htm`, generando documentos `.txt` o `.pdf` paginados sin red.
class EbookConverterIsolateService {
  Future<EbookConversionResult> convertInIsolate(EbookConverterConfig config) {
    return Isolate.run(() => _convertEntryPoint(config));
  }

  /// Extrae título, número de capítulos y bloques estructurales desde un archivo `.epub`.
  static ({String title, int chapterCount, List<EbookContentBlock> blocks})
      extractFromEpubBytes(Uint8List epubBytes) {
    final archive = ZipDecoder().decodeBytes(epubBytes);
    final fileByPath = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) {
        fileByPath[file.name.replaceAll('\\', '/')] = file;
      }
    }

    String? opfPath;
    final containerFile = fileByPath['META-INF/container.xml'];
    if (containerFile != null) {
      final containerXml = utf8.decode(
        containerFile.content as List<int>,
        allowMalformed: true,
      );
      final containerDoc = XmlDocument.parse(containerXml);
      final rootfile = containerDoc.findAllElements('rootfile').firstOrNull;
      opfPath = rootfile?.getAttribute('full-path');
    }

    opfPath ??= fileByPath.keys
        .where((k) => k.toLowerCase().endsWith('.opf'))
        .firstOrNull;

    String title = 'Documento EPUB';
    final chapterPaths = <String>[];

    if (opfPath != null && fileByPath.containsKey(opfPath)) {
      final opfXml = utf8.decode(
        fileByPath[opfPath]!.content as List<int>,
        allowMalformed: true,
      );
      final opfDoc = XmlDocument.parse(opfXml);
      final titleElem = opfDoc
          .findAllElements('title')
          .followedBy(opfDoc.findAllElements('dc:title'))
          .firstOrNull;
      if (titleElem != null && titleElem.innerText.trim().isNotEmpty) {
        title = titleElem.innerText.trim();
      }

      final opfDir = p.posix.dirname(opfPath);
      final manifestHrefById = <String, String>{};
      for (final item in opfDoc.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        final mediaType = item.getAttribute('media-type') ?? '';
        if (id != null &&
            href != null &&
            (mediaType.contains('html') ||
                href.toLowerCase().endsWith('.html') ||
                href.toLowerCase().endsWith('.xhtml') ||
                href.toLowerCase().endsWith('.htm'))) {
          final resolved = opfDir == '.'
              ? href
              : p.posix.normalize(p.posix.join(opfDir, href));
          manifestHrefById[id] = resolved;
        }
      }

      for (final itemref in opfDoc.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        final resolved = idref != null ? manifestHrefById[idref] : null;
        if (resolved != null && fileByPath.containsKey(resolved)) {
          chapterPaths.add(resolved);
        }
      }
    }

    if (chapterPaths.isEmpty) {
      chapterPaths.addAll(
        fileByPath.keys.where((k) {
          final low = k.toLowerCase();
          return low.endsWith('.xhtml') ||
              low.endsWith('.html') ||
              low.endsWith('.htm');
        }),
      );
    }

    final blocks = <EbookContentBlock>[
      EbookContentBlock(type: EbookBlockType.title, text: title),
    ];

    for (final path in chapterPaths) {
      final chapterFile = fileByPath[path];
      if (chapterFile == null) continue;
      final html = utf8.decode(
        chapterFile.content as List<int>,
        allowMalformed: true,
      );
      final parsed = parseHtmlToBlocks(html);
      blocks.addAll(parsed.blocks.where((b) => b.type != EbookBlockType.title));
    }

    return (
      title: title,
      chapterCount: chapterPaths.length,
      blocks: blocks,
    );
  }

  /// Convierte código HTML o XHTML a bloques estructurados y título detectado.
  static ({String title, List<EbookContentBlock> blocks}) parseHtmlToBlocks(
    String htmlSource,
  ) {
    final titleMatch = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(htmlSource);
    var docTitle = titleMatch != null
        ? _cleanInlineHtml(titleMatch.group(1)!)
        : '';

    var body = htmlSource;
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*?)</body>',
      caseSensitive: false,
    ).firstMatch(htmlSource);
    if (bodyMatch != null) {
      body = bodyMatch.group(1)!;
    }

    body = body
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<head[^>]*>[\s\S]*?</head>', caseSensitive: false),
          '',
        );

    final blocks = <EbookContentBlock>[];
    if (docTitle.isNotEmpty) {
      blocks.add(EbookContentBlock(type: EbookBlockType.title, text: docTitle));
    }

    final blockPattern = RegExp(
      r'<(h[1-6]|p|li|blockquote|pre|div)\b[^>]*>([\s\S]*?)</\1>',
      caseSensitive: false,
    );

    final matches = blockPattern.allMatches(body).toList();
    if (matches.isEmpty) {
      final plain = _cleanInlineHtml(
        body.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
      );
      for (final line in plain.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          blocks.add(
            EbookContentBlock(type: EbookBlockType.paragraph, text: trimmed),
          );
        }
      }
    } else {
      for (final m in matches) {
        final tag = m.group(1)!.toLowerCase();
        final inner = m.group(2)!;
        // Evitar duplicar <div> que solo envuelve bloques hijos ya capturados
        if (tag == 'div' &&
            RegExp(r'<(h[1-6]|p|li|blockquote|pre)\b', caseSensitive: false)
                .hasMatch(inner)) {
          continue;
        }
        final text = tag == 'pre'
            ? _decodeHtmlEntities(inner.replaceAll(RegExp(r'<[^>]+>'), '')).trim()
            : _cleanInlineHtml(inner);
        if (text.isEmpty) continue;

        final blockType = switch (tag) {
          'h1' => EbookBlockType.heading1,
          'h2' => EbookBlockType.heading2,
          'h3' || 'h4' || 'h5' || 'h6' => EbookBlockType.heading3,
          'li' => EbookBlockType.listItem,
          'blockquote' => EbookBlockType.quote,
          'pre' => EbookBlockType.code,
          _ => EbookBlockType.paragraph,
        };
        if (docTitle.isEmpty && blockType == EbookBlockType.heading1) {
          docTitle = text;
        }
        blocks.add(EbookContentBlock(type: blockType, text: text));
      }
    }

    return (
      title: docTitle.isEmpty ? 'Documento HTML' : docTitle,
      blocks: blocks,
    );
  }

  static String blocksToCleanText(List<EbookContentBlock> blocks) {
    final buf = StringBuffer();
    for (final block in blocks) {
      switch (block.type) {
        case EbookBlockType.title:
          buf.writeln(block.text.toUpperCase());
          buf.writeln('=' * block.text.length.clamp(4, 48));
          buf.writeln();
        case EbookBlockType.heading1:
          buf.writeln('\n# ${block.text}');
          buf.writeln('-' * block.text.length.clamp(4, 40));
        case EbookBlockType.heading2:
          buf.writeln('\n## ${block.text}');
        case EbookBlockType.heading3:
          buf.writeln('\n### ${block.text}');
        case EbookBlockType.listItem:
          buf.writeln('  • ${block.text}');
        case EbookBlockType.quote:
          buf.writeln('  > ${block.text}');
        case EbookBlockType.code:
          buf.writeln('\n```');
          buf.writeln(block.text);
          buf.writeln('```\n');
        case EbookBlockType.paragraph:
          buf.writeln(block.text);
          buf.writeln();
      }
    }
    return buf.toString().trim();
  }

  static Future<EbookConversionResult> _convertEntryPoint(
    EbookConverterConfig config,
  ) async {
    late final String title;
    late final int chapters;
    late final List<EbookContentBlock> blocks;

    if (config.rawHtmlOverride != null && config.rawHtmlOverride!.isNotEmpty) {
      final parsed = parseHtmlToBlocks(config.rawHtmlOverride!);
      title = parsed.title;
      chapters = 1;
      blocks = parsed.blocks;
    } else if (config.sourceFilePath != null) {
      final file = File(config.sourceFilePath!);
      final ext = p.extension(config.sourceFilePath!).toLowerCase();
      if (ext == '.epub') {
        final bytes = await file.readAsBytes();
        final parsed = extractFromEpubBytes(bytes);
        title = parsed.title;
        chapters = parsed.chapterCount;
        blocks = parsed.blocks;
      } else {
        final html = await file.readAsString();
        final parsed = parseHtmlToBlocks(html);
        title = parsed.title;
        chapters = 1;
        blocks = parsed.blocks;
      }
    } else {
      throw const FormatException('No se proporcionó ningún archivo o HTML.');
    }

    final cleanText = blocksToCleanText(blocks);
    late final Uint8List outBytes;

    if (config.targetFormat == EbookTargetFormat.txt) {
      outBytes = Uint8List.fromList(utf8.encode(cleanText));
    } else {
      outBytes = await _compileBlocksToPdf(
        title: title,
        blocks: blocks,
        fontScale: config.fontScale,
        includePageNumbers: config.includePageNumbers,
        fontBundle: config.fontBundle,
      );
    }

    final outFile = File(config.outputFilePath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(outBytes, flush: true);

    return EbookConversionResult(
      outputFilePath: config.outputFilePath,
      extractedTitle: title,
      chapterCount: chapters,
      characterCount: cleanText.length,
      previewText: cleanText,
    );
  }

  static Future<Uint8List> _compileBlocksToPdf({
    required String title,
    required List<EbookContentBlock> blocks,
    required double fontScale,
    required bool includePageNumbers,
    PdfFontBundle? fontBundle,
  }) async {
    final themeBundle = PdfFontAssetLoader.buildPdfTheme(fontBundle);
    final doc = pw.Document(
      version: PdfVersion.pdf_1_5,
      compress: true,
      title: title,
      producer: 'LocalConvert HTML/EPUB Engine',
      theme: themeBundle.theme,
    );

    final widgets = <pw.Widget>[];
    for (final block in blocks) {
      switch (block.type) {
        case EbookBlockType.title:
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  fontSize: 22 * fontScale,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal900,
                ),
              ),
            ),
          );
        case EbookBlockType.heading1:
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  fontSize: 18 * fontScale,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal800,
                ),
              ),
            ),
          );
        case EbookBlockType.heading2:
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  fontSize: 14.5 * fontScale,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          );
        case EbookBlockType.heading3:
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  fontSize: 12.5 * fontScale,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          );
        case EbookBlockType.listItem:
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 14, bottom: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '•  ',
                    style: pw.TextStyle(
                      fontSize: 11 * fontScale,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal700,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      block.text,
                      style: pw.TextStyle(
                        fontSize: 11 * fontScale,
                        lineSpacing: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        case EbookBlockType.quote:
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 6),
              padding: const pw.EdgeInsets.fromLTRB(12, 8, 10, 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.teal600, width: 3),
                ),
              ),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  fontSize: 10.5 * fontScale,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey800,
                ),
              ),
            ),
          );
        case EbookBlockType.code:
          widgets.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.symmetric(vertical: 6),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  font: themeBundle.monoFont,
                  fontSize: 9.5 * fontScale,
                ),
              ),
            ),
          );
        case EbookBlockType.paragraph:
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                block.text,
                style: pw.TextStyle(
                  fontSize: 11 * fontScale,
                  lineSpacing: 3.2,
                ),
              ),
            ),
          );
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        footer: includePageNumbers
            ? (ctx) => pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
                )
            : null,
        build: (_) => widgets,
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  static String _cleanInlineHtml(String raw) {
    final withoutBreaks =
        raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final stripped = withoutBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeHtmlEntities(stripped).replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static String _decodeHtmlEntities(String input) {
    var out = input
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&copy;', '©')
        .replaceAll('&euro;', '€')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&bull;', '•')
        .replaceAll('&aacute;', 'á')
        .replaceAll('&eacute;', 'é')
        .replaceAll('&iacute;', 'í')
        .replaceAll('&oacute;', 'ó')
        .replaceAll('&uacute;', 'ú')
        .replaceAll('&ntilde;', 'ñ')
        .replaceAll('&Ntilde;', 'Ñ');

    out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) {
        final code = int.tryParse(m.group(1)!);
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      },
    );
    out = out.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) {
        final code = int.tryParse(m.group(1)!, radix: 16);
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      },
    );
    return out;
  }
}
