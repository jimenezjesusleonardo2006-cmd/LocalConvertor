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
import '../../domain/spreadsheet_converter_config.dart';
import '../providers/spreadsheet_converter_notifier.dart';

Future<void> pickSpreadsheetFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar Hoja de Cálculo (.xlsx, .xls, .ods)',
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'ods', 'xlsm', 'xlsb'],
  );
  if (file?.path != null) {
    await ref
        .read(spreadsheetConverterNotifierProvider.notifier)
        .loadWorkbook(file!.path!);
  }
}

class SpreadsheetConverterWorkspaceBody extends ConsumerWidget {
  const SpreadsheetConverterWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spreadsheetConverterNotifierProvider);
    final notifier = ref.read(spreadsheetConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Procesando hoja en Rust...',
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
                    title: 'Arrastra aquí un libro .XLSX, .XLS u .ODS',
                    subtitle:
                        'Procesamiento nativo en Rust con calamine sin requerir Microsoft Office. Exporta a CSV, JSON estructurado o PDF tabular.',
                    allowedExtensionsBadges: const [
                      '.XLSX',
                      '.XLS',
                      '.ODS',
                      'CSV / JSON / PDF',
                    ],
                    accentColor: AppTheme.docAccent,
                    onPickFilesPressed: () => pickSpreadsheetFile(ref),
                    onFilesDropped: (paths) {
                      if (paths.isNotEmpty) {
                        notifier.loadWorkbook(paths.first);
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
                        const Icon(LucideIcons.sheet, color: AppTheme.docAccent),
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
                              '${state.rowCount} filas × ${state.colCount} columnas • Hoja: ${state.selectedSheet ?? "-"}',
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
                          onPressed: () => pickSpreadsheetFile(ref),
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
                        'Vista previa (primeras filas)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: state.previewRows.isEmpty
                          ? const Center(child: Text('La hoja seleccionada está vacía.'))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowHeight: 40,
                                  dataRowMinHeight: 34,
                                  dataRowMaxHeight: 44,
                                  columns: [
                                    for (int c = 0;
                                        c < (state.previewRows.first.length.clamp(1, 10));
                                        c++)
                                      DataColumn(
                                        label: Text(
                                          state.previewRows.first[c].isEmpty
                                              ? 'Col ${c + 1}'
                                              : state.previewRows.first[c],
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                  ],
                                  rows: [
                                    for (final row in state.previewRows.skip(1))
                                      DataRow(
                                        cells: [
                                          for (int c = 0;
                                              c < (state.previewRows.first.length.clamp(1, 10));
                                              c++)
                                            DataCell(
                                              ConstrainedBox(
                                                constraints: const BoxConstraints(maxWidth: 180),
                                                child: Text(
                                                  c < row.length ? row[c] : '',
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
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

class SpreadsheetConverterSettingsPanel extends ConsumerWidget {
  const SpreadsheetConverterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spreadsheetConverterNotifierProvider);
    final notifier = ref.read(spreadsheetConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.sheetNames.isNotEmpty) ...[
          Text(
            'Hoja activa',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: state.selectedSheet,
            decoration: const InputDecoration(isDense: true),
            items: state.sheetNames
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) notifier.selectSheet(val);
            },
          ),
          const SizedBox(height: 20),
        ],
        Text(
          'Formato de Salida',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<SpreadsheetOutputFormat>(
          segments: SpreadsheetOutputFormat.values
              .map(
                (fmt) => ButtonSegment<SpreadsheetOutputFormat>(
                  value: fmt,
                  label: Text(fmt.label),
                ),
              )
              .toList(),
          selected: {state.targetFormat},
          onSelectionChanged: (sel) =>
              notifier.updateSettings(targetFormat: sel.first),
        ),
        if (state.targetFormat == SpreadsheetOutputFormat.csv) ...[
          const SizedBox(height: 20),
          Text(
            'Delimitador CSV',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: ',', label: Text('Coma (,)')),
              ButtonSegment(value: ';', label: Text('Punto y coma (;)')),
            ],
            selected: {state.csvDelimiter},
            onSelectionChanged: (sel) =>
                notifier.updateSettings(csvDelimiter: sel.first),
          ),
        ],
        if (state.targetFormat == SpreadsheetOutputFormat.pdf) ...[
          const SizedBox(height: 20),
          Text(
            'Tamaño de Hoja PDF',
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
            'Orientación',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PdfPageOrientationOption>(
            segments: const [
              ButtonSegment(
                value: PdfPageOrientationOption.landscape,
                label: Text('Horizontal'),
              ),
              ButtonSegment(
                value: PdfPageOrientationOption.portrait,
                label: Text('Vertical'),
              ),
            ],
            selected: {state.orientation},
            onSelectionChanged: (sel) =>
                notifier.updateSettings(orientation: sel.first),
          ),
        ],
      ],
    );
  }
}

class SpreadsheetConverterPrimaryActionButton extends ConsumerWidget {
  const SpreadsheetConverterPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spreadsheetConverterNotifierProvider);
    final enabled = state.selectedFilePath != null && !state.isProcessing;

    return FilledButton.icon(
      onPressed: enabled
          ? () => ref
              .read(spreadsheetConverterNotifierProvider.notifier)
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
