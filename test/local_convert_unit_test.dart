import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:local_convert/core/cli/cli_launch_router.dart';
import 'package:local_convert/core/media/ffmpeg_binary_resolver.dart';
import 'package:local_convert/core/media/ffmpeg_cli_builder.dart';
import 'package:local_convert/core/media/ffmpeg_progress_parser.dart';
import 'package:local_convert/core/media/media_processing_engine.dart';
import 'package:local_convert/core/rust_ffi/local_convert_rust_bridge.dart';
import 'package:local_convert/core/sandbox/sandbox_cleaner_service.dart';
import 'package:local_convert/core/utils/pdf_font_asset_loader.dart';
import 'package:local_convert/features/doc_tools/docx_converter/data/docx_converter_service.dart';
import 'package:local_convert/features/doc_tools/docx_converter/domain/docx_converter_config.dart';
import 'package:local_convert/features/doc_tools/ebook_converter/data/ebook_converter_isolate_service.dart';
import 'package:local_convert/features/doc_tools/ebook_converter/domain/ebook_converter_config.dart';
import 'package:local_convert/features/doc_tools/markdown_to_pdf/data/markdown_to_pdf_isolate_service.dart';
import 'package:local_convert/features/doc_tools/markdown_to_pdf/domain/markdown_to_pdf_config.dart';
import 'package:local_convert/features/doc_tools/spreadsheet_converter/data/spreadsheet_converter_service.dart';
import 'package:local_convert/features/doc_tools/spreadsheet_converter/domain/spreadsheet_converter_config.dart';
import 'package:local_convert/features/doc_tools/structured_data/data/structured_data_isolate_service.dart';
import 'package:local_convert/features/doc_tools/structured_data/domain/structured_data_config.dart';
import 'package:local_convert/features/image_tools/compressor_resizer/data/compressor_resizer_isolate_service.dart';
import 'package:local_convert/features/image_tools/compressor_resizer/domain/compressor_resizer_config.dart';
import 'package:local_convert/features/image_tools/exif_stripper/data/exif_stripper_isolate_service.dart';
import 'package:local_convert/features/image_tools/exif_stripper/domain/exif_stripper_config.dart';
import 'package:local_convert/features/image_tools/format_converter/data/image_format_isolate_service.dart';
import 'package:local_convert/features/image_tools/format_converter/domain/image_format_config.dart';
import 'package:local_convert/features/image_tools/qr_generator/data/qr_generator_service.dart';
import 'package:local_convert/features/image_tools/qr_generator/domain/qr_generator_config.dart';
import 'package:local_convert/features/media_tools/audio_converter/data/audio_converter_service.dart';
import 'package:local_convert/features/media_tools/audio_converter/domain/audio_converter_config.dart';
import 'package:local_convert/features/media_tools/youtube_downloader/domain/youtube_downloader_config.dart';
import 'package:local_convert/features/pdf_tools/compress_pdf/data/compress_pdf_service.dart';
import 'package:local_convert/features/pdf_tools/compress_pdf/domain/compress_pdf_config.dart';
import 'package:local_convert/features/pdf_tools/images_to_pdf/data/image_to_pdf_isolate_service.dart';
import 'package:local_convert/features/pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import 'package:local_convert/features/pdf_tools/merge_pdf/data/merge_pdf_service.dart';
import 'package:local_convert/features/pdf_tools/merge_pdf/domain/merge_pdf_config.dart';
import 'package:local_convert/features/pdf_tools/organize_pdf/data/organize_pdf_service.dart';
import 'package:local_convert/features/pdf_tools/organize_pdf/domain/organize_pdf_config.dart';
import 'package:local_convert/features/pdf_tools/protect_pdf/data/protect_pdf_service.dart';
import 'package:local_convert/features/pdf_tools/protect_pdf/domain/protect_pdf_config.dart';
import 'package:local_convert/features/pdf_tools/split_pdf/data/split_pdf_service.dart';
import 'package:local_convert/features/pdf_tools/split_pdf/domain/page_range_parser.dart';
import 'package:local_convert/features/pdf_tools/split_pdf/domain/split_pdf_config.dart';
import 'package:local_convert/features/pdf_tools/watermark_pdf/data/watermark_pdf_service.dart';
import 'package:local_convert/features/pdf_tools/watermark_pdf/domain/watermark_pdf_config.dart';
import 'package:local_convert/shared/models/tool_item.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

Future<String> _writeVectorPdf(String filePath, List<String> pageTexts) async {
  final doc = sfpdf.PdfDocument();
  final font = sfpdf.PdfStandardFont(sfpdf.PdfFontFamily.helvetica, 14);
  for (final txt in pageTexts) {
    final page = doc.pages.add();
    page.graphics.drawString(
      txt,
      font,
      bounds: const Rect.fromLTWH(40, 40, 400, 100),
    );
  }
  final bytes = await doc.save();
  doc.dispose();
  await File(filePath).writeAsBytes(bytes, flush: true);
  return filePath;
}

