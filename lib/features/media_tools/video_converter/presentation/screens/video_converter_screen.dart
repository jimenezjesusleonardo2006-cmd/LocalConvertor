import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/file_size_formatter.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../providers/video_converter_notifier.dart';

Future<void> pickVideoFileForConversion(WidgetRef ref) async {
  final state = ref.read(videoConverterNotifierProvider);
  if (state.isProcessing) return;

  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar video para convertir o comprimir (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v'],
  );
  if (file?.path != null) {
    await ref.read(videoConverterNotifierProvider.notifier).loadVideoFile(
          file!.path!,
        );
  }
}

class VideoConverterWorkspaceBody extends ConsumerStatefulWidget {
  const VideoConverterWorkspaceBody({super.key});

  @override
  ConsumerState<VideoConverterWorkspaceBody> createState() =>
      _VideoConverterWorkspaceBodyState();
}

class _VideoConverterWorkspaceBodyState
    extends ConsumerState<VideoConverterWorkspaceBody> {
  final _trimStartCtrl = TextEditingController();
  final _trimEndCtrl = TextEditingController();

  @override
  void dispose() {
    _trimStartCtrl.dispose();
    _trimEndCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoConverterNotifierProvider);
    final notifier = ref.read(videoConverterNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Transcodificando video...',
            accentColor: AppTheme.mediaAccent,
            onCancel: notifier.cancelConversion,
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

          if (state.selectedVideoPath == null)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: DesktopDropZone(
                      title: 'Arrastra aquí un archivo de video para convertir o comprimir',
                      subtitle:
                          'Procesamiento local con FFmpeg hacia MP4, MKV, WEBM (VP9), MOV, AVI o GIF animado con recorte Trim y silencio.',
                      allowedExtensionsBadges: const [
                        'MP4',
                        'MKV',
                        'WEBM',
                        'MOV',
                        'AVI',
                        'GIF',
                      ],
                      accentColor: AppTheme.mediaAccent,
                      onPickFilesPressed: () => pickVideoFileForConversion(ref),
                      onFilesDropped: (paths) {
                        if (paths.isNotEmpty) {
                          notifier.loadVideoFile(paths.first);
                        }
                      },
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.mediaAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                LucideIcons.video,
                                color: AppTheme.mediaAccent,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.basename(state.selectedVideoPath!),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tamaño original: ${formatFileSize(state.originalSizeBytes)} • Salida: ${state.format.label}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: notifier.clear,
                              icon: const Icon(LucideIcons.trash2, size: 16),
                              label: const Text('Quitar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recorte Opcional (Trim)',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Deja vacío para convertir completo, o indica inicio/fin en formato MM:SS (ej. 00:15).',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _trimStartCtrl,
                                    onChanged: (v) =>
                                        notifier.updateConfig(trimStartText: v),
                                    decoration: const InputDecoration(
                                      labelText: 'Inicio (MM:SS)',
                                      hintText: '00:00',
                                      prefixIcon: Icon(LucideIcons.scissors),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _trimEndCtrl,
                                    onChanged: (v) =>
                                        notifier.updateConfig(trimEndText: v),
                                    decoration: const InputDecoration(
                                      labelText: 'Fin (MM:SS)',
                                      hintText: '01:30',
                                      prefixIcon: Icon(LucideIcons.clock),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VideoConverterSettingsPanel extends ConsumerWidget {
  const VideoConverterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoConverterNotifierProvider);
    final notifier = ref.read(videoConverterNotifierProvider.notifier);
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
        RadioGroup<VideoOutputFormat>(
          groupValue: state.format,
          onChanged: (v) {
            if (!state.isProcessing && v != null) {
              notifier.updateConfig(format: v);
            }
          },
          child: Column(
            children: VideoOutputFormat.values.map((fmt) {
              return RadioListTile<VideoOutputFormat>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(fmt.label, style: const TextStyle(fontSize: 13)),
                value: fmt,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Resolución',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: VideoResolutionPreset.values.map((res) {
            final selected = state.resolution == res;
            return ChoiceChip(
              label: Text(res.label),
              selected: selected,
              onSelected: state.isProcessing
                  ? null
                  : (_) => notifier.updateConfig(resolution: res),
            );
          }).toList(),
        ),
        if (state.format != VideoOutputFormat.gif) ...[
          const SizedBox(height: 16),
          Text(
            'Nivel de Compresión (CRF)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          RadioGroup<VideoCrfPreset>(
            groupValue: state.crfPreset,
            onChanged: (v) {
              if (!state.isProcessing && v != null) {
                notifier.updateConfig(crfPreset: v);
              }
            },
            child: Column(
              children: VideoCrfPreset.values.map((preset) {
                return RadioListTile<VideoCrfPreset>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title:
                      Text(preset.label, style: const TextStyle(fontSize: 13)),
                  value: preset,
                );
              }).toList(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Silenciar audio (Mute)'),
            value: state.muteAudio,
            activeThumbColor: AppTheme.mediaAccent,
            onChanged: state.isProcessing
                ? null
                : (v) => notifier.updateConfig(muteAudio: v),
          ),
        ],
      ],
    );
  }
}

class VideoConverterPrimaryActionButton extends ConsumerWidget {
  const VideoConverterPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoConverterNotifierProvider);
    final notifier = ref.read(videoConverterNotifierProvider.notifier);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: (state.selectedVideoPath == null || state.isProcessing)
            ? null
            : notifier.convertAndExport,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.mediaAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.video, size: 18),
        label: Text(
          state.isProcessing
              ? 'Transcodificando...'
              : 'Convertir a ${state.format.extension.toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
