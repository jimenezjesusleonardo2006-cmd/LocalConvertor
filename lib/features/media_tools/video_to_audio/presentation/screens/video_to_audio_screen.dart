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
import '../providers/video_to_audio_notifier.dart';

Future<void> pickVideoForAudioExtraction(WidgetRef ref) async {
  final state = ref.read(videoToAudioNotifierProvider);
  if (state.isProcessing) return;

  final file = await FilePicker.pickFile(
    dialogTitle: 'Seleccionar video para extraer audio (LocalConvert)',
    type: FileType.custom,
    allowedExtensions: ['mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v'],
  );
  if (file?.path != null) {
    await ref.read(videoToAudioNotifierProvider.notifier).loadVideoFile(
          file!.path!,
        );
  }
}

class VideoToAudioWorkspaceBody extends ConsumerWidget {
  const VideoToAudioWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoToAudioNotifierProvider);
    final notifier = ref.read(videoToAudioNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (state.isProcessing) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DeterministicProgressBar(
            progress: state.progress,
            statusText: state.statusMessage ?? 'Extrayendo audio...',
            accentColor: AppTheme.mediaAccent,
            onCancel: notifier.cancelExtraction,
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
                      title: 'Arrastra aquí un video para extraer su pista de audio',
                      subtitle:
                          'Convierte a MP3, M4A o WAV localmente, con modo rápido sin pérdida (Stream Copy) si el códec es compatible.',
                      allowedExtensionsBadges: const [
                        'MP4 / MKV / MOV',
                        'MP3',
                        'M4A',
                        'WAV',
                      ],
                      accentColor: AppTheme.mediaAccent,
                      onPickFilesPressed: () =>
                          pickVideoForAudioExtraction(ref),
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
                child: Card(
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
                            LucideIcons.fileAudio,
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
                                'Peso del video: ${formatFileSize(state.originalSizeBytes)} → Extraer como ${state.format.label}',
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
              ),
            ),
        ],
      ),
    );
  }
}

class VideoToAudioSettingsPanel extends ConsumerWidget {
  const VideoToAudioSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoToAudioNotifierProvider);
    final notifier = ref.read(videoToAudioNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formato de Audio Destino',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        RadioGroup<AudioExtractFormat>(
          groupValue: state.format,
          onChanged: (v) {
            if (!state.isProcessing && v != null) {
              notifier.updateConfig(format: v);
            }
          },
          child: Column(
            children: AudioExtractFormat.values.map((fmt) {
              return RadioListTile<AudioExtractFormat>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(fmt.label, style: const TextStyle(fontSize: 13)),
                value: fmt,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Extracción rápida sin pérdida (Stream Copy)'),
          subtitle: const Text(
            'Copia directa sin recodificar cuando el contenedor y códec son compatibles (.M4A).',
          ),
          value: state.streamCopyFastMode,
          activeThumbColor: AppTheme.mediaAccent,
          onChanged: state.isProcessing
              ? null
              : (v) => notifier.updateConfig(streamCopyFastMode: v),
        ),
        if (state.format != AudioExtractFormat.wav &&
            !state.streamCopyFastMode) ...[
          const SizedBox(height: 14),
          Text(
            'Bitrate de Salida',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<AudioBitrateOption>(
            segments: AudioBitrateOption.values
                .map((b) => ButtonSegment(value: b, label: Text('${b.kbps}k')))
                .toList(),
            selected: {state.bitrate},
            onSelectionChanged: state.isProcessing
                ? null
                : (sel) => notifier.updateConfig(bitrate: sel.first),
          ),
        ],
      ],
    );
  }
}

class VideoToAudioPrimaryActionButton extends ConsumerWidget {
  const VideoToAudioPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoToAudioNotifierProvider);
    final notifier = ref.read(videoToAudioNotifierProvider.notifier);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: (state.selectedVideoPath == null || state.isProcessing)
            ? null
            : notifier.extractAndExport,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.mediaAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.fileAudio, size: 18),
        label: Text(
          state.isProcessing
              ? 'Extrayendo...'
              : 'Extraer a .${state.format.extension.toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
