import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/cli/cli_launch_router.dart';
import 'core/sandbox/sandbox_cleaner_service.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/doc_tools/docx_converter/presentation/providers/docx_converter_notifier.dart';
import 'features/doc_tools/docx_converter/presentation/screens/docx_converter_screen.dart';
import 'features/doc_tools/ebook_converter/presentation/providers/ebook_converter_notifier.dart';
import 'features/doc_tools/ebook_converter/presentation/screens/ebook_converter_screen.dart';
import 'features/doc_tools/markdown_to_pdf/presentation/providers/markdown_to_pdf_notifier.dart';
import 'features/doc_tools/markdown_to_pdf/presentation/screens/markdown_to_pdf_screen.dart';
import 'features/doc_tools/spreadsheet_converter/presentation/providers/spreadsheet_converter_notifier.dart';
import 'features/doc_tools/spreadsheet_converter/presentation/screens/spreadsheet_converter_screen.dart';
import 'features/doc_tools/structured_data/presentation/providers/structured_data_notifier.dart';
import 'features/doc_tools/structured_data/presentation/screens/structured_data_screen.dart';
import 'features/image_tools/compressor_resizer/presentation/providers/compressor_resizer_notifier.dart';
import 'features/image_tools/compressor_resizer/presentation/screens/compressor_resizer_screen.dart';
import 'features/image_tools/exif_stripper/presentation/providers/exif_stripper_notifier.dart';
import 'features/image_tools/exif_stripper/presentation/screens/exif_stripper_screen.dart';
import 'features/image_tools/format_converter/presentation/providers/image_format_notifier.dart';
import 'features/image_tools/format_converter/presentation/screens/image_format_screen.dart';
import 'features/image_tools/qr_generator/presentation/providers/qr_generator_notifier.dart';
import 'features/image_tools/qr_generator/presentation/screens/qr_generator_screen.dart';
import 'features/media_tools/audio_converter/presentation/providers/audio_converter_notifier.dart';
import 'features/media_tools/audio_converter/presentation/screens/audio_converter_screen.dart';
import 'features/media_tools/video_converter/presentation/providers/video_converter_notifier.dart';
import 'features/media_tools/video_converter/presentation/screens/video_converter_screen.dart';
import 'features/media_tools/video_to_audio/presentation/providers/video_to_audio_notifier.dart';
import 'features/media_tools/video_to_audio/presentation/screens/video_to_audio_screen.dart';
import 'features/media_tools/youtube_downloader/presentation/providers/youtube_downloader_notifier.dart';
import 'features/media_tools/youtube_downloader/presentation/screens/youtube_downloader_screen.dart';
import 'features/pdf_tools/compress_pdf/presentation/providers/compress_pdf_notifier.dart';
import 'features/pdf_tools/compress_pdf/presentation/screens/compress_pdf_screen.dart';
import 'features/pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import 'features/pdf_tools/images_to_pdf/presentation/screens/image_to_pdf_screen.dart';
import 'features/pdf_tools/merge_pdf/presentation/providers/merge_pdf_notifier.dart';
import 'features/pdf_tools/merge_pdf/presentation/screens/merge_pdf_screen.dart';
import 'features/pdf_tools/organize_pdf/presentation/providers/organize_pdf_notifier.dart';
import 'features/pdf_tools/organize_pdf/presentation/screens/organize_pdf_screen.dart';
import 'features/pdf_tools/pdf_to_images/presentation/providers/pdf_to_images_notifier.dart';
import 'features/pdf_tools/pdf_to_images/presentation/screens/pdf_to_images_screen.dart';
import 'features/pdf_tools/protect_pdf/presentation/providers/protect_pdf_notifier.dart';
import 'features/pdf_tools/protect_pdf/presentation/screens/protect_pdf_screen.dart';
import 'features/pdf_tools/split_pdf/presentation/providers/split_pdf_notifier.dart';
import 'features/pdf_tools/split_pdf/presentation/screens/split_pdf_screen.dart';
import 'features/pdf_tools/watermark_pdf/presentation/providers/watermark_pdf_notifier.dart';
import 'features/pdf_tools/watermark_pdf/presentation/screens/watermark_pdf_screen.dart';
import 'shared/models/tool_item.dart';
import 'shared/widgets/adaptive_workspace_shell.dart';

/// Argumentos CLI pasados al ejecutable (Windows Explorer "Abrir con" / Drag-to-EXE).
final initialCliArgsProvider = Provider<List<String>>((ref) => const []);

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Limpieza preventiva del Sandbox temporal (CacheDir) al iniciar la aplicación.
  await SandboxCleanerService().purgeAll();

  runApp(
    ProviderScope(
      overrides: [
        initialCliArgsProvider.overrideWithValue(args),
      ],
      child: const LocalConvertApp(),
    ),
  );
}

