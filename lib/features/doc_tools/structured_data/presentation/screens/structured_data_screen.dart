import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/structured_data_config.dart';
import '../providers/structured_data_notifier.dart';

Future<void> pickStructuredDataFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar CSV, JSON o XML (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['csv', 'json', 'xml'],
  );
  if (file?.path != null) {
    await ref.read(structuredDataNotifierProvider.notifier).loadFile(
          file!.path!,
        );
  }
}

class StructuredDataWorkspaceBody extends ConsumerStatefulWidget {
  const StructuredDataWorkspaceBody({super.key});

  @override
  ConsumerState<StructuredDataWorkspaceBody> createState() =>
      _StructuredDataWorkspaceBodyState();
}

class _StructuredDataWorkspaceBodyState
    extends ConsumerState<StructuredDataWorkspaceBody> {
  late final TextEditingController _inputController;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(
      text: ref.read(structuredDataNotifierProvider).inputContent,
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(structuredDataNotifierProvider);
    final notifier = ref.read(structuredDataNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (_inputController.text != state.inputContent) {
      _inputController.value = TextEditingValue(
        text: state.inputContent,
        selection: TextSelection.collapsed(offset: state.inputContent.length),
      );
    }

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Procesando datos...',
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
          ] else if (state.syntaxError != null) ...[
            StatusBanner(
              message:
                  'Error de sintaxis (${state.sourceFormat.label}): ${state.syntaxError}',
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

          if (state.selectedFilePath == null && state.inputContent.isEmpty)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DesktopDropZone(
                          title: 'Arrastra aquí un archivo .CSV, .JSON o .XML',
                          subtitle:
                              'Valida sintaxis al instante, transforma bidireccionalmente entre CSV / JSON / XML o exporta CSV como tabla PDF paginada.',
                          allowedExtensionsBadges: const [
                            'CSV ↔ JSON ↔ XML',
                            'CSV → Tabla PDF',
                          ],
                          accentColor: AppTheme.docAccent,
                          onPickFilesPressed: () => pickStructuredDataFile(ref),
                          onFilesDropped: (paths) {
                            if (paths.isNotEmpty) {
                              notifier.loadFile(paths.first);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: notifier.loadSampleCsv,
                          icon: const Icon(LucideIcons.table, size: 16),
                          label: const Text(
                            'O cargar tabla CSV de ejemplo con editor en vivo',
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
                        onPressed: () => pickStructuredDataFile(ref),
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
                              LucideIcons.table,
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
                                        : 'Editor de Datos (${state.sourceFormat.label})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    state.syntaxError == null &&
                                            state.rowCount != null
                                        ? '${state.rowCount} filas • ${state.columnCount} columnas • Sintaxis válida'
                                        : 'Entrada ${state.sourceFormat.label} → Salida ${state.targetFormat.label}',
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showPreviewSideBySide =
                      state.livePreviewText != null && constraints.maxWidth >= 680;
                  final editorCard = Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _inputController,
                        maxLines: null,
                        expands: true,
                        onChanged: notifier.updateInputContent,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Pega aquí tus datos CSV, JSON o XML...',
                        ),
                      ),
                    ),
                  );

                  if (!showPreviewSideBySide) {
                    return editorCard;
                  }

                  return Row(
                    children: [
                      Expanded(child: editorCard),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                state.livePreviewText!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

class StructuredDataSettingsPanel extends ConsumerWidget {
  const StructuredDataSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(structuredDataNotifierProvider);
    final notifier = ref.read(structuredDataNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formato de Entrada',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<StructuredDataFormat>(
          segments: const [
            ButtonSegment(value: StructuredDataFormat.csv, label: Text('CSV')),
            ButtonSegment(value: StructuredDataFormat.json, label: Text('JSON')),
            ButtonSegment(value: StructuredDataFormat.xml, label: Text('XML')),
          ],
          selected: {state.sourceFormat},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateSettings(sourceFormat: sel.first),
        ),
        const SizedBox(height: 18),
        Text(
          'Formato de Salida',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        RadioGroup<StructuredDataFormat>(
          groupValue: state.targetFormat,
          onChanged: (v) {
            if (!state.isProcessing && v != null) {
              notifier.updateSettings(targetFormat: v);
            }
          },
          child: Column(
            children: StructuredDataFormat.values.map((fmt) {
              return RadioListTile<StructuredDataFormat>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(fmt.label, style: const TextStyle(fontSize: 13)),
                value: fmt,
              );
            }).toList(),
          ),
        ),
        if (state.sourceFormat == StructuredDataFormat.csv ||
            state.targetFormat == StructuredDataFormat.csv) ...[
          const SizedBox(height: 12),
          Text(
            'Delimitador CSV',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: ',', label: Text('Coma (,)')),
              ButtonSegment(value: ';', label: Text('Punto y coma (;)')),
            ],
            selected: {state.csvDelimiter},
            onSelectionChanged: state.isProcessing
                ? null
                : (sel) => notifier.updateSettings(csvDelimiter: sel.first),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Formatear salida (Pretty Print)'),
          value: state.prettyPrint,
          activeThumbColor: AppTheme.docAccent,
          onChanged: state.isProcessing
              ? null
              : (v) => notifier.updateSettings(prettyPrint: v),
        ),
      ],
    );
  }
}

class StructuredDataPrimaryActionButton extends ConsumerWidget {
  const StructuredDataPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(structuredDataNotifierProvider);
    final canRun = state.inputContent.trim().isNotEmpty &&
        state.syntaxError == null &&
        !state.isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canRun
            ? () => ref
                .read(structuredDataNotifierProvider.notifier)
                .convertAndExport()
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.docAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.download, size: 18),
        label: Text(
          'Convertir y Guardar ${state.targetFormat.label}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
