import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/constants/memory_guard_config.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/compressor_resizer_config.dart';
import '../providers/compressor_resizer_notifier.dart';

/// Abre el selector nativo para cargar imágenes a comprimir/redimensionar (Ctrl/Cmd+O).
Future<void> pickImagesForCompression(WidgetRef ref) async {
  final state = ref.read(compressorResizerNotifierProvider);
  if (state.isProcessing) return;

  final result = await FilePicker.pickFiles(
    dialogTitle: 'Seleccionar imágenes para comprimir / redimensionar',
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );

  if (result.isNotEmpty) { final paths = result.map((f) => f.path).whereType<String>().toList();
    await ref
        .read(compressorResizerNotifierProvider.notifier)
        .addImageFiles(paths);
  }
}

class CompressorResizerWorkspaceBody extends ConsumerWidget {
  const CompressorResizerWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compressorResizerNotifierProvider);
    final notifier = ref.read(compressorResizerNotifierProvider.notifier);
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
              statusText: state.statusMessage ?? 'Optimizando imágenes...',
              accentColor: AppTheme.imageAccent,
              onCancel: notifier.cancelCompression,
            ),
            const SizedBox(height: 20),
          ],

          if (state.files.isEmpty)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: DesktopDropZone(
                    title:
                        'Arrastra y suelta imágenes para comprimir y redimensionar',
                    subtitle:
                        'Ajusta la calidad de 1 a 100 con estimación en tiempo real del peso final y reduce la resolución por porcentaje o píxeles exactos.',
                    allowedExtensionsBadges: const ['JPG', 'PNG', 'WEBP'],
                    accentColor: AppTheme.imageAccent,
                    onPickFilesPressed: () => pickImagesForCompression(ref),
                    onFilesDropped: notifier.addImageFiles,
                  ),
                ),
              ),
            )
          else ...[
            DesktopDropZone(
              title:
                  '${state.files.length} imágenes listas para comprimir (Calidad: ${state.quality}%)',
              subtitle:
                  'La tarjeta de estimación en el panel de ajustes muestra el peso resultante en tiempo real.',
              allowedExtensionsBadges: const ['JPG', 'PNG', 'WEBP'],
              accentColor: AppTheme.imageAccent,
              compact: true,
              onPickFilesPressed: () => pickImagesForCompression(ref),
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
                              if (index == 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.imageAccent,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'Muestra en vivo',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  '#${index + 1}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
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
                            child: Image.file(
                              File(item.path),
                              fit: BoxFit.contain,
                              cacheWidth: MemoryGuardConfig.thumbnailDecodeWidthPx,
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
                                'Original: ${_formatBytes(item.originalSizeBytes)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
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

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }
}

class CompressorResizerSettingsPanel extends ConsumerWidget {
  const CompressorResizerSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compressorResizerNotifierProvider);
    final notifier = ref.read(compressorResizerNotifierProvider.notifier);
    final theme = Theme.of(context);
    final estimate = state.liveEstimate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Tarjeta de Estimación de Peso Final en Tiempo Real
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.imageAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.imageAccent.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.gauge,
                    size: 16,
                    color: AppTheme.imageAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Estimación de Peso Final',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.imageAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (state.isEstimating)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (estimate == null)
                Text(
                  'Carga al menos una imagen para calcular el peso estimado en tiempo real.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      CompressorResizerWorkspaceBody._formatBytes(
                        estimate.originalBytes,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const Icon(LucideIcons.arrowRight, size: 15),
                    Text(
                      CompressorResizerWorkspaceBody._formatBytes(
                        estimate.estimatedBytes,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.imageAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${estimate.originalWidth}×${estimate.originalHeight} → ${estimate.targetWidth}×${estimate.targetHeight} px',
                      style: theme.textTheme.labelSmall,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: estimate.savingsPercent >= 0
                            ? AppTheme.privacyBadge.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        estimate.savingsPercent >= 0
                            ? '-${estimate.savingsPercent.toStringAsFixed(1)}%'
                            : '+${estimate.savingsPercent.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: estimate.savingsPercent >= 0
                              ? AppTheme.privacyBadge
                              : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),

        // 2. Slider de Calidad (1 a 100)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Calidad (1 a 100)',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.imageAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${state.quality}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.imageAccent,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: state.quality.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          activeColor: AppTheme.imageAccent,
          label: '${state.quality}',
          onChanged: state.isProcessing
              ? null
              : (v) => notifier.updateParameters(quality: v.round()),
        ),
        const SizedBox(height: 16),

        // 3. Modo de Redimensionamiento
        Text(
          'Redimensionar Resolución',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ImageResizeMode>(
          segments: const [
            ButtonSegment(
              value: ImageResizeMode.percentage,
              label: Text('Porcentaje (%)'),
            ),
            ButtonSegment(
              value: ImageResizeMode.exactDimensions,
              label: Text('Píxeles (px)'),
            ),
          ],
          selected: {state.resizeMode},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateParameters(resizeMode: sel.first),
        ),
        const SizedBox(height: 16),

        if (state.resizeMode == ImageResizeMode.percentage) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(child: Text('Escala de resolución:')),
              const SizedBox(width: 8),
              Text(
                '${state.scalePercent}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.imageAccent,
                ),
              ),
            ],
          ),
          Slider(
            value: state.scalePercent.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            activeColor: AppTheme.imageAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateParameters(scalePercent: v.round()),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  enabled: !state.isProcessing,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Ancho (px)',
                    hintText: estimate != null
                        ? '${estimate.originalWidth}'
                        : 'Ej: 1920',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val);
                    notifier.updateParameters(
                      targetWidthPx: parsed,
                      clearTargetWidth: parsed == null,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  enabled: !state.isProcessing,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Alto (px)',
                    hintText: estimate != null
                        ? '${estimate.originalHeight}'
                        : 'Ej: 1080',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val);
                    notifier.updateParameters(
                      targetHeightPx: parsed,
                      clearTargetHeight: parsed == null,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Mantener proporción de aspecto'),
            value: state.maintainAspectRatio,
            activeThumbColor: AppTheme.imageAccent,
            onChanged: state.isProcessing
                ? null
                : (val) =>
                    notifier.updateParameters(maintainAspectRatio: val),
          ),
        ],
      ],
    );
  }
}

class CompressorResizerPrimaryActionButton extends ConsumerWidget {
  const CompressorResizerPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compressorResizerNotifierProvider);
    final notifier = ref.read(compressorResizerNotifierProvider.notifier);

    return FilledButton.icon(
      onPressed: (state.files.isEmpty || state.isProcessing)
          ? null
          : notifier.compressAndExport,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.imageAccent,
        foregroundColor: Colors.white,
      ),
      icon: const Icon(LucideIcons.minimize2, size: 18),
      label: Text(
        state.isProcessing
            ? 'Comprimiendo en Isolate...'
            : 'Comprimir y Guardar (${state.files.length})',
      ),
    );
  }
}



