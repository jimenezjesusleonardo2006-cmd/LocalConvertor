import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/merge_pdf_config.dart';
import '../providers/merge_pdf_notifier.dart';

/// Abre el selector nativo de múltiples archivos PDF (invocable desde botón o Ctrl/Cmd+O).
Future<void> pickPdfFilesForMerge(WidgetRef ref) async {
  final state = ref.read(mergePdfNotifierProvider);
  if (state.isProcessing) return;

  final result = await FilePicker.pickFiles(
    dialogTitle: 'Seleccionar documentos PDF para unir',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  if (result.isNotEmpty) { final paths = result.map((f) => f.path).whereType<String>().toList();
    await ref.read(mergePdfNotifierProvider.notifier).addPdfFiles(paths);
  }
}

class MergePdfWorkspaceBody extends ConsumerWidget {
  const MergePdfWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mergePdfNotifierProvider);
    final notifier = ref.read(mergePdfNotifierProvider.notifier);
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
              statusText: state.statusMessage ?? 'Uniendo documentos PDF...',
              accentColor: AppTheme.pdfAccent,
              onCancel: notifier.cancelMerge,
            ),
            const SizedBox(height: 20),
          ],

          if (state.documents.isEmpty)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title: 'Arrastra y suelta varios archivos PDF aquí',
                    subtitle:
                        'Podrás reordenar su secuencia con Drag & Drop antes de fusionarlos en un solo documento.',
                    allowedExtensionsBadges: const ['PDF + PDF → 1 PDF'],
                    accentColor: AppTheme.pdfAccent,
                    onPickFilesPressed: () => pickPdfFilesForMerge(ref),
                    onFilesDropped: notifier.addPdfFiles,
                  ),
                ),
              ),
            )
          else ...[
            DesktopDropZone(
              title:
                  '${state.documents.length} documentos (${state.totalCombinedPages} páginas en total) • Arrastra para cambiar el orden',
              subtitle:
                  'Necesitas al menos 2 documentos PDF para realizar la unión.',
              allowedExtensionsBadges: const ['PDF'],
              accentColor: AppTheme.pdfAccent,
              compact: true,
              onPickFilesPressed: () => pickPdfFilesForMerge(ref),
              onFilesDropped: notifier.addPdfFiles,
            ),
            const SizedBox(height: 18),

            Expanded(
              child: ReorderableGridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 225,
                  mainAxisExtent: 260,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: state.documents.length,
                onReorder: notifier.reorderDocuments,
                itemBuilder: (context, index) {
                  final doc = state.documents[index];
                  return _MergePdfCard(
                    key: ValueKey(doc.id),
                    doc: doc,
                    sequenceOrder: index + 1,
                    onRemove: state.isProcessing
                        ? null
                        : () => notifier.removeDocumentAt(index),
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

class MergePdfSettingsPanel extends ConsumerWidget {
  const MergePdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mergePdfNotifierProvider);
    final notifier = ref.read(mergePdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen de Unión',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.pdfAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(child: Text('Documentos cargados:')),
                  const SizedBox(width: 8),
                  Text(
                    '${state.documents.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(child: Text('Total páginas combinadas:')),
                  const SizedBox(width: 8),
                  Text(
                    '${state.totalCombinedPages}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.pdfAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Calidad de Ensamblaje',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<MergePdfQualityPreset>(
          groupValue: state.qualityPreset,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateQualityPreset(val);
            }
          },
          child: Column(
            children: MergePdfQualityPreset.values.map((preset) {
              return RadioListTile<MergePdfQualityPreset>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(preset.label),
                value: preset,
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

class MergePdfPrimaryActionButton extends ConsumerWidget {
  const MergePdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mergePdfNotifierProvider);
    final notifier = ref.read(mergePdfNotifierProvider.notifier);

    return FilledButton.icon(
      onPressed: (state.documents.length < 2 || state.isProcessing)
          ? null
          : notifier.mergeAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.pdfAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.files, size: 18),
      label: Text(
        state.isProcessing
            ? 'Uniendo en Isolate...'
            : 'Unir ${state.documents.length} PDFs',
      ),
    );
  }
}

class _MergePdfCard extends StatelessWidget {
  final MergePdfDocumentItem doc;
  final int sequenceOrder;
  final VoidCallback? onRemove;

  const _MergePdfCard({
    super.key,
    required this.doc,
    required this.sequenceOrder,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            child: Row(
              children: [
                const Icon(LucideIcons.gripVertical, size: 14),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.pdfAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Doc #$sequenceOrder',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 15,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black12,
              padding: const EdgeInsets.all(8),
              child: doc.coverThumbnail != null
                  ? Image.memory(doc.coverThumbnail!, fit: BoxFit.contain)
                  : const Center(
                      child: Icon(
                        LucideIcons.fileText,
                        size: 36,
                        color: AppTheme.pdfAccent,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  doc.pageCount > 0
                      ? '${doc.pageCount} páginas'
                      : 'Analizando páginas...',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.pdfAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



