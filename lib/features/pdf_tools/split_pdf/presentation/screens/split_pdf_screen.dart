import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/split_pdf_config.dart';
import '../providers/split_pdf_notifier.dart';

/// Abre el selector nativo para cargar el PDF a dividir (invocable desde botón o Ctrl/Cmd+O).
Future<void> pickPdfForSplit(WidgetRef ref) async {
  final state = ref.read(splitPdfNotifierProvider);
  if (state.isProcessing) return;

  final picked = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar documento PDF para dividir',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  final filePath = picked?.path;
  if (filePath != null) {
    await ref.read(splitPdfNotifierProvider.notifier).selectPdfFile(filePath);
  }
}

class SplitPdfWorkspaceBody extends ConsumerWidget {
  const SplitPdfWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(splitPdfNotifierProvider);
    final notifier = ref.read(splitPdfNotifierProvider.notifier);
    final theme = Theme.of(context);
    final selectedPages = state.parsedRanges.uniqueSortedPages;

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
              statusText: state.statusMessage ?? 'Dividiendo PDF...',
              accentColor: AppTheme.pdfAccent,
              onCancel: notifier.cancelSplit,
            ),
            const SizedBox(height: 20),
          ],

          if (state.selectedPdfPath == null)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title: 'Arrastra y suelta un documento PDF para dividir',
                    subtitle:
                        'Extrae páginas individuales o rangos personalizados como "1-3, 5, 8-10".',
                    allowedExtensionsBadges: const ['PDF → Rangos / ZIP'],
                    accentColor: AppTheme.pdfAccent,
                    onPickFilesPressed: () => pickPdfForSplit(ref),
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
            Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.pdfAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.scissors,
                    color: AppTheme.pdfAccent,
                  ),
                ),
                title: Text(
                  p.basename(state.selectedPdfPath!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${selectedPages.length} de ${state.totalPages} páginas seleccionadas • Haz clic en cualquier página para incluirla o excluirla',
                ),
                trailing: TextButton.icon(
                  onPressed: state.isProcessing ? null : notifier.clearSelection,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Cambiar PDF'),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisExtent: 245,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: state.pageThumbnails.length,
                itemBuilder: (context, index) {
                  final pageNum = index + 1;
                  final isSelected = selectedPages.contains(pageNum);

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isSelected
                            ? AppTheme.pdfAccent
                            : theme.dividerColor.withValues(alpha: 0.2),
                        width: isSelected ? 2.2 : 1.0,
                      ),
                    ),
                    child: InkWell(
                      onTap: state.isProcessing
                          ? null
                          : () => notifier.togglePageSelection(pageNum),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            color: isSelected
                                ? AppTheme.pdfAccent.withValues(alpha: 0.14)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Página $pageNum',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? AppTheme.pdfAccent
                                        : null,
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? LucideIcons.checkCircle2
                                      : LucideIcons.circle,
                                  size: 16,
                                  color: isSelected
                                      ? AppTheme.pdfAccent
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Opacity(
                              opacity: isSelected ? 1.0 : 0.42,
                              child: Container(
                                color: Colors.black12,
                                padding: const EdgeInsets.all(8),
                                child: Image.memory(
                                  state.pageThumbnails[index],
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

class SplitPdfSettingsPanel extends ConsumerStatefulWidget {
  const SplitPdfSettingsPanel({super.key});

  @override
  ConsumerState<SplitPdfSettingsPanel> createState() =>
      _SplitPdfSettingsPanelState();
}

class _SplitPdfSettingsPanelState extends ConsumerState<SplitPdfSettingsPanel> {
  late final TextEditingController _rangeController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(splitPdfNotifierProvider).rangeExpression;
    _rangeController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(splitPdfNotifierProvider);
    final notifier = ref.read(splitPdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    // Sincronizar el TextField si el usuario hizo clic en las miniaturas
    if (_rangeController.text != state.rangeExpression) {
      _rangeController.value = TextEditingValue(
        text: state.rangeExpression,
        selection:
            TextSelection.collapsed(offset: state.rangeExpression.length),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rangos de Páginas',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _rangeController,
          enabled: !state.isProcessing && state.selectedPdfPath != null,
          onChanged: notifier.updateRangeExpression,
          decoration: InputDecoration(
            hintText: 'Ej: 1-3, 5, 8-10',
            prefixIcon: const Icon(LucideIcons.hash, size: 18),
            errorText: state.selectedPdfPath != null
                ? state.parsedRanges.validationError
                : null,
            errorMaxLines: 3,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Escribe páginas o rangos separados por coma (ej. 1-3, 5, 8-10) o toca directamente las miniaturas.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),

        // Atajos rápidos de selección
        if (state.totalPages > 0) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Todas'),
                onPressed: state.isProcessing
                    ? null
                    : () => notifier
                        .updateRangeExpression('1-${state.totalPages}'),
              ),
              ActionChip(
                label: const Text('Impares'),
                onPressed: state.isProcessing
                    ? null
                    : () {
                        final odds = [
                          for (int i = 1; i <= state.totalPages; i += 2) i,
                        ].join(', ');
                        notifier.updateRangeExpression(odds);
                      },
              ),
              ActionChip(
                label: const Text('Pares'),
                onPressed: state.isProcessing
                    ? null
                    : () {
                        final evens = [
                          for (int i = 2; i <= state.totalPages; i += 2) i,
                        ].join(', ');
                        if (evens.isNotEmpty) {
                          notifier.updateRangeExpression(evens);
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        Text(
          'Modo de Extracción',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<SplitOutputMode>(
          groupValue: state.outputMode,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateOutputMode(val);
            }
          },
          child: Column(
            children: SplitOutputMode.values.map((mode) {
              return RadioListTile<SplitOutputMode>(
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

class SplitPdfPrimaryActionButton extends ConsumerWidget {
  const SplitPdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(splitPdfNotifierProvider);
    final notifier = ref.read(splitPdfNotifierProvider.notifier);
    final count = state.parsedRanges.uniqueSortedPages.length;

    return FilledButton.icon(
      onPressed: (state.selectedPdfPath == null ||
              !state.parsedRanges.isValid ||
              state.isProcessing)
          ? null
          : notifier.splitAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.pdfAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.scissors, size: 18),
      label: Text(
        state.isProcessing
            ? 'Dividiendo en Isolate...'
            : 'Extraer $count Páginas',
      ),
    );
  }
}