void main() {
  group('SandboxCleanerService (Sandbox Local)', () {
    test('crea sesiones efímeras y destruye archivos y directorios por completo',
        () async {
      final baseTemp = await Directory.systemTemp.createTemp('lc_sandbox_unit_');
      try {
        final cleaner = SandboxCleanerService(
          tempDirProvider: () async => baseTemp,
        );

        final sessionDir = await cleaner.createSessionDir('sess_01');
        expect(await sessionDir.exists(), isTrue);

        final tempFile = File(p.join(sessionDir.path, 'intermediate.pdf'));
        await tempFile.writeAsBytes([1, 2, 3]);
        expect(await tempFile.exists(), isTrue);

        await cleaner.deleteTempFile(tempFile.path);
        expect(await tempFile.exists(), isFalse);

        final secondFile = File(p.join(sessionDir.path, 'nested.png'));
        await secondFile.writeAsBytes([4, 5, 6]);
        await cleaner.deleteSessionDir(sessionDir.path);
        expect(await sessionDir.exists(), isFalse);

        await cleaner.createSessionDir('sess_02');
        await cleaner.purgeAll();
        final root = await cleaner.getSandboxRoot();
        expect(root.listSync(), isEmpty);
      } finally {
        if (await baseTemp.exists()) {
          await baseTemp.delete(recursive: true);
        }
      }
    });
  });

  group('PageRangeParser (Dividir PDF)', () {
    test('parsea rangos complejos como "1-3, 5, 8-10" correctamente', () {
      final result = PageRangeParser.parse('1-3, 5, 8-10', maxPages: 12);
      expect(result.isValid, isTrue);
      expect(result.segments.length, 3);
      expect(result.uniqueSortedPages, equals({1, 2, 3, 5, 8, 9, 10}));
    });

    test('detecta errores de rango fuera de límites, invertido o no numérico', () {
      expect(
        PageRangeParser.parse('1-4, 15', maxPages: 10).validationError,
        contains('excede el total'),
      );
      expect(
        PageRangeParser.parse('8-3', maxPages: 10).validationError,
        contains('mayor que la final'),
      );
      expect(
        PageRangeParser.parse('1, abc', maxPages: 10).validationError,
        contains('no numérico'),
      );
      expect(PageRangeParser.parse('', maxPages: 10).isValid, isFalse);
    });

    test('formatea conjunto de páginas hacia cadena compacta de rangos', () {
      final formatted =
          PageRangeParser.formatPagesToRangeString({1, 2, 3, 5, 8, 9, 10});
      expect(formatted, equals('1-3, 5, 8-10'));
    });
  });

  group('ImageToPdfIsolateService (Imágenes a PDF en Isolate)', () {
    test('convierte PNG transparente y JPG a un %PDF-1.5 con progreso determinista',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_img2pdf_');
      try {
        // PNG con canal alfa
        final pngImg = img.Image(width: 24, height: 16, numChannels: 4);
        img.fill(pngImg, color: img.ColorRgba8(229, 50, 45, 180));
        final pngPath = p.join(tempDir.path, 'alpha.png');
        await File(pngPath).writeAsBytes(img.encodePng(pngImg));

        // JPG estándar
        final jpgImg = img.Image(width: 40, height: 30);
        img.fill(jpgImg, color: img.ColorRgb8(37, 99, 235));
        final jpgPath = p.join(tempDir.path, 'photo.jpg');
        await File(jpgPath).writeAsBytes(img.encodeJpg(jpgImg, quality: 90));

        final outPdfPath = p.join(tempDir.path, 'result.pdf');
        final cleaner = SandboxCleanerService(
          tempDirProvider: () async => tempDir,
        );
        final service = ImageToPdfIsolateService(sandboxCleaner: cleaner);

        final events = await service
            .convertImagesToPdf(
              ImageToPdfConfig(
                imagePaths: [pngPath, jpgPath],
                outputFilePath: outPdfPath,
                pageSize: PdfPageSizeOption.fitToImage,
                margin: PdfMarginOption.small,
                maxDimensionPx: 32,
              ),
            )
            .toList();

        expect(events.any((e) => e.stage == ConversionStage.initializing), isTrue);
        expect(
          events.where((e) => e.stage == ConversionStage.processingImage).length,
          equals(2),
        );
        expect(events.last.stage, equals(ConversionStage.completed));
        expect(events.last.progress, equals(1.0));
        expect(await File(outPdfPath).exists(), isTrue);

        final pdfBytes = await File(outPdfPath).readAsBytes();
        expect(String.fromCharCodes(pdfBytes.sublist(0, 8)), startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('ImageFormatIsolateService (PNG, JPG, WEBP, BMP)', () {
    late img.Image testCanvas;

    setUp(() {
      testCanvas = img.Image(width: 16, height: 16);
      img.fill(testCanvas, color: img.ColorRgb8(229, 50, 45));
    });

    test('codifica hacia PNG, JPG, BMP y WEBP con cabeceras válidas', () {
      final pngBytes = ImageFormatIsolateService.encodeImageToFormat(
        image: testCanvas,
        targetFormat: TargetImageFormat.png,
        quality: 90,
      );
      expect(pngBytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));

      final jpgBytes = ImageFormatIsolateService.encodeImageToFormat(
        image: testCanvas,
        targetFormat: TargetImageFormat.jpg,
        quality: 85,
      );
      expect(jpgBytes.sublist(0, 2), equals([0xFF, 0xD8]));

      final bmpBytes = ImageFormatIsolateService.encodeImageToFormat(
        image: testCanvas,
        targetFormat: TargetImageFormat.bmp,
        quality: 90,
      );
      expect(bmpBytes.sublist(0, 2), equals([0x42, 0x4D]));

      final webpBytes = ImageFormatIsolateService.encodeImageToFormat(
        image: testCanvas,
        targetFormat: TargetImageFormat.webp,
        quality: 85,
      );
      expect(webpBytes.sublist(0, 4), equals([0x52, 0x49, 0x46, 0x46]));
      expect(webpBytes.sublist(8, 12), equals([0x57, 0x45, 0x42, 0x50]));
    });

    test('convierte lote de imágenes en Isolate respetando maxDimensionPx y genera ZIP',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_fmt_batch_');
      try {
        final bigImg = img.Image(width: 100, height: 50);
        img.fill(bigImg, color: img.ColorRgb8(13, 148, 136));
        final src1 = p.join(tempDir.path, 'a.png');
        final src2 = p.join(tempDir.path, 'b.png');
        await File(src1).writeAsBytes(img.encodePng(bigImg));
        await File(src2).writeAsBytes(img.encodePng(bigImg));

        final outDir = Directory(p.join(tempDir.path, 'out'))..createSync();
        final cleaner = SandboxCleanerService(
          tempDirProvider: () async => tempDir,
        );
        final service = ImageFormatIsolateService(sandboxCleaner: cleaner);

        final events = await service
            .convertBatch(
              ImageFormatBatchConfig(
                inputPaths: [src1, src2],
                sessionDirPath: outDir.path,
                targetFormat: TargetImageFormat.jpg,
                quality: 80,
                packageAsZip: true,
                maxDimensionPx: 50,
              ),
            )
            .toList();

        final last = events.last;
        expect(last.isCompleted, isTrue);
        expect(last.outputFiles.length, equals(2));
        expect(last.zipFilePath, isNotNull);
        expect(await File(last.zipFilePath!).exists(), isTrue);

        final convertedDecoded =
            img.decodeImage(await File(last.outputFiles.first).readAsBytes());
        expect(convertedDecoded?.width, equals(50));
        expect(convertedDecoded?.height, equals(25));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('CompressorResizerIsolateService (Compresión y Redimensionamiento)', () {
    test('estima dimensiones y peso y procesa lote en Isolate', () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_comp_');
      try {
        final canvas = img.Image(width: 80, height: 40);
        img.fill(canvas, color: img.ColorRgb8(37, 99, 235));
        final srcPath = p.join(tempDir.path, 'sample.jpg');
        await File(srcPath).writeAsBytes(img.encodeJpg(canvas, quality: 98));

        final cleaner = SandboxCleanerService(
          tempDirProvider: () async => tempDir,
        );
        final service = CompressorResizerIsolateService(sandboxCleaner: cleaner);

        final estimate = await service.estimateSingleFile(
          filePath: srcPath,
          resizeMode: ImageResizeMode.percentage,
          scalePercent: 50,
          maintainAspectRatio: true,
          quality: 60,
          maxDimensionPx: 4096,
        );
        expect(estimate, isNotNull);
        expect(estimate!.originalWidth, equals(80));
        expect(estimate.targetWidth, equals(40));
        expect(estimate.targetHeight, equals(20));

        final outDir = Directory(p.join(tempDir.path, 'out'))..createSync();
        final events = await service
            .processBatch(
              CompressorResizerBatchConfig(
                inputPaths: [srcPath],
                sessionDirPath: outDir.path,
                resizeMode: ImageResizeMode.exactDimensions,
                targetWidthPx: 20,
                targetHeightPx: 10,
                maintainAspectRatio: false,
                quality: 75,
                maxDimensionPx: 4096,
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        expect(events.last.outputFiles.length, equals(1));
        final outImg =
            img.decodeImage(await File(events.last.outputFiles.first).readAsBytes());
        expect(outImg?.width, equals(20));
        expect(outImg?.height, equals(10));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('MarkdownToPdfIsolateService (Markdown AST y Unicode TTF a PDF)', () {
    test('carga fuentes Roboto locales y compila Unicode (ñ, tildes, €, •) sin errores',
        () async {
      final fontBundle = PdfFontAssetLoader.loadFromDiskSync();
      expect(fontBundle, isNotNull);

      final tempDir = await Directory.systemTemp.createTemp('lc_md_test_');
      final outPath = p.join(tempDir.path, 'test_md.pdf');

      try {
        final service = MarkdownToPdfIsolateService();
        final path = await service.compileToPdfInIsolate(
          MarkdownToPdfConfig(
            rawContent:
                '# Título con Ñ y €\n\nTexto con **negrita**, *cursiva* y `código`.\n\n- Ítem 1\n- Ítem 2\n\n> Cita offline — LocalConvert\n\n```dart\nprint("Hola");\n```',
            documentTitle: 'Test Doc',
            isMarkdown: true,
            outputPdfPath: outPath,
            fontBundle: fontBundle,
          ),
        );

        final file = File(path);
        expect(await file.exists(), isTrue);
        final bytes = await file.readAsBytes();
        final header = String.fromCharCodes(bytes.sublist(0, 8));
        expect(header, startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('compila texto plano (.txt) en PDF válido', () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_txt_test_');
      final outPath = p.join(tempDir.path, 'plain.pdf');

      try {
        final service = MarkdownToPdfIsolateService();
        final path = await service.compileToPdfInIsolate(
          MarkdownToPdfConfig(
            rawContent: 'Primera línea\n\nSegunda línea con acento: áéíóú ñ.',
            documentTitle: 'Plain',
            isMarkdown: false,
            outputPdfPath: outPath,
            fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
          ),
        );

        final bytes = await File(path).readAsBytes();
        expect(String.fromCharCodes(bytes.sublist(0, 8)), startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Fase 1: MergePdfService y SplitPdfService con preservación vectorial',
      () {
    test('MergePdfService une PDFs conservando texto seleccionable y vectores',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_vec_merge_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final doc1 = await _writeVectorPdf(
          p.join(tempDir.path, 'doc1.pdf'),
          ['Documento Vectorial Uno'],
        );
        final doc2 = await _writeVectorPdf(
          p.join(tempDir.path, 'doc2.pdf'),
          ['Documento Vectorial Dos'],
        );
        final mergedOut = p.join(tempDir.path, 'merged.pdf');

        final service = MergePdfService(sandboxCleaner: cleaner);
        final events = await service
            .mergeDocuments(
              documents: [
                MergePdfDocumentItem(
                  id: '1',
                  filePath: doc1,
                  fileName: 'doc1.pdf',
                  pageCount: 1,
                ),
                MergePdfDocumentItem(
                  id: '2',
                  filePath: doc2,
                  fileName: 'doc2.pdf',
                  pageCount: 1,
                ),
              ],
              outputPdfPath: mergedOut,
              qualityPreset: MergePdfQualityPreset.balanced,
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        final mergedDoc = sfpdf.PdfDocument(
          inputBytes: await File(mergedOut).readAsBytes(),
        );
        try {
          expect(mergedDoc.pages.count, equals(2));
          final text = sfpdf.PdfTextExtractor(mergedDoc).extractText();
          expect(text, contains('Documento Vectorial Uno'));
          expect(text, contains('Documento Vectorial Dos'));
        } finally {
          mergedDoc.dispose();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('SplitPdfService extrae páginas conservando texto seleccionable',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_vec_split_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final src = await _writeVectorPdf(
          p.join(tempDir.path, 'multi.pdf'),
          ['Primera Pagina Vectorial', 'Segunda Pagina Vectorial'],
        );
        final sessionDir = Directory(p.join(tempDir.path, 'sess'))..createSync();
        final parsed = PageRangeParser.parse('2', maxPages: 2);

        final service = SplitPdfService(sandboxCleaner: cleaner);
        final events = await service
            .splitPdf(
              SplitPdfConfig(
                sourcePdfPath: src,
                sessionDirPath: sessionDir.path,
                segments: parsed.segments,
                uniquePagesToExtract: parsed.uniqueSortedPages,
                outputMode: SplitOutputMode.singleCombinedPdf,
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        final outPath = events.last.singleOutputPdfPath!;
        final outDoc = sfpdf.PdfDocument(
          inputBytes: await File(outPath).readAsBytes(),
        );
        try {
          expect(outDoc.pages.count, equals(1));
          final extracted = sfpdf.PdfTextExtractor(outDoc).extractText();
          expect(extracted, contains('Segunda Pagina Vectorial'));
          expect(extracted, isNot(contains('Primera Pagina Vectorial')));
        } finally {
          outDoc.dispose();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Fase 2.1: Nuevas herramientas PDF (Organizar, Proteger, Marca, Comprimir)',
      () {
    test('OrganizePdfService reordena y rota páginas manteniendo texto',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_org_pdf_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final src = await _writeVectorPdf(
          p.join(tempDir.path, 'src.pdf'),
          ['Pagina Alfa', 'Pagina Beta'],
        );
        final outPath = p.join(tempDir.path, 'org.pdf');
        final service = OrganizePdfService(sandboxCleaner: cleaner);

        final events = await service
            .organizePdf(
              OrganizePdfConfig(
                sourcePdfPath: src,
                outputPdfPath: outPath,
                pages: const [
                  OrganizePdfPageItem(
                    id: 1,
                    originalPageIndex: 1,
                    rotationDeltaDegrees: 90,
                  ),
                  OrganizePdfPageItem(
                    id: 0,
                    originalPageIndex: 0,
                    rotationDeltaDegrees: 0,
                  ),
                ],
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        final doc = sfpdf.PdfDocument(
          inputBytes: await File(outPath).readAsBytes(),
        );
        try {
          expect(doc.pages.count, equals(2));
          expect(
            sfpdf.PdfTextExtractor(doc).extractText(startPageIndex: 0, endPageIndex: 0),
            contains('Pagina Beta'),
          );
          expect(
            sfpdf.PdfTextExtractor(doc).extractText(startPageIndex: 1, endPageIndex: 1),
            contains('Pagina Alfa'),
          );
        } finally {
          doc.dispose();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('ProtectPdfService cifra con contraseña y desbloquea con clave actual',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_prot_pdf_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final src = await _writeVectorPdf(
          p.join(tempDir.path, 'plain.pdf'),
          ['Secreto LocalConvert'],
        );
        final locked = p.join(tempDir.path, 'locked.pdf');
        final unlocked = p.join(tempDir.path, 'unlocked.pdf');
        final service = ProtectPdfService(sandboxCleaner: cleaner);

        await service.processPdf(
          ProtectPdfConfig(
            sourcePdfPath: src,
            outputPdfPath: locked,
            mode: ProtectPdfMode.encrypt,
            userPassword: 'clave123',
            cipherLevel: PdfCipherLevel.aes128,
          ),
        );

        final lockedBytes = await File(locked).readAsBytes();
        expect(
          () => sfpdf.PdfDocument(inputBytes: lockedBytes),
          throwsA(anything),
        );

        final withPw = sfpdf.PdfDocument(
          inputBytes: lockedBytes,
          password: 'clave123',
        );
        expect(withPw.pages.count, equals(1));
        withPw.dispose();

        await service.processPdf(
          ProtectPdfConfig(
            sourcePdfPath: locked,
            outputPdfPath: unlocked,
            mode: ProtectPdfMode.unlock,
            currentPassword: 'clave123',
          ),
        );

        final unlockedDoc = sfpdf.PdfDocument(
          inputBytes: await File(unlocked).readAsBytes(),
        );
        expect(unlockedDoc.pages.count, equals(1));
        unlockedDoc.dispose();
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('WatermarkPdfService estampa texto Unicode con PdfFontAssetLoader',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_wm_pdf_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final src = await _writeVectorPdf(
          p.join(tempDir.path, 'src.pdf'),
          ['Documento Base'],
        );
        final out = p.join(tempDir.path, 'wm.pdf');
        final service = WatermarkPdfService(sandboxCleaner: cleaner);

        await service.applyWatermark(
          WatermarkPdfConfig(
            sourcePdfPath: src,
            outputPdfPath: out,
            type: WatermarkType.text,
            text: 'CONFIDENCIAL Año 2026 €',
            fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
          ),
        );

        final outDoc = sfpdf.PdfDocument(
          inputBytes: await File(out).readAsBytes(),
        );
        try {
          expect(outDoc.pages.count, equals(1));
          expect(
            sfpdf.PdfTextExtractor(outDoc).extractText(),
            contains('Documento Base'),
          );
        } finally {
          outDoc.dispose();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('CompressPdfService optimiza PDF vectorial preservando texto',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_cmp_pdf_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final src = await _writeVectorPdf(
          p.join(tempDir.path, 'src.pdf'),
          ['Contenido Optimizado LocalConvert'],
        );
        final out = p.join(tempDir.path, 'cmp.pdf');
        final service = CompressPdfService(sandboxCleaner: cleaner);

        final result = await service.compressPdf(
          CompressPdfConfig(
            sourcePdfPath: src,
            outputPdfPath: out,
            level: CompressPdfLevel.losslessVector,
          ),
        );

        expect(result.pageCount, equals(1));
        expect(result.compressedBytes, greaterThan(0));
        final outDoc = sfpdf.PdfDocument(
          inputBytes: await File(out).readAsBytes(),
        );
        try {
          expect(
            sfpdf.PdfTextExtractor(outDoc).extractText(),
            contains('Contenido Optimizado'),
          );
        } finally {
          outDoc.dispose();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Fase 2.2: TIFF/ICO/GIF/TGA, SVG → PNG y Limpiador EXIF', () {
    test('ImageFormatIsolateService codifica TIFF, ICO, GIF y TGA válidos', () {
      final src = img.Image(width: 32, height: 24, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(59, 130, 246, 255));

      for (final fmt in const [
        TargetImageFormat.tiff,
        TargetImageFormat.ico,
        TargetImageFormat.gif,
        TargetImageFormat.tga,
      ]) {
        final encoded = ImageFormatIsolateService.encodeImageToFormat(
          image: src,
          targetFormat: fmt,
          quality: 90,
        );
        expect(encoded, isNotEmpty);
        final decoded = img.decodeImage(encoded);
        expect(decoded, isNotNull, reason: 'Debe decodificar ${fmt.label}');
        expect(decoded!.width, equals(32));
        expect(decoded.height, equals(24));
      }
    });

    test('ImageFormatIsolateService rasteriza SVG offline a PNG con escala 2x',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_svg_test_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final svgPath = p.join(tempDir.path, 'icon.svg');
        await File(svgPath).writeAsString('''
<svg xmlns="http://www.w3.org/2000/svg" width="50" height="40" viewBox="0 0 50 40">
  <rect x="2" y="2" width="46" height="36" fill="#2563EB"/>
  <circle cx="25" cy="20" r="10" fill="#FFFFFF"/>
  <path d="M10 10 L40 10 L40 30 Z" fill="#10B981"/>
</svg>''');
        final outDir = Directory(p.join(tempDir.path, 'out'))..createSync();

        final service = ImageFormatIsolateService(sandboxCleaner: cleaner);
        final events = await service
            .convertBatch(
              ImageFormatBatchConfig(
                inputPaths: [svgPath],
                sessionDirPath: outDir.path,
                targetFormat: TargetImageFormat.png,
                svgScaleMultiplier: 2,
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        final pngBytes = await File(events.last.outputFiles.first).readAsBytes();
        final decoded = img.decodePng(pngBytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, equals(100));
        expect(decoded.height, equals(80));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('ExifStripperIsolateService detecta y elimina etiquetas EXIF en Isolate',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_exif_test_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final photo = img.Image(width: 24, height: 24);
        img.fill(photo, color: img.ColorRgb8(245, 158, 11));
        photo.exif.imageIfd[0x010F] = img.IfdValueAscii('CanonTest');
        photo.exif.imageIfd[0x0110] = img.IfdValueAscii('EOSOffline');

        final srcBytes = img.encodeJpg(photo, quality: 92);
        final detected = ExifStripperIsolateService.inspectExifTags(srcBytes);
        expect(detected, isNotEmpty);

        final srcPath = p.join(tempDir.path, 'camera.jpg');
        await File(srcPath).writeAsBytes(srcBytes, flush: true);
        final outDir = Directory(p.join(tempDir.path, 'out'))..createSync();

        final service = ExifStripperIsolateService(sandboxCleaner: cleaner);
        final events = await service
            .stripBatch(
              ExifStripperBatchConfig(
                inputPaths: [srcPath],
                sessionDirPath: outDir.path,
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        expect(events.last.totalTagsRemoved, greaterThanOrEqualTo(2));
        final cleanedBytes =
            await File(events.last.outputFiles.first).readAsBytes();
        expect(ExifStripperIsolateService.inspectExifTags(cleanedBytes), isEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Fase 2.3: Datos Estructurados (CSV/JSON/XML/PDF) y HTML/EPUB', () {
    test('StructuredDataIsolateService convierte CSV -> JSON -> XML y CSV -> PDF',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_sdata_');
      try {
        final service = StructuredDataIsolateService();
        const sampleCsv = 'id,nombre,moneda\n1,Iñaki,€\n2,Sofía,\$';

        final jsonRes = await service.convertInIsolate(
          StructuredDataConfig(
            inputContent: sampleCsv,
            sourceFormat: StructuredDataFormat.csv,
            targetFormat: StructuredDataFormat.json,
            outputFilePath: p.join(tempDir.path, 'out.json'),
          ),
        );
        expect(jsonRes.rowCount, equals(2));
        final decodedJson = jsonDecode(jsonRes.previewText) as List;
        expect((decodedJson.first as Map)['nombre'], equals('Iñaki'));

        final xmlRes = await service.convertInIsolate(
          StructuredDataConfig(
            inputContent: jsonRes.previewText,
            sourceFormat: StructuredDataFormat.json,
            targetFormat: StructuredDataFormat.xml,
            outputFilePath: p.join(tempDir.path, 'out.xml'),
          ),
        );
        expect(xmlRes.previewText, contains('<dataset>'));
        expect(xmlRes.previewText, contains('Sofía'));

        final pdfRes = await service.convertInIsolate(
          StructuredDataConfig(
            inputContent: sampleCsv,
            sourceFormat: StructuredDataFormat.csv,
            targetFormat: StructuredDataFormat.pdfTable,
            outputFilePath: p.join(tempDir.path, 'table.pdf'),
            fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
          ),
        );
        expect(
          String.fromCharCodes(pdfRes.outputBytes.sublist(0, 8)),
          startsWith('%PDF-1.'),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('EbookConverterIsolateService convierte HTML y EPUB real a TXT y PDF',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_ebook_');
      try {
        final service = EbookConverterIsolateService();

        // 1. HTML a TXT
        final htmlTxt = await service.convertInIsolate(
          EbookConverterConfig(
            rawHtmlOverride:
                '<html><head><title>Nota Offline</title></head><body><h1>Hola Mundo</h1><p>Texto con ñ y €.</p><ul><li>Punto uno</li></ul></body></html>',
            targetFormat: EbookTargetFormat.txt,
            outputFilePath: p.join(tempDir.path, 'nota.txt'),
          ),
        );
        expect(htmlTxt.extractedTitle, equals('Nota Offline'));
        expect(htmlTxt.previewText, contains('Hola Mundo'));
        expect(htmlTxt.previewText, contains('Punto uno'));

        // 2. EPUB real (ZIP interno) a PDF
        final epubArchive = Archive();
        const containerXml =
            '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';
        const opfXml =
            '<?xml version="1.0"?><package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Libro Local</dc:title></metadata><manifest><item id="c1" href="cap1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>';
        const chapterXhtml =
            '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Capítulo 1</h1><p>Contenido offline del libro con ñ.</p></body></html>';

        epubArchive.addFile(
          ArchiveFile(
            'META-INF/container.xml',
            utf8.encode(containerXml).length,
            utf8.encode(containerXml),
          ),
        );
        epubArchive.addFile(
          ArchiveFile(
            'OEBPS/content.opf',
            utf8.encode(opfXml).length,
            utf8.encode(opfXml),
          ),
        );
        epubArchive.addFile(
          ArchiveFile(
            'OEBPS/cap1.xhtml',
            utf8.encode(chapterXhtml).length,
            utf8.encode(chapterXhtml),
          ),
        );

        final epubPath = p.join(tempDir.path, 'libro.epub');
        await File(epubPath).writeAsBytes(
          ZipEncoder().encode(epubArchive),
          flush: true,
        );

        final pdfOutPath = p.join(tempDir.path, 'libro.pdf');
        final epubPdf = await service.convertInIsolate(
          EbookConverterConfig(
            sourceFilePath: epubPath,
            targetFormat: EbookTargetFormat.pdf,
            outputFilePath: pdfOutPath,
            fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
          ),
        );

        expect(epubPdf.extractedTitle, equals('Libro Local'));
        expect(epubPdf.chapterCount, equals(1));
        expect(epubPdf.previewText, contains('Contenido offline del libro'));
        final pdfBytes = await File(pdfOutPath).readAsBytes();
        expect(String.fromCharCodes(pdfBytes.sublist(0, 8)), startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Multimedia Suite: FFmpeg Parser, CLI Builder, AudioService y YouTube ID',
      () {
    test('FfmpegProgressParser extrae Duration, time= y timestamps de usuario',
        () {
      const sampleLog =
          '  Duration: 00:02:00.00, start: 0.000000, bitrate: 192 kb/s\n'
          'frame=  120 fps= 30 q=28.0 size= 256kB time=00:00:30.00 bitrate= 69.9kbits/s';
      final dur = FfmpegProgressParser.parseDuration(sampleLog);
      final cur = FfmpegProgressParser.parseCurrentTime(sampleLog);

      expect(dur, equals(const Duration(minutes: 2)));
      expect(cur, equals(const Duration(seconds: 30)));
      expect(FfmpegProgressParser.computeProgress(cur!, dur), closeTo(0.25, 0.001));

      expect(
        FfmpegProgressParser.parseUserTimestamp('01:30'),
        equals(const Duration(minutes: 1, seconds: 30)),
      );
      expect(
        FfmpegProgressParser.parseUserTimestamp('45'),
        equals(const Duration(seconds: 45)),
      );
      expect(FfmpegProgressParser.parseUserTimestamp('invalido'), isNull);
    });

    test('FfmpegCliBuilder genera argumentos exactos de audio, video, trim, GIF y mux',
        () {
      final audioArgs = FfmpegCliBuilder.buildAudioConversionArgs(
        inputPath: 'in.wav',
        outputPath: 'out.mp3',
        format: AudioOutputFormat.mp3,
        bitrate: AudioBitrateOption.k320,
        sampleRate: AudioSampleRateOption.hz48000,
        metadata: {'title': 'Tema', 'artist': 'Autor'},
      );
      expect(audioArgs, containsAllInOrder(['-ar', '48000', '-c:a', 'libmp3lame', '-b:a', '320k']));
      expect(audioArgs, containsAllInOrder(['-metadata', 'title=Tema']));

      final videoArgs = FfmpegCliBuilder.buildVideoConversionArgs(
        inputPath: 'in.mov',
        outputPath: 'out.mp4',
        format: VideoOutputFormat.mp4,
        resolution: VideoResolutionPreset.p720,
        crfPreset: VideoCrfPreset.balanced,
        muteAudio: true,
        trimStart: const Duration(seconds: 5),
        trimEnd: const Duration(seconds: 25),
      );
      expect(videoArgs, containsAllInOrder(['-ss', '00:00:05.000', '-to', '00:00:25.000', '-i', 'in.mov']));
      expect(videoArgs, containsAllInOrder(['-vf', 'scale=-2:720', '-c:v', 'libx264', '-crf', '23']));
      expect(videoArgs, contains('-an'));

      final gifArgs = FfmpegCliBuilder.buildVideoConversionArgs(
        inputPath: 'clip.mp4',
        outputPath: 'clip.gif',
        format: VideoOutputFormat.gif,
        resolution: VideoResolutionPreset.p480,
        crfPreset: VideoCrfPreset.balanced,
        muteAudio: false,
      );
      expect(gifArgs.join(' '), contains('palettegen'));
      expect(gifArgs.last, equals('clip.gif'));

      final copyArgs = FfmpegCliBuilder.buildAudioExtractionArgs(
        inputPath: 'video.mp4',
        outputPath: 'audio.m4a',
        format: AudioExtractFormat.m4a,
        streamCopy: true,
        bitrate: AudioBitrateOption.k192,
      );
      expect(copyArgs, containsAllInOrder(['-vn', '-c:a', 'copy', 'audio.m4a']));

      final muxArgs = FfmpegCliBuilder.buildMuxVideoAndAudioArgs(
        videoPath: 'v.mp4',
        audioPath: 'a.m4a',
        outputPath: 'final.mp4',
      );
      expect(muxArgs, containsAllInOrder(['-c:v', 'copy', '-c:a', 'aac', 'final.mp4']));
    });

    test('YoutubeUrlValidator valida watch, youtu.be, shorts y rechaza dominios externos',
        () {
      expect(
        YoutubeUrlValidator.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        equals('dQw4w9WgXcQ'),
      );
      expect(
        YoutubeUrlValidator.extractVideoId('https://youtu.be/dQw4w9WgXcQ?t=12'),
        equals('dQw4w9WgXcQ'),
      );
      expect(
        YoutubeUrlValidator.extractVideoId('https://youtube.com/shorts/abcDEF12345'),
        equals('abcDEF12345'),
      );
      expect(
        YoutubeUrlValidator.isValidYoutubeUrl('https://vimeo.com/123456789'),
        isFalse,
      );
      expect(YoutubeUrlValidator.isValidYoutubeUrl('no es una url'), isFalse);
    });

    test('AudioConverterService procesa lote con MediaProcessingEngine simulado y empaqueta ZIP',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_audio_svc_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final in1 = p.join(tempDir.path, 'track1.wav');
        final in2 = p.join(tempDir.path, 'track2.wav');
        await File(in1).writeAsBytes([1, 2, 3]);
        await File(in2).writeAsBytes([4, 5, 6]);
        final sessionDir = Directory(p.join(tempDir.path, 'sess'))..createSync();

        final mockEngine = _FakeMediaEngine();
        final service = AudioConverterService(
          engine: mockEngine,
          sandboxCleaner: cleaner,
        );

        final events = await service
            .convertBatch(
              AudioConverterBatchConfig(
                inputPaths: [in1, in2],
                sessionDirPath: sessionDir.path,
                targetFormat: AudioOutputFormat.mp3,
                bitrate: AudioBitrateOption.k192,
                sampleRate: AudioSampleRateOption.hz44100,
                packageAsZip: true,
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        expect(events.last.zipFilePath, isNotNull);
        expect(await File(events.last.zipFilePath!).exists(), isTrue);
        expect(mockEngine.recordedCommands.length, equals(2));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('FfmpegBinaryResolver resuelve rutas no vacías para ffmpeg y ffprobe', () {
      final ffmpeg = FfmpegBinaryResolver.ffmpegPath;
      final ffprobe = FfmpegBinaryResolver.ffprobePath;

      expect(ffmpeg, isNotEmpty);
      expect(ffprobe, isNotEmpty);
      expect(ffmpeg == 'ffmpeg' || ffmpeg.endsWith('ffmpeg.exe'), isTrue);
      expect(ffprobe == 'ffprobe' || ffprobe.endsWith('ffprobe.exe'), isTrue);
    });
  });

  group('Motor Nativo Rust FFI (local_convert_core)', () {
    test('LocalConvertRustBridge carga local_convert_core y codifica RGBA + ZIP',
        () async {
      expect(LocalConvertRustBridge.isAvailable, isTrue);
      expect(LocalConvertRustBridge.resolveLibraryPath(), isNotNull);

      final tempDir = await Directory.systemTemp.createTemp('lc_rust_ffi_');
      try {
        final rgba = Uint8List.fromList([
          for (int i = 0; i < 16 * 16; i++) ...[37, 99, 235, 180],
        ]);
        final pngBytes = LocalConvertRustBridge.encodeRgbaBufferSync(
          rgbaBytes: rgba,
          width: 16,
          height: 16,
          format: 'png',
          quality: 90,
        );
        expect(pngBytes.sublist(0, 4), equals([0x89, 0x50, 0x4E, 0x47]));

        final jpgBytes = LocalConvertRustBridge.encodeRgbaBufferSync(
          rgbaBytes: rgba,
          width: 16,
          height: 16,
          format: 'jpg',
          quality: 85,
        );
        expect(jpgBytes.sublist(0, 2), equals([0xFF, 0xD8]));

        final imgPath = p.join(tempDir.path, 'pagina_001.png');
        final zipPath = p.join(tempDir.path, 'salida.zip');
        await File(imgPath).writeAsBytes(pngBytes, flush: true);

        final zipRes = LocalConvertRustBridge.invokeJsonSync({
          'action': 'create_zip',
          'input_paths': [imgPath],
          'output_zip_path': zipPath,
        });
        expect(zipRes['zip_file_path'], equals(zipPath));
        expect(await File(zipPath).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('SplitPdfService en modo ZIP separado genera archivos vectoriales por rango en Rust',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_rust_split_zip_');
      try {
        final cleaner = SandboxCleanerService(tempDirProvider: () async => tempDir);
        final src = await _writeVectorPdf(
          p.join(tempDir.path, 'manual.pdf'),
          ['Capitulo Uno', 'Capitulo Dos', 'Capitulo Tres'],
        );
        final sessionDir = Directory(p.join(tempDir.path, 'sess'))..createSync();
        final parsed = PageRangeParser.parse('1, 3', maxPages: 3);

        final service = SplitPdfService(sandboxCleaner: cleaner);
        final events = await service
            .splitPdf(
              SplitPdfConfig(
                sourcePdfPath: src,
                sessionDirPath: sessionDir.path,
                segments: parsed.segments,
                uniquePagesToExtract: parsed.uniqueSortedPages,
                outputMode: SplitOutputMode.separatePdfsPerRangeZip,
              ),
            )
            .toList();

        expect(events.last.isCompleted, isTrue);
        final zipPath = events.last.zipOutputPath!;
        expect(await File(zipPath).exists(), isTrue);

        final archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
        expect(archive.files.length, equals(2));
        final firstDoc = sfpdf.PdfDocument(
          inputBytes: archive.files.first.content,
        );
        try {
          expect(sfpdf.PdfTextExtractor(firstDoc).extractText(), contains('Capitulo Uno'));
        } finally {
          firstDoc.dispose();
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Empaquetado Comercial: Iconos, Explorer CLI y Ofimática/QR en Rust', () {
    test('Íconos oficiales multicapa (.ico) y PNG 256x256 existen y son válidos',
        () async {
      final icoFile = File(
        p.join(Directory.current.path, 'windows', 'runner', 'resources', 'app_icon.ico'),
      );
      final pngFile = File(
        p.join(Directory.current.path, 'assets', 'icons', 'app_icon.png'),
      );

      expect(await icoFile.exists(), isTrue);
      expect(await pngFile.exists(), isTrue);
      final icoBytes = await icoFile.readAsBytes();
      expect(icoBytes.sublist(0, 6), equals([0, 0, 1, 0, 6, 0]));
      final decodedPng = img.decodePng(await pngFile.readAsBytes());
      expect(decodedPng?.width, equals(256));
      expect(decodedPng?.height, equals(256));
    });

    test('CliLaunchRouter resuelve herramientas correctas desde argumentos CLI',
        () {
      expect(
        CliLaunchRouter.resolveFromArgs(['--verbose', 'informe.pdf'], verifyExists: false)?.toolId,
        equals(ToolId.splitPdf),
      );
      expect(
        CliLaunchRouter.resolveFromArgs(['a.pdf', 'b.pdf'], verifyExists: false)?.toolId,
        equals(ToolId.mergePdf),
      );
      expect(
        CliLaunchRouter.resolveFromArgs(['foto.webp', 'logo.png'], verifyExists: false)?.toolId,
        equals(ToolId.imageFormatConverter),
      );
      expect(
        CliLaunchRouter.resolveFromArgs(['finanzas.xlsx'], verifyExists: false)?.toolId,
        equals(ToolId.spreadsheetConverter),
      );
      expect(
        CliLaunchRouter.resolveFromArgs(['contrato.docx'], verifyExists: false)?.toolId,
        equals(ToolId.docxConverter),
      );
      expect(
        CliLaunchRouter.resolveFromArgs(['apuntes.md'], verifyExists: false)?.toolId,
        equals(ToolId.markdownToPdf),
      );
    });

    test('SpreadsheetConverterService lee .xlsx en Rust y convierte a CSV, JSON y PDF',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_xlsx_test_');
      try {
        final xlsxPath = p.join(tempDir.path, 'ventas.xlsx');
        final archive = Archive()
          ..addFile(_utf8ArchiveFile('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>'''))
          ..addFile(_utf8ArchiveFile('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>'''))
          ..addFile(_utf8ArchiveFile('xl/workbook.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Resumen" sheetId="1" r:id="rId1"/></sheets>
</workbook>'''))
          ..addFile(_utf8ArchiveFile('xl/_rels/workbook.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>'''))
          ..addFile(_utf8ArchiveFile('xl/worksheets/sheet1.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Item</t></is></c><c r="B1" t="inlineStr"><is><t>Precio</t></is></c></row>
    <row r="2"><c r="A2" t="inlineStr"><is><t>LocalConvert</t></is></c><c r="B2"><v>49</v></c></row>
  </sheetData>
</worksheet>'''));
        await File(xlsxPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);

        final svc = SpreadsheetConverterService();
        final info = await svc.inspectWorkbook(xlsxPath);
        expect(info.sheetNames, equals(['Resumen']));
        expect(info.rowCount, equals(2));

        final csvOut = p.join(tempDir.path, 'resumen.csv');
        await svc.convertWorkbook(
          SpreadsheetConvertConfig(
            sourceFilePath: xlsxPath,
            sheetName: 'Resumen',
            targetFormat: SpreadsheetOutputFormat.csv,
            outputFilePath: csvOut,
          ),
        );
        expect(await File(csvOut).readAsString(), contains('LocalConvert,49'));

        final jsonOut = p.join(tempDir.path, 'resumen.json');
        await svc.convertWorkbook(
          SpreadsheetConvertConfig(
            sourceFilePath: xlsxPath,
            targetFormat: SpreadsheetOutputFormat.json,
            outputFilePath: jsonOut,
          ),
        );
        final jsonList = jsonDecode(await File(jsonOut).readAsString()) as List<dynamic>;
        expect((jsonList.first as Map<String, dynamic>)['Item'], equals('LocalConvert'));

        final pdfOut = p.join(tempDir.path, 'resumen.pdf');
        await svc.convertWorkbook(
          SpreadsheetConvertConfig(
            sourceFilePath: xlsxPath,
            targetFormat: SpreadsheetOutputFormat.pdf,
            outputFilePath: pdfOut,
          ),
          fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
        );
        final pdfBytes = await File(pdfOut).readAsBytes();
        expect(String.fromCharCodes(pdfBytes.sublist(0, 7)), startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('DocxConverterService convierte .docx real a Markdown, TXT y PDF',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_docx_test_');
      try {
        final docxPath = p.join(tempDir.path, 'nota.docx');
        final archive = Archive()
          ..addFile(_utf8ArchiveFile('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>'''))
          ..addFile(_utf8ArchiveFile('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''))
          ..addFile(_utf8ArchiveFile('word/document.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Manual Offline</w:t></w:r></w:p>
    <w:p><w:r><w:b/><w:t>Motor Rust</w:t></w:r><w:r><w:t> activo.</w:t></w:r></w:p>
  </w:body>
</w:document>'''));
        await File(docxPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);

        final svc = DocxConverterService();
        final info = await svc.inspectDocument(docxPath);
        expect(info.previewMarkdown, contains('# Manual Offline'));

        final mdOut = p.join(tempDir.path, 'nota.md');
        await svc.convertDocument(
          DocxConvertConfig(
            sourceFilePath: docxPath,
            targetFormat: DocxOutputFormat.markdown,
            outputFilePath: mdOut,
          ),
        );
        expect(await File(mdOut).readAsString(), contains('**Motor Rust** activo.'));

        final pdfOut = p.join(tempDir.path, 'nota.pdf');
        await svc.convertDocument(
          DocxConvertConfig(
            sourceFilePath: docxPath,
            targetFormat: DocxOutputFormat.pdf,
            outputFilePath: pdfOut,
          ),
          fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
        );
        final pdfBytes = await File(pdfOut).readAsBytes();
        expect(String.fromCharCodes(pdfBytes.sublist(0, 7)), startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('QrGeneratorService genera preview PNG y lotes PNG/ZIP, SVG y Lámina PDF en Rust',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('lc_qr_test_');
      try {
        final svc = QrGeneratorService();
        final previewPath = p.join(tempDir.path, 'preview.png');
        final prev = await svc.generatePreview(
          content: 'https://localconvert.app',
          errorCorrection: QrErrorCorrection.medium,
          outputPath: previewPath,
          sizePx: 256,
        );
        expect(prev.moduleCount, greaterThan(15));
        expect(await File(previewPath).exists(), isTrue);

        final pngBatchDir = Directory(p.join(tempDir.path, 'png_lote'))..createSync();
        final pngRes = await svc.generateBatch(
          QrBatchConfig(
            items: const ['Uno', 'Dos'],
            sessionDirPath: pngBatchDir.path,
            outputFormat: QrOutputFormat.png,
            packageAsZip: true,
          ),
        );
        expect(pngRes.generatedCount, equals(2));
        expect(pngRes.zipFilePath, isNotNull);
        expect(await File(pngRes.zipFilePath!).exists(), isTrue);

        final svgDir = Directory(p.join(tempDir.path, 'svg_lote'))..createSync();
        final svgRes = await svc.generateBatch(
          QrBatchConfig(
            items: const ['SoloSVG'],
            sessionDirPath: svgDir.path,
            outputFormat: QrOutputFormat.svg,
          ),
        );
        expect(await File(svgRes.outputFiles.first).readAsString(), contains('<svg'));

        final pdfDir = Directory(p.join(tempDir.path, 'pdf_lote'))..createSync();
        final pdfRes = await svc.generateBatch(
          QrBatchConfig(
            items: const ['Ticket A', 'Ticket B'],
            sessionDirPath: pdfDir.path,
            outputFormat: QrOutputFormat.pdf,
          ),
          fontBundle: PdfFontAssetLoader.loadFromDiskSync(),
        );
        final pdfBytes = await File(pdfRes.outputFiles.first).readAsBytes();
        expect(String.fromCharCodes(pdfBytes.sublist(0, 7)), startsWith('%PDF-1.'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}

ArchiveFile _utf8ArchiveFile(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}

class _FakeMediaEngine implements MediaProcessingEngine {
  final List<List<String>> recordedCommands = [];

  @override
  Future<void> cancelCurrent() async {}

  @override
  Stream<MediaProgressEvent> executeCommand({
    required List<String> arguments,
    required String outputPath,
    Duration? knownDuration,
    String? statusPrefix,
  }) async* {
    recordedCommands.add(arguments);
    yield MediaProgressEvent(progress: 0.5, statusMessage: '${statusPrefix ?? ""} 50%');
    await File(outputPath).writeAsBytes([73, 68, 51, 0, 1], flush: true);
    yield MediaProgressEvent(
      progress: 1.0,
      statusMessage: 'Listo',
      isCompleted: true,
      outputPath: outputPath,
    );
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> resolveExecutablePath() async => 'fake_ffmpeg';
}
