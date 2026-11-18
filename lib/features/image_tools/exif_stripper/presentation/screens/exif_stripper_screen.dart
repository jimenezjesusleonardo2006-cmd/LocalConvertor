import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/file_size_formatter.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../providers/exif_stripper_notifier.dart';

Future<void> pickImagesForExifStripper(WidgetRef ref) async {
  final state = ref.read(exifStripperNotifierProvider);
  if (state.isProcessing) return;

  final result = await FilePicker.pickFiles(
    dialogTitle: 'Seleccionar imágenes para limpiar metadatos EXIF/GPS',
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'tif', 'tiff'],
  );

  if (result.isNotEmpty) {
    final paths = result.map((f) => f.path).whereType<String>().toList();
    await ref.read(exifStripperNotifierProvider.notifier).addImageFiles(paths);
  }
}

class ExifStripperWorkspaceBody extends ConsumerWidget {
  const ExifStripperWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exifStripperNotifierProvider);
    final notifier = ref.read(exifStripperNotifierProvider.notifier);
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
              icon: LucideIcons.shieldCheck,
              color: AppTheme.privacyBadge,
            ),
            const SizedBox(height: 16),
          ],

          if (state.isProcessing) ...[
            DeterministicProgressBar(
              progress: state.progress,
              statusText: state.statusMessage ?? 'Eliminando metadatos...',
              accentColor: AppTheme.imageAccent,
              onCancel: notifier.cancelProcess,
            ),
            const SizedBox(height: 20),
          ],

          if (state.files.isEmpty)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: DesktopDropZone(
                      title: 'Arrastra fotos para borrar ubicación GPS y EXIF',
                      subtitle:
                          'Inspecciona y elimina cámara, coordenadas GPS, software y fechas en Isolate local conservando la orientación visual.',
                      allowedExtensionsBadges: const [
                        'JPG',
                        'PNG',
                        'WEBP',
                        'TIFF',
                      ],
                      accentColor: AppTheme.imageAccent,
                      onPickFilesPressed: () => pickImagesForExifStripper(ref),
                      onFilesDropped: notifier.addImageFiles,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            DesktopDropZone(
              title:
                  '${state.files.length} archivos • ${state.totalDetectedTags} etiquetas EXIF detectadas',
              subtitle: 'Suelta más imágenes para limpiar en el mismo lote.',
              allowedExtensionsBadges: const ['Sin GPS', 'Sin EXIF', 'Sin ICC'],
              accentColor: AppTheme.imageAccent,
              compact: true,
              onPickFilesPressed: () => pickImagesForExifStripper(ref),
              onFilesDropped: notifier.addImageFiles,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: state.files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = state.files[index];
                  final previewTags = item.detectedTags.take(4).join(' • ');
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(item.path),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              cacheWidth:
                                  MemoryGuardConfig.thumbnailDecodeWidthPx,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 56,
                                height: 56,
                                child: Icon(LucideIcons.image),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.fileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.detectedTags.isEmpty
                                      ? '${formatFileSize(item.originalSizeBytes)} • Sin etiquetas EXIF expuestas'
                                      : '${formatFileSize(item.originalSizeBytes)} • ${item.detectedTags.length} etiquetas ($previewTags)',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: state.isProcessing
                                ? null
                                : () => notifier.removeFileAt(index),
                            icon: Icon(
                              LucideIcons.trash2,
                              size: 18,
                              color: theme.colorScheme.error,
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

class ExifStripperSettingsPanel extends ConsumerWidget {
  const ExifStripperSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exifStripperNotifierProvider);
    final notifier = ref.read(exifStripperNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen de Privacidad',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Imágenes cargadas:')),
                    Text(
                      '${state.files.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('Etiquetas EXIF detectadas:')),
                    Text(
                      '${state.totalDetectedTags}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.imageAccent,
                      ),
                    ),
                  ],
                ),
                if (state.lastTotalTagsRemoved != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Etiquetas eliminadas:')),
                      Text(
                        '${state.lastTotalTagsRemoved}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.privacyBadge,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Empaquetar siempre en .ZIP'),
          subtitle: const Text('Automático al limpiar 2 o más imágenes.'),
          value: state.packageAsZip || state.files.length > 1,
          activeThumbColor: AppTheme.imageAccent,
          onChanged: (state.isProcessing || state.files.length > 1)
              ? null
              : (v) => notifier.updateSettings(packageAsZip: v),
        ),
        const SizedBox(height: 16),
        const StatusBanner(
          message:
              'Hornea la orientación visual (EXIF Orientation) antes de borrar GPS, cámara y perfiles ICC.',
          icon: LucideIcons.shieldCheck,
          color: AppTheme.privacyBadge,
        ),
      ],
    );
  }
}

class ExifStripperPrimaryActionButton extends ConsumerWidget {
  const ExifStripperPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exifStripperNotifierProvider);
    final notifier = ref.read(exifStripperNotifierProvider.notifier);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: (state.files.isEmpty || state.isProcessing)
            ? null
            : notifier.stripAndExport,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.imageAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.shieldCheck, size: 18),
        label: Text(
          state.isProcessing
              ? 'Limpiando en Isolate...'
              : 'Limpiar Metadatos (${state.files.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
