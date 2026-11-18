import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../../../pdf_tools/images_to_pdf/domain/image_to_pdf_config.dart';
import '../../domain/markdown_to_pdf_config.dart';
import '../providers/markdown_to_pdf_notifier.dart';

/// Abre el selector nativo para cargar un archivo `.md` o `.txt` (invocable desde botón o Ctrl/Cmd+O).
Future<void> pickMarkdownOrTextFile(WidgetRef ref) async {
  final state = ref.read(markdownToPdfNotifierProvider);
  if (state.isProcessing) return;

  final picked = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar archivo Markdown (.md) o Texto (.txt)',
    type: FileType.custom,
    allowedExtensions: ['md', 'markdown', 'txt'],
  );

  final filePath = picked?.path;
  if (filePath != null) {
    await ref
        .read(markdownToPdfNotifierProvider.notifier)
        .loadDocumentFile(filePath);
  }
}

class MarkdownToPdfWorkspaceBody extends ConsumerStatefulWidget {
  const MarkdownToPdfWorkspaceBody({super.key});

  @override
  ConsumerState<MarkdownToPdfWorkspaceBody> createState() =>
      _MarkdownToPdfWorkspaceBodyState();
}

class _MarkdownToPdfWorkspaceBodyState
    extends ConsumerState<MarkdownToPdfWorkspaceBody> {
  late final TextEditingController _editorController;

  @override
  void initState() {
    super.initState();
    _editorController = TextEditingController(
      text: ref.read(markdownToPdfNotifierProvider).content,
    );
  }

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(markdownToPdfNotifierProvider);
    final notifier = ref.read(markdownToPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (_editorController.text != state.content) {
      _editorController.value = TextEditingValue(
        text: state.content,
        selection: TextSelection.collapsed(offset: state.content.length),
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

          if (state.selectedFilePath == null && state.content.isEmpty)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DesktopDropZone(
                          title:
                              'Arrastra y suelta un archivo .MD o .TXT aquí',
                          subtitle:
                              'Compila encabezados, listas, citas y bloques de código a un documento PDF multipágina.',
                          allowedExtensionsBadges: const [
                            'MD → PDF',
                            'TXT → PDF',
                          ],
                          accentColor: AppTheme.docAccent,
                          onPickFilesPressed: () => pickMarkdownOrTextFile(ref),
                          onFilesDropped: (paths) {
                            if (paths.isNotEmpty) {
                              notifier.loadDocumentFile(paths.first);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: () {
                            notifier.updateTextContent(
                              '# Informe LocalConvert\n\n'
                              'Este documento fue generado **100% en local** sin llamadas de red.\n\n'
                              '## Características Principales\n'
                              '- Procesamiento aislado en `Isolate`\n'
                              '- Limpieza automática de `CacheDir`\n'
                              '- Soporte de bloques de código y citas\n\n'
                              '> Privacidad garantizada por diseño.\n\n'
                              '```dart\n'
                              'final pdf = await compileToPdfInIsolate(config);\n'
                              '```',
                            );
                          },
                          icon: const Icon(LucideIcons.edit3, size: 16),
                          label: const Text(
                            'O escribe / pega Markdown directamente en el editor',
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
                    final actionButtons = <Widget>[
                      OutlinedButton.icon(
                        onPressed: state.isProcessing
                            ? null
                            : () => pickMarkdownOrTextFile(ref),
                        icon: const Icon(LucideIcons.folderOpen, size: 16),
                        label: const Text('Abrir archivo'),
                      ),
                      TextButton.icon(
                        onPressed:
                            state.isProcessing ? null : notifier.clearFile,
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
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.docAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                LucideIcons.fileCode,
                                color: AppTheme.docAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.selectedFilePath != null
                                        ? p.basename(state.selectedFilePath!)
                                        : 'Editor Markdown / Texto en Vivo',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${state.content.length} caracteres • Modo ${state.isMarkdown ? "Markdown AST" : "Texto Plano"}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            if (isWide) ...[
                              const SizedBox(width: 12),
                              Wrap(spacing: 8, children: actionButtons),
                            ],
                          ],
                        ),
                        if (!isWide) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: actionButtons,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Editor interactivo del contenido .md / .txt antes de exportar a PDF
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _editorController,
                    maxLines: null,
                    expands: true,
                    onChanged: notifier.updateTextContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Escribe o edita tu contenido Markdown o Texto aquí...',
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

class MarkdownToPdfSettingsPanel extends ConsumerWidget {
  const MarkdownToPdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(markdownToPdfNotifierProvider);
    final notifier = ref.read(markdownToPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de Interpretación',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Markdown (.md)'),
            ),
            ButtonSegment(
              value: false,
              label: Text('Texto Plano (.txt)'),
            ),
          ],
          selected: {state.isMarkdown},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateSettings(isMarkdown: sel.first),
        ),
        const SizedBox(height: 20),

        Text(
          'Tamaño de Página',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PdfPageSizeOption>(
          segments: const [
            ButtonSegment(
              value: PdfPageSizeOption.a4,
              label: Text('A4'),
            ),
            ButtonSegment(
              value: PdfPageSizeOption.letter,
              label: Text('Carta'),
            ),
          ],
          selected: {state.pageSize},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateSettings(pageSize: sel.first),
        ),
        const SizedBox(height: 20),

        Text(
          'Márgenes del Documento',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PdfMarginOption>(
          segments: const [
            ButtonSegment(
              value: PdfMarginOption.small,
              label: Text('Delgado'),
            ),
            ButtonSegment(
              value: PdfMarginOption.large,
              label: Text('Estándar'),
            ),
          ],
          selected: {
            state.margin == PdfMarginOption.none
                ? PdfMarginOption.small
                : state.margin,
          },
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateSettings(margin: sel.first),
        ),
        const SizedBox(height: 20),

        Text(
          'Escala Tipográfica',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<DocFontScaleOption>(
          groupValue: state.fontScale,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateSettings(fontScale: val);
            }
          },
          child: Column(
            children: DocFontScaleOption.values.map((opt) {
              return RadioListTile<DocFontScaleOption>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(opt.label),
                value: opt,
                activeColor: AppTheme.docAccent,
                enabled: !state.isProcessing,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Numerar páginas al pie'),
          value: state.showPageNumbers,
          activeThumbColor: AppTheme.docAccent,
          onChanged: state.isProcessing
              ? null
              : (val) => notifier.updateSettings(showPageNumbers: val),
        ),
      ],
    );
  }
}

class MarkdownToPdfPrimaryActionButton extends ConsumerWidget {
  const MarkdownToPdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(markdownToPdfNotifierProvider);
    final notifier = ref.read(markdownToPdfNotifierProvider.notifier);

    return FilledButton.icon(
      onPressed: (state.content.trim().isEmpty || state.isProcessing)
          ? null
          : notifier.convertAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.docAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.fileCheck2, size: 18),
      label: Text(
        state.isProcessing ? 'Compilando PDF...' : 'Exportar a PDF (Ctrl+S)',
      ),
    );
  }
}



