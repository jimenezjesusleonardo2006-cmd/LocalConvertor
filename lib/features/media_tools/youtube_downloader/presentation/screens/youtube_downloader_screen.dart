import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/media/ffmpeg_progress_parser.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/deterministic_progress_bar.dart';
import '../../../../../shared/widgets/status_banner.dart';
import '../../domain/youtube_downloader_config.dart';
import '../providers/youtube_downloader_notifier.dart';

Future<void> pasteYoutubeUrlFromClipboard(WidgetRef ref) async {
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  final text = clip?.text?.trim();
  if (text != null && text.isNotEmpty) {
    await ref
        .read(youtubeDownloaderNotifierProvider.notifier)
        .fetchVideoMetadata(text);
  }
}

class YoutubeDownloaderWorkspaceBody extends ConsumerStatefulWidget {
  const YoutubeDownloaderWorkspaceBody({super.key});

  @override
  ConsumerState<YoutubeDownloaderWorkspaceBody> createState() =>
      _YoutubeDownloaderWorkspaceBodyState();
}

class _YoutubeDownloaderWorkspaceBodyState
    extends ConsumerState<YoutubeDownloaderWorkspaceBody> {
  final _urlCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(youtubeDownloaderNotifierProvider);
    final notifier = ref.read(youtubeDownloaderNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (_urlCtrl.text != state.urlInput && state.urlInput.isNotEmpty) {
      _urlCtrl.value = TextEditingValue(
        text: state.urlInput,
        selection: TextSelection.collapsed(offset: state.urlInput.length),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StatusBanner(
              message:
                  'Requiere conexión directa a YouTube — Sin servidores intermediarios, sin proxies ni telemetría.',
              icon: LucideIcons.wifi,
              color: AppTheme.youtubeAccent,
            ),
            const SizedBox(height: 16),

            if (state.errorMessage != null) ...[
              StatusBanner(
                message: state.errorMessage!,
                icon: LucideIcons.alertTriangle,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
            ] else if (!state.isDownloading && state.statusMessage != null) ...[
              StatusBanner(
                message: state.statusMessage!,
                icon: LucideIcons.checkCircle2,
                color: AppTheme.privacyBadge,
              ),
              const SizedBox(height: 16),
            ],

            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enlace de YouTube',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _urlCtrl,
                      onChanged: notifier.updateUrl,
                      decoration: const InputDecoration(
                        hintText: 'https://www.youtube.com/watch?v=...',
                        prefixIcon: Icon(LucideIcons.link),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: state.isDownloading
                              ? null
                              : () => pasteYoutubeUrlFromClipboard(ref),
                          icon: const Icon(LucideIcons.clipboardPaste, size: 16),
                          label: const Text('Pegar del portapapeles'),
                        ),
                        FilledButton.icon(
                          onPressed: (state.isFetchingMetadata ||
                                  state.isDownloading)
                              ? null
                              : () => notifier.fetchVideoMetadata(_urlCtrl.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.youtubeAccent,
                            foregroundColor: Colors.white,
                          ),
                          icon: state.isFetchingMetadata
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(LucideIcons.search, size: 16),
                          label: const Text('Obtener Video'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (state.isDownloading) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StageChip(
                            label: '1. Obteniendo flujos',
                            active: state.stage ==
                                YoutubeDownloadStage.fetchingStreams,
                          ),
                          _StageChip(
                            label: '2. Descargando',
                            active:
                                state.stage == YoutubeDownloadStage.downloading,
                          ),
                          _StageChip(
                            label: '3. Ensamblando archivo',
                            active:
                                state.stage == YoutubeDownloadStage.assembling,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DeterministicProgressBar(
                        progress: state.progress,
                        statusText:
                            state.statusMessage ?? state.stage.label,
                        accentColor: AppTheme.youtubeAccent,
                        onCancel: notifier.cancelDownload,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (state.videoInfo != null) ...[
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 520;
                      final thumb = ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          state.videoInfo!.thumbnailUrl,
                          width: isWide ? 180 : double.infinity,
                          height: 108,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: isWide ? 180 : double.infinity,
                            height: 108,
                            color: AppTheme.youtubeAccent.withValues(alpha: 0.1),
                            child: const Icon(
                              LucideIcons.playCircle,
                              size: 36,
                              color: AppTheme.youtubeAccent,
                            ),
                          ),
                        ),
                      );
                      final infoCol = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.videoInfo!.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Canal: ${state.videoInfo!.author}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (state.videoInfo!.duration != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Duración: ${FfmpegProgressParser.formatDuration(state.videoInfo!.duration!)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      );

                      if (!isWide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [thumb, const SizedBox(height: 12), infoCol],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          thumb,
                          const SizedBox(width: 16),
                          Expanded(child: infoCol),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  final String label;
  final bool active;

  const _StageChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.youtubeAccent
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : null,
        ),
      ),
    );
  }
}

class YoutubeDownloaderSettingsPanel extends ConsumerWidget {
  const YoutubeDownloaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(youtubeDownloaderNotifierProvider);
    final notifier = ref.read(youtubeDownloaderNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de Descarga',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<YoutubeDownloadMode>(
          segments: YoutubeDownloadMode.values
              .map((m) => ButtonSegment(value: m, label: Text(m.label)))
              .toList(),
          selected: {state.mode},
          onSelectionChanged: state.isDownloading
              ? null
              : (sel) => notifier.updateSettings(mode: sel.first),
        ),
        const SizedBox(height: 16),
        if (state.mode == YoutubeDownloadMode.videoMp4) ...[
          Text(
            'Resolución MP4',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          RadioGroup<YoutubeVideoQualityOption>(
            groupValue: state.videoQuality,
            onChanged: (v) {
              if (!state.isDownloading && v != null) {
                notifier.updateSettings(videoQuality: v);
              }
            },
            child: Column(
              children: YoutubeVideoQualityOption.values.map((q) {
                return RadioListTile<YoutubeVideoQualityOption>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(q.label, style: const TextStyle(fontSize: 13)),
                  value: q,
                );
              }).toList(),
            ),
          ),
        ] else ...[
          Text(
            'Formato Solo Audio',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          RadioGroup<YoutubeAudioFormatOption>(
            groupValue: state.audioFormat,
            onChanged: (v) {
              if (!state.isDownloading && v != null) {
                notifier.updateSettings(audioFormat: v);
              }
            },
            child: Column(
              children: YoutubeAudioFormatOption.values.map((fmt) {
                return RadioListTile<YoutubeAudioFormatOption>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(fmt.label, style: const TextStyle(fontSize: 13)),
                  value: fmt,
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const StatusBanner(
          message:
              'Flujos de alta resolución (>720p) o MP3 se unen automáticamente en sandbox con FFmpeg.',
          icon: LucideIcons.shieldCheck,
          color: AppTheme.privacyBadge,
        ),
      ],
    );
  }
}

class YoutubeDownloaderPrimaryActionButton extends ConsumerWidget {
  const YoutubeDownloaderPrimaryActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(youtubeDownloaderNotifierProvider);
    final notifier = ref.read(youtubeDownloaderNotifierProvider.notifier);
    final canDownload =
        !state.isDownloading &&
        (state.videoInfo != null ||
            YoutubeUrlValidator.isValidYoutubeUrl(state.urlInput));

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: canDownload ? notifier.startDownloadAndExport : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.youtubeAccent,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.download, size: 18),
        label: Text(
          state.isDownloading
              ? state.stage.label
              : (state.mode == YoutubeDownloadMode.videoMp4
                  ? 'Descargar Video MP4'
                  : 'Descargar Audio'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
