import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/pdf_to_images_config.dart';
import '../providers/pdf_to_images_notifier.dart';

/// Abre el selector nativo de archivo PDF (invocable desde botón o Ctrl/Cmd+O).
Future<void> pickPdfForImageExtraction(WidgetRef ref) async {
  final state = ref.read(pdfToImagesNotifierProvider);
  if (state.isProcessing) return;

  final picked = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar documento PDF',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  final filePath = picked?.path;
  if (filePath != null) {
    await ref.read(pdfToImagesNotifierProvider.notifier).selectPdfFile(filePath);
  }
}

class PdfToImagesWorkspaceBody extends ConsumerWidget {
  const PdfToImagesWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfToImagesNotifierProvider);
    final notifier = ref.read(pdfToImagesNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.errorMessage != null) ...[
            StatusBanner(
              message: state.errorMessage!,
              icon: LucideIcons.alertTriangle,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
          ] else if (!state.isProcessing && state.statusMessage != null) ...[
            StatusBanner(
              message: state.statusMessage!,
              icon: LucideIcons.checkCircle2,
              color: AppTheme.privacyBadge,
            ),
            const SizedBox(height: 16),
          ],

          if (state.isProcessing) ...[
            DeterministicProgressBar(
              progress: state.progress,
              statusText: state.statusMessage ?? 'Extrayendo páginas...',
              accentColor: AppTheme.pdfAccent,
              onCancel: notifier.cancelExtraction,
            ),
            const SizedBox(height: 20),
          ],

          if (state.selectedPdfPath == null)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title: 'Arrastra y suelta un archivo PDF aquí',
                    subtitle:
                        'Extraeremos cada página como imagen PNG o JPG de alta resolución o en un archivo .ZIP.',
                    allowedExtensionsBadges: const ['PDF → PNG', 'PDF → JPG', 'ZIP'],
                    accentColor: AppTheme.pdfAccent,
                    onPickFilesPressed: () => pickPdfForImageExtraction(ref),
                    onFilesDropped: (paths) {
                      if (paths.isNotEmpty) {
                        notifier.selectPdfFile(paths.first);
                      }
                    },
                  ),
                ),
              ),
            )
          else ...[
            // Barra informativa del PDF cargado
            Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.pdfAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.fileText,
                    color: AppTheme.pdfAccent,
                  ),
                ),
                title: Text(
                  p.basename(state.selectedPdfPath!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  state.isLoadingPreview
                      ? 'Renderizando miniaturas (${state.totalPages} listas)...'
                      : '${state.totalPages} páginas listas para extraer en formato ${state.outputFormat.extension.toUpperCase()}',
                ),
                trailing: TextButton.icon(
                  onPressed: state.isProcessing ? null : notifier.clearSelection,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Cambiar PDF'),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Cuadrícula de miniaturas de las páginas del PDF
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisExtent: 240,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: state.pageThumbnails.length,
                itemBuilder: (context, index) {
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Página ${index + 1}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '.${state.outputFormat.extension}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.pdfAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: Colors.black12,
                            padding: const EdgeInsets.all(8),
                            child: Image.memory(
                              state.pageThumbnails[index],
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PdfToImagesSettingsPanel extends ConsumerWidget {
  const PdfToImagesSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfToImagesNotifierProvider);
    final notifier = ref.read(pdfToImagesNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formato de Imagen',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PdfImageOutputFormat>(
          segments: const [
            ButtonSegment(
              value: PdfImageOutputFormat.png,
              label: Text('PNG'),
            ),
            ButtonSegment(
              value: PdfImageOutputFormat.jpg,
              label: Text('JPG'),
            ),
          ],
          selected: {state.outputFormat},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateConfig(outputFormat: sel.first),
        ),
        const SizedBox(height: 20),

        if (state.outputFormat == PdfImageOutputFormat.jpg) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Calidad JPG',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${state.jpgQuality}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.pdfAccent,
                ),
              ),
            ],
          ),
          Slider(
            value: state.jpgQuality.toDouble(),
            min: 20,
            max: 100,
            divisions: 16,
            activeColor: AppTheme.pdfAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateConfig(jpgQuality: v.round()),
          ),
          const SizedBox(height: 12),
        ],

        Text(
          'Resolución (DPI)',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<PdfRasterDpiOption>(
          groupValue: state.dpiOption,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateConfig(dpiOption: val);
            }
          },
          child: Column(
            children: PdfRasterDpiOption.values.map((opt) {
              return RadioListTile<PdfRasterDpiOption>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(opt.label),
                value: opt,
                activeColor: AppTheme.pdfAccent,
                enabled: !state.isProcessing,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Modo de Exportación',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<PdfImagePackagingMode>(
          groupValue: state.packagingMode,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateConfig(packagingMode: val);
            }
          },
          child: Column(
            children: PdfImagePackagingMode.values.map((mode) {
              return RadioListTile<PdfImagePackagingMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(mode.label),
                value: mode,
                activeColor: AppTheme.pdfAccent,
                enabled: !state.isProcessing,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class PdfToImagesPrimaryActionButton extends ConsumerWidget {
  const PdfToImagesPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pdfToImagesNotifierProvider);
    final notifier = ref.read(pdfToImagesNotifierProvider.notifier);

    return FilledButton.icon(
      onPressed: (state.selectedPdfPath == null || state.isProcessing)
          ? null
          : notifier.extractAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.pdfAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.image, size: 18),
      label: Text(
        state.isProcessing
            ? 'Extrayendo...'
            : 'Extraer ${state.totalPages} Páginas',
      ),
    );
  }
}



