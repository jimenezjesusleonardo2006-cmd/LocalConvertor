import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/file_size_formatter.dart';
import '../../../../../shared/widgets/desktop_drop_zone.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../providers/audio_converter_notifier.dart';

Future<void> pickAudioFilesForConversion(WidgetRef ref) async {
  final state = ref.read(audioConverterNotifierProvider);
  if (state.isProcessing) return;

  final result = await FilePicker.pickFiles(
    dialogTitle: 'Seleccionar archivos de audio (MP3, WAV, M4A, OGG, FLAC, OPUS)',
    type: FileType.custom,
    allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg', 'flac', 'opus', 'aac', 'wma'],
  );

  if (result.isNotEmpty) {
    final paths = result.map((f) => f.path).whereType<String>().toList();
    await ref.read(audioConverterNotifierProvider.notifier).addAudioFiles(paths);
  }
}

class AudioConverterWorkspaceBody extends ConsumerWidget {
  const AudioConverterWorkspaceBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioConverterNotifierProvider);
    final notifier = ref.read(audioConverterNotifierProvider.notifier);
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
              statusText: state.statusMessage ?? 'Convirtiendo audio...',
              accentColor: AppTheme.mediaAccent,
              onCancel: notifier.cancelConversion,
            ),
            const SizedBox(height: 20),
          ],

          if (state.files.isEmpty)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: DesktopDropZone(
                      title: 'Arrastra y suelta pistas de audio para convertir por lotes',
                      subtitle:
                          'Transcodificación 100% local con FFmpeg entre MP3, WAV, M4A (AAC), OGG, FLAC y OPUS.',
                      allowedExtensionsBadges: const [
                        'MP3',
                        'WAV',
                        'M4A',
                        'OGG',
                        'FLAC',
                        'OPUS',
                      ],
                      accentColor: AppTheme.mediaAccent,
                      onPickFilesPressed: () => pickAudioFilesForConversion(ref),
                      onFilesDropped: notifier.addAudioFiles,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            DesktopDropZone(
              title:
                  '${state.files.length} pista(s) → .${state.targetFormat.extension.toUpperCase()}',
              subtitle: 'Suelta más archivos de audio aquí para agregarlos al lote.',
              allowedExtensionsBadges: const ['MP3', 'WAV', 'FLAC', 'OPUS'],
              accentColor: AppTheme.mediaAccent,
              compact: true,
              onPickFilesPressed: () => pickAudioFilesForConversion(ref),
              onFilesDropped: notifier.addAudioFiles,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: state.files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = state.files[index];
                  return Card(
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.mediaAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.music,
                          color: AppTheme.mediaAccent,
                        ),
                      ),
                      title: Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${item.sourceExtension} → ${state.targetFormat.label} • ${formatFileSize(item.sizeBytes)}',
                      ),
                      trailing: IconButton(
                        onPressed: state.isProcessing
                            ? null
                            : () => notifier.removeFileAt(index),
                        icon: Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
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

class AudioConverterSettingsPanel extends ConsumerWidget {
  const AudioConverterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioConverterNotifierProvider);
    final notifier = ref.read(audioConverterNotifierProvider.notifier);
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
        const SizedBox(height: 6),
        RadioGroup<AudioOutputFormat>(
          groupValue: state.targetFormat,
          onChanged: (val) {
            if (!state.isProcessing && val != null) {
              notifier.updateConfig(targetFormat: val);
            }
          },
          child: Column(
            children: AudioOutputFormat.values.map((fmt) {
              return RadioListTile<AudioOutputFormat>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(fmt.label, style: const TextStyle(fontSize: 13)),
                value: fmt,
              );
            }).toList(),
          ),
        ),
        if (state.targetFormat.usesBitrate) ...[
          const SizedBox(height: 14),
          Text(
            'Bitrate de Audio',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<AudioBitrateOption>(
            segments: AudioBitrateOption.values
                .map(
                  (b) => ButtonSegment(
                    value: b,
                    label: Text('${b.kbps}k'),
                  ),
                )
                .toList(),
            selected: {state.bitrate},
            onSelectionChanged: state.isProcessing
                ? null
                : (sel) => notifier.updateConfig(bitrate: sel.first),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Frecuencia de Muestreo',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<AudioSampleRateOption>(
          segments: AudioSampleRateOption.values
              .map((sr) => ButtonSegment(value: sr, label: Text(sr.label)))
              .toList(),
          selected: {state.sampleRate},
          onSelectionChanged: state.isProcessing
              ? null
              : (sel) => notifier.updateConfig(sampleRate: sel.first),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Empaquetar siempre en .ZIP'),
          subtitle: const Text('Automático para lotes de 2 o más audios.'),
          value: state.packageAsZip || state.files.length > 1,
          activeThumbColor: AppTheme.mediaAccent,
          onChanged: (state.isProcessing || state.files.length > 1)
              ? null
              : (v) => notifier.updateConfig(packageAsZip: v),
        ),
      ],
    );
  }
}

class AudioConverterPrimaryActionButton extends ConsumerWidget {
  const AudioConverterPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioConverterNotifierProvider);
    final notifier = ref.read(audioConverterNotifierProvider.notifier);

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: (state.files.isEmpty || state.isProcessing)
            ? null
            : notifier.convertAndExport,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.mediaAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.music, size: 18),
        label: Text(
          state.isProcessing
              ? 'Procesando lote...'
              : 'Convertir a ${state.targetFormat.extension.toUpperCase()} (${state.files.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
