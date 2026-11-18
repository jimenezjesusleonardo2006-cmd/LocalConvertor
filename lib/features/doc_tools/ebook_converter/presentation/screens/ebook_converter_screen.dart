import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/ebook_converter_config.dart';
import '../providers/ebook_converter_notifier.dart';

Future<void> pickHtmlOrEpubFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar archivo .HTML o .EPUB (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['epub', 'html', 'htm', 'xhtml'],
  );
  if (file?.path != null) {
    await ref.read(ebookConverterNotifierProvider.notifier).loadFile(
          file!.path!,
        );
  }
}

class EbookConverterWorkspaceBody extends ConsumerWidget {
  const EbookConverterWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ebookConverterNotifierProvider);
    final notifier = ref.read(ebookConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Compilando libro/HTML...',
            accentColor: AppTheme.docAccent,
            onCancel: () {},
          ),
        ),
      );
    }

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
          ] else if (state.statusMessage != null) ...[
            StatusBanner(
              message: state.statusMessage!,
              icon: LucideIcons.checkCircle2,
              color: AppTheme.privacyBadge,
            ),
            const SizedBox(height: 16),
          ],

          if (!state.hasInput)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DesktopDropZone(
                          title: 'Arrastra aquí un libro .EPUB o página .HTML',
                          subtitle:
                              'Extrae capítulos XHTML locales y estructura HTML para exportar a texto plano .TXT o documento .PDF paginado.',
                          allowedExtensionsBadges: const [
                            'EPUB → PDF / TXT',
                            'HTML → PDF / TXT',
                          ],
                          accentColor: AppTheme.docAccent,
                          onPickFilesPressed: () => pickHtmlOrEpubFile(ref),
                          onFilesDropped: (paths) {
                            if (paths.isNotEmpty) {
                              notifier.loadFile(paths.first);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: notifier.loadSampleHtml,
                          icon: const Icon(LucideIcons.bookOpen, size: 16),
                          label: const Text(
                            'O cargar documento HTML de ejemplo para previsualizar',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final buttons = <Widget>[
                      OutlinedButton.icon(
                        onPressed: () => pickHtmlOrEpubFile(ref),
                        icon: const Icon(LucideIcons.folderOpen, size: 16),
                        label: const Text('Abrir archivo'),
                      ),
                      TextButton.icon(
                        onPressed: notifier.clear,
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        label: const Text('Limpiar'),
                      ),
                    ];
                    final isWide = constraints.maxWidth >= 560;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.bookOpen,
                              color: AppTheme.docAccent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.selectedFilePath != null
                                        ? p.basename(state.selectedFilePath!)
                                        : state.extractedTitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${state.chapterCount} capítulo(s) • ${state.previewText.length} caracteres extraídos',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (isWide) ...[
                              const SizedBox(width: 12),
                              Wrap(spacing: 8, children: buttons),
                            ],
                          ],
                        ),
                        if (!isWide) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: buttons,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      state.previewText,
                      style: const TextStyle(fontSize: 13.5, height: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EbookConverterSettingsPanel extends ConsumerWidget {
  const EbookConverterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ebookConverterNotifierProvider);
    final notifier = ref.read(ebookConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formato de Salida',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<EbookTargetFormat>(
          groupValue: state.targetFormat,
          onChanged: (v) {
            if (!state.isProcessing && v != null) {
              notifier.updateSettings(targetFormat: v);
            }
          },
          child: Column(
            children: EbookTargetFormat.values.map((fmt) {
              return RadioListTile<EbookTargetFormat>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(fmt.label, style: const TextStyle(fontSize: 13)),
                value: fmt,
              );
            }).toList(),
          ),
        ),
        if (state.targetFormat == EbookTargetFormat.pdf) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Text('Escala tipográfica:')),
              Text(
                '${state.fontScale.toStringAsFixed(1)}x',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.docAccent,
                ),
              ),
            ],
          ),
          Slider(
            value: state.fontScale,
            min: 0.8,
            max: 1.4,
            divisions: 6,
            activeColor: AppTheme.docAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateSettings(fontScale: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Numerar páginas al pie'),
            value: state.includePageNumbers,
            activeThumbColor: AppTheme.docAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateSettings(includePageNumbers: v),
          ),
        ],
      ],
    );
  }
}

class EbookConverterPrimaryActionButton extends ConsumerWidget {
  const EbookConverterPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ebookConverterNotifierProvider);
    final canRun = state.hasInput && !state.isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canRun
            ? () => ref
                .read(ebookConverterNotifierProvider.notifier)
                .convertAndExport()
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.docAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.download, size: 18),
        label: Text(
          'Exportar a ${state.targetFormat.extension.toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
