import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import '../../../markdown_to_pdf/domain/markdown_to_pdf_config.dart';
import '../../domain/docx_converter_config.dart';
import '../providers/docx_converter_notifier.dart';

Future<void> pickDocxFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar Documento Word (.docx)',
    type: FileType.custom,
    allowedExtensions: ['docx'],
  );
  if (file?.path != null) {
    await ref
        .read(docxConverterNotifierProvider.notifier)
        .loadDocxFile(file!.path!);
  }
}

class DocxConverterWorkspaceBody extends ConsumerWidget {
  const DocxConverterWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(docxConverterNotifierProvider);
    final notifier = ref.read(docxConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Procesando .DOCX en Rust...',
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
          if (state.selectedFilePath == null)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title: 'Arrastra aquí un documento Word .DOCX',
                    subtitle:
                        'Extrae XML nativo en Rust conservando encabezados, negritas, cursivas, listas y tablas hacia PDF, Markdown o texto plano.',
                    allowedExtensionsBadges: const [
                      '.DOCX → PDF',
                      '.DOCX → MD',
                      '.DOCX → TXT',
                    ],
                    accentColor: AppTheme.docAccent,
                    onPickFilesPressed: () => pickDocxFile(ref),
                    onFilesDropped: (paths) {
                      if (paths.isNotEmpty) {
                        notifier.loadDocxFile(paths.first);
                      }
                    },
                  ),
                ),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.fileText, color: AppTheme.docAccent),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.basename(state.selectedFilePath!),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${state.paragraphCount} párrafos • ${state.tableCount} tabla(s)',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => pickDocxFile(ref),
                          icon: const Icon(LucideIcons.folderOpen, size: 16),
                          label: const Text('Cambiar archivo'),
                        ),
                        TextButton.icon(
                          onPressed: notifier.clear,
                          icon: const Icon(LucideIcons.trash2, size: 16),
                          label: const Text('Limpiar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Text(
                        'Vista previa de estructura extraída (Markdown)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          state.previewMarkdown.isEmpty
                              ? '(Sin contenido textual)'
                              : state.previewMarkdown,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DocxConverterSettingsPanel extends ConsumerWidget {
  const DocxConverterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(docxConverterNotifierProvider);
    final notifier = ref.read(docxConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Formato de Salida',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DocxOutputFormat>(
          segments: DocxOutputFormat.values
              .map(
                (fmt) => ButtonSegment<DocxOutputFormat>(
                  value: fmt,
                  label: Text(fmt.label),
                ),
              )
              .toList(),
          selected: {state.targetFormat},
          onSelectionChanged: (sel) =>
              notifier.updateSettings(targetFormat: sel.first),
        ),
        if (state.targetFormat == DocxOutputFormat.pdf) ...[
          const SizedBox(height: 20),
          Text(
            'Tamaño de Hoja',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PdfPageSizeOption>(
            segments: const [
              ButtonSegment(value: PdfPageSizeOption.a4, label: Text('A4')),
              ButtonSegment(value: PdfPageSizeOption.letter, label: Text('Carta')),
            ],
            selected: {
              state.pageSize == PdfPageSizeOption.letter
                  ? PdfPageSizeOption.letter
                  : PdfPageSizeOption.a4,
            },
            onSelectionChanged: (sel) =>
                notifier.updateSettings(pageSize: sel.first),
          ),
          const SizedBox(height: 16),
          Text(
            'Escala Tipográfica',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DocFontScaleOption>(
            isExpanded: true,
            initialValue: state.fontScale,
            decoration: const InputDecoration(isDense: true),
            items: DocFontScaleOption.values
                .map(
                  (opt) => DropdownMenuItem(
                    value: opt,
                    child: Text(opt.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (val) => notifier.updateSettings(fontScale: val),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Numerar páginas'),
            value: state.showPageNumbers,
            onChanged: (v) => notifier.updateSettings(showPageNumbers: v),
          ),
        ],
      ],
    );
  }
}

class DocxConverterPrimaryActionButton extends ConsumerWidget {
  const DocxConverterPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(docxConverterNotifierProvider);
    final enabled = state.selectedFilePath != null && !state.isProcessing;

    return FilledButton.icon(
      onPressed: enabled
          ? () => ref
              .read(docxConverterNotifierProvider.notifier)
              .convertAndExport()
          : null,
      style: FilledButton.styleFrom(backgroundColor: AppTheme.docAccent),
      icon: const Icon(LucideIcons.download),
      label: Text(
        'Convertir a ${state.targetFormat.label}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
