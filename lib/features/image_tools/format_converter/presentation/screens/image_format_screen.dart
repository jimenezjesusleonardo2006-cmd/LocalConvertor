import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/image_format_config.dart';
import '../providers/image_format_notifier.dart';

/// Abre el selector nativo para cargar imágenes a convertir (invocable desde botón o Ctrl/Cmd+O).
Future<void> pickImagesForFormatConversion(WidgetRef ref) async {
  final state = ref.read(imageFormatConverterNotifierProvider);
  if (state.isProcessing) return;

  final result = await FilePicker.pickFiles(
    dialogTitle:
        'Seleccionar imágenes (PNG, JPG, WEBP, BMP, TIFF, ICO, GIF, TGA, SVG)',
    type: FileType.custom,
    allowedExtensions: [
      'png',
      'jpg',
      'jpeg',
      'webp',
      'bmp',
      'tif',
      'tiff',
      'ico',
      'gif',
      'tga',
      'svg',
    ],
  );

  if (result.isNotEmpty) { final paths = result.map((f) => f.path).whereType<String>().toList();
    await ref
        .read(imageFormatConverterNotifierProvider.notifier)
        .addImageFiles(paths);
  }
}

class ImageFormatConverterWorkspaceBody extends ConsumerWidget {
  const ImageFormatConverterWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageFormatConverterNotifierProvider);
    final notifier = ref.read(imageFormatConverterNotifierProvider.notifier);
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
              statusText: state.statusMessage ?? 'Convirtiendo formatos...',
              accentColor: AppTheme.imageAccent,
              onCancel: notifier.cancelConversion,
            ),
            const SizedBox(height: 20),
          ],

          if (state.files.isEmpty)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title: 'Arrastra y suelta tus imágenes para cambiar su formato',
                    subtitle:
                        'Conversión por lotes en memoria local entre PNG, JPG, WEBP, BMP, TIFF, ICO, GIF, TGA y rasterización de SVG.',
                    allowedExtensionsBadges: const [
                      'PNG',
                      'JPG',
                      'WEBP',
                      'TIFF',
                      'ICO',
                      'GIF',
                      'TGA',
                      'SVG',
                    ],
                    accentColor: AppTheme.imageAccent,
                    onPickFilesPressed: () =>
                        pickImagesForFormatConversion(ref),
                    onFilesDropped: notifier.addImageFiles,
                  ),
                ),
              ),
            )
          else ...[
            DesktopDropZone(
              title:
                  '${state.files.length} imágenes en cola → Convertir a .${state.targetFormat.extension.toUpperCase()}',
              subtitle:
                  'Suelta más archivos aquí para agregarlos al lote actual.',
              allowedExtensionsBadges: const [
                'PNG',
                'JPG',
                'WEBP',
                'TIFF',
                'SVG',
              ],
              accentColor: AppTheme.imageAccent,
              compact: true,
              onPickFilesPressed: () => pickImagesForFormatConversion(ref),
              onFilesDropped: notifier.addImageFiles,
            ),
            const SizedBox(height: 16),

            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 245,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: state.files.length,
                itemBuilder: (context, index) {
                  final item = state.files[index];
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
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.imageAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${item.sourceExtension} → ${state.targetFormat.label}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.imageAccent,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: state.isProcessing
                                    ? null
                                    : () => notifier.removeFileAt(index),
                                child: Icon(
                                  LucideIcons.trash2,
                                  size: 15,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: Colors.black12,
                            padding: const EdgeInsets.all(8),
                            child: item.sourceExtension == 'SVG'
                                ? SvgPicture.file(
                                    File(item.path),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(LucideIcons.image, size: 28),
                                    ),
                                  )
                                : Image.file(
                                    File(item.path),
                                    fit: BoxFit.contain,
                                    cacheWidth:
                                        MemoryGuardConfig.thumbnailDecodeWidthPx,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(LucideIcons.image, size: 28),
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
                                item.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _formatBytes(item.originalSizeBytes),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ],
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }
}

class ImageFormatConverterSettingsPanel extends ConsumerWidget {
  const ImageFormatConverterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageFormatConverterNotifierProvider);
    final notifier = ref.read(imageFormatConverterNotifierProvider.notifier);
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
        RadioGroup<TargetImageFormat>(
          groupValue: state.targetFormat,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateSettings(targetFormat: val);
            }
          },
          child: Column(
            children: TargetImageFormat.values.map((fmt) {
              return RadioListTile<TargetImageFormat>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  fmt.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(fmt.description),
                value: fmt,
                activeColor: AppTheme.imageAccent,
                enabled: !state.isProcessing,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        if (state.targetFormat == TargetImageFormat.jpg ||
            state.targetFormat == TargetImageFormat.webp) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Calidad de Codificación',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${state.quality}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.imageAccent,
                ),
              ),
            ],
          ),
          Slider(
            value: state.quality.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            activeColor: AppTheme.imageAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateSettings(quality: v.round()),
          ),
          const SizedBox(height: 12),
        ],

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Empaquetar siempre en .ZIP'),
          subtitle: const Text(
            'Automático cuando se convierten 2 o más imágenes.',
          ),
          value: state.packageAsZip || state.files.length > 1,
          activeThumbColor: AppTheme.imageAccent,
          onChanged: (state.isProcessing || state.files.length > 1)
              ? null
              : (val) => notifier.updateSettings(packageAsZip: val),
        ),
        const SizedBox(height: 12),
        Text(
          'Escala para SVG de entrada',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1x')),
            ButtonSegment(value: 2, label: Text('2x')),
            ButtonSegment(value: 4, label: Text('4x')),
          ],
          selected: {state.svgScaleMultiplier},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateSettings(
                    svgScaleMultiplier: sel.first,
                  ),
        ),
      ],
    );
  }
}

class ImageFormatConverterPrimaryActionButton extends ConsumerWidget {
  const ImageFormatConverterPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageFormatConverterNotifierProvider);
    final notifier = ref.read(imageFormatConverterNotifierProvider.notifier);

    return FilledButton.icon(
      onPressed: (state.files.isEmpty || state.isProcessing)
          ? null
          : notifier.convertAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.imageAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.refreshCw, size: 18),
      label: Text(
        state.isProcessing
            ? 'Convirtiendo en Isolate...'
            : 'Convertir a ${state.targetFormat.label} (${state.files.length})',
      ),
    );
  }
}