class LocalConvertApp extends ConsumerWidget {
  const LocalConvertApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'LocalConvert — Offline & Multimedia Suite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const LocalConvertHomeCoordinator(),
    );
  }
}

/// Coordinador principal entre el Dashboard y el Área de Trabajo de las 21 herramientas.
class LocalConvertHomeCoordinator extends ConsumerStatefulWidget {
  const LocalConvertHomeCoordinator({super.key});

  @override
  ConsumerState<LocalConvertHomeCoordinator> createState() =>
      _LocalConvertHomeCoordinatorState();
}

class _LocalConvertHomeCoordinatorState
    extends ConsumerState<LocalConvertHomeCoordinator> {
  ToolCategory _selectedCategory = ToolCategory.all;
  ToolItem? _activeTool;

  @override
  void initState() {
    super.initState();
    final args = ref.read(initialCliArgsProvider);
    final route = CliLaunchRouter.resolveFromArgs(args);
    if (route != null) {
      _selectedCategory = route.category;
      _activeTool = ToolItem.catalog.firstWhere(
        (item) => item.id == route.toolId,
        orElse: () => ToolItem.catalog.first,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _preloadCliRouteFiles(route);
        }
      });
    }
  }

  void _preloadCliRouteFiles(CliLaunchRoute route) {
    final files = route.filePaths;
    if (files.isEmpty) return;

    switch (route.toolId) {
      case ToolId.mergePdf:
        ref.read(mergePdfNotifierProvider.notifier).addPdfFiles(files);
      case ToolId.splitPdf:
        ref.read(splitPdfNotifierProvider.notifier).selectPdfFile(files.first);
      case ToolId.imageFormatConverter:
        ref
            .read(imageFormatConverterNotifierProvider.notifier)
            .addImageFiles(files);
      case ToolId.spreadsheetConverter:
        ref
            .read(spreadsheetConverterNotifierProvider.notifier)
            .loadWorkbook(files.first);
      case ToolId.docxConverter:
        ref
            .read(docxConverterNotifierProvider.notifier)
            .loadDocxFile(files.first);
      case ToolId.structuredDataConverter:
        ref.read(structuredDataNotifierProvider.notifier).loadFile(files.first);
      case ToolId.markdownToPdf:
        ref
            .read(markdownToPdfNotifierProvider.notifier)
            .loadDocumentFile(files.first);
      case ToolId.ebookToPdf:
        ref.read(ebookConverterNotifierProvider.notifier).loadFile(files.first);
      case ToolId.audioConverter:
        ref.read(audioConverterNotifierProvider.notifier).addAudioFiles(files);
      case ToolId.videoConverter:
        ref
            .read(videoConverterNotifierProvider.notifier)
            .loadVideoFile(files.first);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveWorkspaceShell(
      selectedCategory: _selectedCategory,
      onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
      activeTool: _activeTool,
      onCloseTool: () => setState(() => _activeTool = null),
      onShortcutOpenFiles: _handleShortcutOpen,
      onShortcutSaveOutput: _handleShortcutSave,
      body: _buildActiveBody(),
      settingsPanel: _buildActiveSettingsPanel(),
      primaryActionFooter: _buildActivePrimaryAction(),
    );
  }

  Widget _buildActiveBody() {
    if (_activeTool == null) {
      return DashboardScreen(
        selectedCategory: _selectedCategory,
        onCategoryChanged: (cat) => setState(() => _selectedCategory = cat),
        onToolSelected: (tool) => setState(() => _activeTool = tool),
      );
    }

    switch (_activeTool!.id) {
      case ToolId.imagesToPdf:
        return const ImageToPdfWorkspaceBody();
      case ToolId.pdfToImages:
        return const PdfToImagesWorkspaceBody();
      case ToolId.mergePdf:
        return const MergePdfWorkspaceBody();
      case ToolId.splitPdf:
        return const SplitPdfWorkspaceBody();
      case ToolId.organizePdf:
        return const OrganizePdfWorkspaceBody();
      case ToolId.protectPdf:
        return const ProtectPdfWorkspaceBody();
      case ToolId.watermarkPdf:
        return const WatermarkPdfWorkspaceBody();
      case ToolId.compressPdf:
        return const CompressPdfWorkspaceBody();
      case ToolId.imageFormatConverter:
        return const ImageFormatConverterWorkspaceBody();
      case ToolId.imageCompressorResizer:
        return const CompressorResizerWorkspaceBody();
      case ToolId.stripExif:
        return const ExifStripperWorkspaceBody();
      case ToolId.qrGenerator:
        return const QrGeneratorWorkspaceBody();
      case ToolId.markdownToPdf:
        return const MarkdownToPdfWorkspaceBody();
      case ToolId.structuredDataConverter:
        return const StructuredDataWorkspaceBody();
      case ToolId.ebookToPdf:
        return const EbookConverterWorkspaceBody();
      case ToolId.spreadsheetConverter:
        return const SpreadsheetConverterWorkspaceBody();
      case ToolId.docxConverter:
        return const DocxConverterWorkspaceBody();
      case ToolId.audioConverter:
        return const AudioConverterWorkspaceBody();
      case ToolId.videoConverter:
        return const VideoConverterWorkspaceBody();
      case ToolId.videoToAudio:
        return const VideoToAudioWorkspaceBody();
      case ToolId.youtubeDownloader:
        return const YoutubeDownloaderWorkspaceBody();
    }
  }

  Widget? _buildActiveSettingsPanel() {
    if (_activeTool == null) return null;
    switch (_activeTool!.id) {
      case ToolId.imagesToPdf:
        return const ImageToPdfSettingsPanel();
      case ToolId.pdfToImages:
        return const PdfToImagesSettingsPanel();
      case ToolId.mergePdf:
        return const MergePdfSettingsPanel();
      case ToolId.splitPdf:
        return const SplitPdfSettingsPanel();
      case ToolId.organizePdf:
        return const OrganizePdfSettingsPanel();
      case ToolId.protectPdf:
        return const ProtectPdfSettingsPanel();
      case ToolId.watermarkPdf:
        return const WatermarkPdfSettingsPanel();
      case ToolId.compressPdf:
        return const CompressPdfSettingsPanel();
      case ToolId.imageFormatConverter:
        return const ImageFormatConverterSettingsPanel();
      case ToolId.imageCompressorResizer:
        return const CompressorResizerSettingsPanel();
      case ToolId.stripExif:
        return const ExifStripperSettingsPanel();
      case ToolId.qrGenerator:
        return const QrGeneratorSettingsPanel();
      case ToolId.markdownToPdf:
        return const MarkdownToPdfSettingsPanel();
      case ToolId.structuredDataConverter:
        return const StructuredDataSettingsPanel();
      case ToolId.ebookToPdf:
        return const EbookConverterSettingsPanel();
      case ToolId.spreadsheetConverter:
        return const SpreadsheetConverterSettingsPanel();
      case ToolId.docxConverter:
        return const DocxConverterSettingsPanel();
      case ToolId.audioConverter:
        return const AudioConverterSettingsPanel();
      case ToolId.videoConverter:
        return const VideoConverterSettingsPanel();
      case ToolId.videoToAudio:
        return const VideoToAudioSettingsPanel();
      case ToolId.youtubeDownloader:
        return const YoutubeDownloaderSettingsPanel();
    }
  }

  Widget? _buildActivePrimaryAction() {
    if (_activeTool == null) return null;
    switch (_activeTool!.id) {
      case ToolId.imagesToPdf:
        return const ImageToPdfPrimaryActionButton();
      case ToolId.pdfToImages:
        return const PdfToImagesPrimaryActionButton();
      case ToolId.mergePdf:
        return const MergePdfPrimaryActionButton();
      case ToolId.splitPdf:
        return const SplitPdfPrimaryActionButton();
      case ToolId.organizePdf:
        return const OrganizePdfPrimaryActionButton();
      case ToolId.protectPdf:
        return const ProtectPdfPrimaryActionButton();
      case ToolId.watermarkPdf:
        return const WatermarkPdfPrimaryActionButton();
      case ToolId.compressPdf:
        return const CompressPdfPrimaryActionButton();
      case ToolId.imageFormatConverter:
        return const ImageFormatConverterPrimaryActionButton();
      case ToolId.imageCompressorResizer:
        return const CompressorResizerPrimaryActionButton();
      case ToolId.stripExif:
        return const ExifStripperPrimaryActionButton();
      case ToolId.qrGenerator:
        return const QrGeneratorPrimaryActionButton();
      case ToolId.markdownToPdf:
        return const MarkdownToPdfPrimaryActionButton();
      case ToolId.structuredDataConverter:
        return const StructuredDataPrimaryActionButton();
      case ToolId.ebookToPdf:
        return const EbookConverterPrimaryActionButton();
      case ToolId.spreadsheetConverter:
        return const SpreadsheetConverterPrimaryActionButton();
      case ToolId.docxConverter:
        return const DocxConverterPrimaryActionButton();
      case ToolId.audioConverter:
        return const AudioConverterPrimaryActionButton();
      case ToolId.videoConverter:
        return const VideoConverterPrimaryActionButton();
      case ToolId.videoToAudio:
        return const VideoToAudioPrimaryActionButton();
      case ToolId.youtubeDownloader:
        return const YoutubeDownloaderPrimaryActionButton();
    }
  }

  void _handleShortcutOpen() {
    switch (_activeTool?.id) {
      case ToolId.imagesToPdf:
        pickImagesForPdf(ref);
      case ToolId.pdfToImages:
        pickPdfForImageExtraction(ref);
      case ToolId.mergePdf:
        pickPdfFilesForMerge(ref);
      case ToolId.splitPdf:
        pickPdfForSplit(ref);
      case ToolId.organizePdf:
        pickPdfForOrganize(ref);
      case ToolId.protectPdf:
        pickPdfForProtect(ref);
      case ToolId.watermarkPdf:
        pickPdfForWatermark(ref);
      case ToolId.compressPdf:
        pickPdfForCompression(ref);
      case ToolId.imageFormatConverter:
        pickImagesForFormatConversion(ref);
      case ToolId.imageCompressorResizer:
        pickImagesForCompression(ref);
      case ToolId.stripExif:
        pickImagesForExifStripper(ref);
      case ToolId.qrGenerator:
        pickQrBatchFile(ref);
      case ToolId.markdownToPdf:
        pickMarkdownOrTextFile(ref);
      case ToolId.structuredDataConverter:
        pickStructuredDataFile(ref);
      case ToolId.ebookToPdf:
        pickHtmlOrEpubFile(ref);
      case ToolId.spreadsheetConverter:
        pickSpreadsheetFile(ref);
      case ToolId.docxConverter:
        pickDocxFile(ref);
      case ToolId.audioConverter:
        pickAudioFilesForConversion(ref);
      case ToolId.videoConverter:
        pickVideoFileForConversion(ref);
      case ToolId.videoToAudio:
        pickVideoForAudioExtraction(ref);
      case ToolId.youtubeDownloader:
        pasteYoutubeUrlFromClipboard(ref);
      case null:
        break;
    }
  }

  void _handleShortcutSave() {
    switch (_activeTool?.id) {
      case ToolId.imagesToPdf:
        ref.read(imageToPdfNotifierProvider.notifier).convertAndExport();
      case ToolId.pdfToImages:
        ref.read(pdfToImagesNotifierProvider.notifier).extractAndExport();
      case ToolId.mergePdf:
        ref.read(mergePdfNotifierProvider.notifier).mergeAndExport();
      case ToolId.splitPdf:
        ref.read(splitPdfNotifierProvider.notifier).splitAndExport();
      case ToolId.organizePdf:
        ref.read(organizePdfNotifierProvider.notifier).organizeAndExport();
      case ToolId.protectPdf:
        ref.read(protectPdfNotifierProvider.notifier).processAndExport();
      case ToolId.watermarkPdf:
        ref.read(watermarkPdfNotifierProvider.notifier).applyAndExport();
      case ToolId.compressPdf:
        ref.read(compressPdfNotifierProvider.notifier).compressAndExport();
      case ToolId.imageFormatConverter:
        ref
            .read(imageFormatConverterNotifierProvider.notifier)
            .convertAndExport();
      case ToolId.imageCompressorResizer:
        ref
            .read(compressorResizerNotifierProvider.notifier)
            .compressAndExport();
      case ToolId.stripExif:
        ref.read(exifStripperNotifierProvider.notifier).stripAndExport();
      case ToolId.qrGenerator:
        ref.read(qrGeneratorNotifierProvider.notifier).generateAndExport();
      case ToolId.markdownToPdf:
        ref.read(markdownToPdfNotifierProvider.notifier).convertAndExport();
      case ToolId.structuredDataConverter:
        ref.read(structuredDataNotifierProvider.notifier).convertAndExport();
      case ToolId.ebookToPdf:
        ref.read(ebookConverterNotifierProvider.notifier).convertAndExport();
      case ToolId.spreadsheetConverter:
        ref
            .read(spreadsheetConverterNotifierProvider.notifier)
            .convertAndExport();
      case ToolId.docxConverter:
        ref.read(docxConverterNotifierProvider.notifier).convertAndExport();
      case ToolId.audioConverter:
        ref.read(audioConverterNotifierProvider.notifier).convertAndExport();
      case ToolId.videoConverter:
        ref.read(videoConverterNotifierProvider.notifier).convertAndExport();
      case ToolId.videoToAudio:
        ref.read(videoToAudioNotifierProvider.notifier).extractAndExport();
      case ToolId.youtubeDownloader:
        ref
            .read(youtubeDownloaderNotifierProvider.notifier)
            .startDownloadAndExport();
      case null:
        break;
    }
  }
}
