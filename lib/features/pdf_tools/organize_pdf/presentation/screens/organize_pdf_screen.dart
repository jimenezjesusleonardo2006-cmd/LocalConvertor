import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/organize_pdf_config.dart';
import '../providers/organize_pdf_notifier.dart';

Future<void> pickPdfForOrganize(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar PDF para organizar y rotar (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (file?.path != null) {
    await ref.read(organizePdfNotifierProvider.notifier).loadPdfFile(file!.path!);
  }
}

class OrganizePdfWorkspaceBody extends ConsumerWidget {
  const OrganizePdfWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizePdfNotifierProvider);
    final notifier = ref.read(organizePdfNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Procesando...',
            accentColor: AppTheme.pdfAccent,
            onCancel: notifier.cancelProcess,
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

          if (state.sourcePdfPath == null)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: DesktopDropZone(
                      title: 'Arrastra aquí un archivo PDF para organizar',
                      subtitle:
                          'Rota páginas individuales 90°/180°/270°, arrastra para reordenar o elimina las que no necesites conservando vectores.',
                      allowedExtensionsBadges: const ['PDF Vectorial'],
                      accentColor: AppTheme.pdfAccent,
                      onPickFilesPressed: () => pickPdfForOrganize(ref),
                      onFilesDropped: (paths) {
                        if (paths.isNotEmpty) {
                          notifier.loadPdfFile(paths.first);
                        }
                      },
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.fileText,
                          color: AppTheme.pdfAccent,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(state.sourcePdfPath!),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${state.pages.length} páginas activas',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => notifier.rotateAllPages(),
                          icon: const Icon(LucideIcons.rotateCw, size: 15),
                          label: const Text('Rotar todas +90°'),
                        ),
                        TextButton.icon(
                          onPressed: notifier.resetOrder,
                          icon: const Icon(LucideIcons.rotateCcw, size: 15),
                          label: const Text('Restablecer'),
                        ),
                        TextButton.icon(
                          onPressed: notifier.clear,
                          icon: const Icon(LucideIcons.trash2, size: 15),
                          label: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ReorderableGridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 215,
                  mainAxisExtent: 265,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: state.pages.length,
                onReorder: notifier.reorderPages,
                itemBuilder: (context, index) {
                  final item = state.pages[index];
                  return _OrganizePageCard(
                    key: ValueKey('org_${item.id}_${item.originalPageIndex}'),
                    item: item,
                    displayPosition: index + 1,
                    canDelete: state.pages.length > 1,
                    onRotateLeft: () =>
                        notifier.rotatePage(index, deltaDegrees: -90),
                    onRotateRight: () =>
                        notifier.rotatePage(index, deltaDegrees: 90),
                    onDelete: () => notifier.removePageAt(index),
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

class _OrganizePageCard extends StatelessWidget {
  final OrganizePdfPageItem item;
  final int displayPosition;
  final bool canDelete;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onDelete;

  const _OrganizePageCard({
    super.key,
    required this.item,
    required this.displayPosition,
    required this.canDelete,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quarterTurns = (item.rotationDeltaDegrees ~/ 90) % 4;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.pdfAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Pos. $displayPosition',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (item.rotationDeltaDegrees != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.pdfAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${item.rotationDeltaDegrees}°',
                      style: const TextStyle(
                        color: AppTheme.pdfAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                if (canDelete)
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 15),
                    tooltip: 'Eliminar página',
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: quarterTurns,
                  child: item.thumbnailBytes != null
                      ? Image.memory(
                          item.thumbnailBytes!,
                          cacheWidth: MemoryGuardConfig.thumbnailDecodeWidthPx,
                          fit: BoxFit.contain,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.fileText,
                              size: 32,
                              color: AppTheme.pdfAccent,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pág. orig. ${item.originalPageIndex + 1}',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: onRotateLeft,
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  tooltip: 'Rotar -90°',
                ),
                Text(
                  'Orig. #${item.originalPageIndex + 1}',
                  style: theme.textTheme.labelSmall,
                ),
                IconButton(
                  onPressed: onRotateRight,
                  icon: const Icon(LucideIcons.rotateCw, size: 16),
                  tooltip: 'Rotar +90°',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OrganizePdfSettingsPanel extends ConsumerWidget {
  const OrganizePdfSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizePdfNotifierProvider);
    final notifier = ref.read(organizePdfNotifierProvider.notifier);
    final theme = Theme.of(context);
    final rotatedCount =
        state.pages.where((p) => p.rotationDeltaDegrees != 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen de Organización',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Páginas activas:')),
                    Text(
                      '${state.pages.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('Páginas rotadas:')),
                    Text(
                      '$rotatedCount',
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
        ),
        const SizedBox(height: 16),
        Text(
          'Acciones en Lote',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: state.pages.isEmpty
                ? null
                : () => notifier.rotateAllPages(deltaDegrees: 90),
            icon: const Icon(LucideIcons.rotateCw, size: 16),
            label: const Text('Rotar todas +90°'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: state.pages.isEmpty ? null : notifier.resetOrder,
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('Restablecer documento'),
          ),
        ),
        const SizedBox(height: 20),
        const StatusBanner(
          message:
              'Preserva texto seleccionable, fuentes y vectores originales del PDF.',
          icon: LucideIcons.shieldCheck,
          color: AppTheme.privacyBadge,
        ),
      ],
    );
  }
}

class OrganizePdfPrimaryActionButton extends ConsumerWidget {
  const OrganizePdfPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(organizePdfNotifierProvider);
    final canExport =
        state.sourcePdfPath != null && state.pages.isNotEmpty && !state.isProcessing;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canExport
            ? () => ref
                .read(organizePdfNotifierProvider.notifier)
                .organizeAndExport()
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.pdfAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.download, size: 18),
        label: const Text(
          'Guardar PDF Organizado',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
