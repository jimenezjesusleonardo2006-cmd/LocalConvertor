import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/media/media_processing_engine.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/youtube_downloader_service.dart';
import '../../domain/youtube_downloader_config.dart';

final youtubeDownloaderServiceProvider =
    Provider.autoDispose<YoutubeDownloaderService>((ref) {
  final engine = ref.watch(mediaProcessingEngineProvider);
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = YoutubeDownloaderService(
    mediaEngine: engine,
    sandboxCleaner: cleaner,
  );
  ref.onDispose(service.cancel);
  return service;
});

class YoutubeDownloaderState {
  final String urlInput;
  final YoutubeVideoInfo? videoInfo;
  final bool isFetchingMetadata;
  final YoutubeDownloadMode mode;
  final YoutubeVideoQualityOption videoQuality;
  final YoutubeAudioFormatOption audioFormat;
  final YoutubeDownloadStage stage;
  final bool isDownloading;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const YoutubeDownloaderState({
    this.urlInput = '',
    this.videoInfo,
    this.isFetchingMetadata = false,
    this.mode = YoutubeDownloadMode.videoMp4,
    this.videoQuality = YoutubeVideoQualityOption.p1080,
    this.audioFormat = YoutubeAudioFormatOption.m4a,
    this.stage = YoutubeDownloadStage.idle,
    this.isDownloading = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  YoutubeDownloaderState copyWith({
    String? urlInput,
    YoutubeVideoInfo? videoInfo,
    bool clearVideoInfo = false,
    bool? isFetchingMetadata,
    YoutubeDownloadMode? mode,
    YoutubeVideoQualityOption? videoQuality,
    YoutubeAudioFormatOption? audioFormat,
    YoutubeDownloadStage? stage,
    bool? isDownloading,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return YoutubeDownloaderState(
      urlInput: urlInput ?? this.urlInput,
      videoInfo: clearVideoInfo ? null : (videoInfo ?? this.videoInfo),
      isFetchingMetadata: isFetchingMetadata ?? this.isFetchingMetadata,
      mode: mode ?? this.mode,
      videoQuality: videoQuality ?? this.videoQuality,
      audioFormat: audioFormat ?? this.audioFormat,
      stage: stage ?? this.stage,
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class YoutubeDownloaderNotifier extends Notifier<YoutubeDownloaderState> {
  StreamSubscription<YoutubeDownloadProgress>? _subscription;
  String? _currentSessionId;

  @override
  YoutubeDownloaderState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupSession();
    });
    return const YoutubeDownloaderState();
  }

  void updateUrl(String url) {
    state = state.copyWith(urlInput: url);
  }

  void updateSettings({
    YoutubeDownloadMode? mode,
    YoutubeVideoQualityOption? videoQuality,
    YoutubeAudioFormatOption? audioFormat,
  }) {
    state = state.copyWith(
      mode: mode,
      videoQuality: videoQuality,
      audioFormat: audioFormat,
    );
  }

  void clear() {
    state = const YoutubeDownloaderState();
  }

  Future<void> fetchVideoMetadata([String? customUrl]) async {
    final targetUrl = (customUrl ?? state.urlInput).trim();
    if (targetUrl.isEmpty || state.isFetchingMetadata || state.isDownloading) {
      return;
    }

    if (!YoutubeUrlValidator.isValidYoutubeUrl(targetUrl)) {
      state = state.copyWith(
        urlInput: targetUrl,
        errorMessage:
            'El enlace no corresponde a un video válido de YouTube.',
      );
      return;
    }

    state = state.copyWith(
      urlInput: targetUrl,
      isFetchingMetadata: true,
      clearVideoInfo: true,
      statusMessage: 'Consultando metadatos directamente desde YouTube...',
    );

    try {
      final service = ref.read(youtubeDownloaderServiceProvider);
      final info = await service.fetchVideoInfo(targetUrl);
      state = state.copyWith(
        videoInfo: info,
        isFetchingMetadata: false,
        statusMessage: 'Video "${info.title}" listo para descargar.',
      );
    } catch (e) {
      state = state.copyWith(
        isFetchingMetadata: false,
        errorMessage: 'No se pudo obtener la información del video: $e',
      );
    }
  }

  Future<void> startDownloadAndExport() async {
    if (state.isDownloading) return;
    if (state.videoInfo == null) {
      await fetchVideoMetadata();
      if (state.videoInfo == null) return;
    }

    final info = state.videoInfo!;
    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(youtubeDownloaderServiceProvider);

    _currentSessionId = 'ytdl_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final safeTitle = info.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final ext = state.mode == YoutubeDownloadMode.videoMp4
        ? 'mp4'
        : state.audioFormat.extension;
    final outFileName =
        '${safeTitle.isEmpty ? info.videoId : safeTitle}.$ext';
    final tempOut = p.join(sessionDir.path, outFileName);

    state = state.copyWith(
      isDownloading: true,
      stage: YoutubeDownloadStage.fetchingStreams,
      progress: 0.03,
      statusMessage: 'Iniciando conexión directa con YouTube...',
    );

    _subscription = service
        .download(
      videoInfo: info,
      sessionDirPath: sessionDir.path,
      outputPath: tempOut,
      mode: state.mode,
      videoQuality: state.videoQuality,
      audioFormat: state.audioFormat,
    )
        .listen((event) async {
      if (event.errorMessage != null) {
        await _cleanupSession();
        state = state.copyWith(
          isDownloading: false,
          stage: YoutubeDownloadStage.idle,
          progress: 0.0,
          errorMessage: event.errorMessage,
        );
        return;
      }

      if (event.isCompleted && event.outputPath != null) {
        try {
          final savedUri = await LocalFileExporter.saveTempFile(
            dialogTitle: 'Guardar descarga de YouTube (LocalConvert)',
            fileName: outFileName,
            sourceFilePath: event.outputPath!,
          );
          state = state.copyWith(
            isDownloading: false,
            stage: YoutubeDownloadStage.completed,
            progress: 1.0,
            statusMessage: savedUri != null
                ? 'Descarga guardada como "$outFileName".'
                : 'Descarga completada (guardado cancelado).',
          );
        } finally {
          await _cleanupSession();
        }
        return;
      }

      state = state.copyWith(
        isDownloading: true,
        stage: event.stage,
        progress: event.progress,
        statusMessage: event.statusMessage,
      );
    });
  }

  void cancelDownload() {
    _subscription?.cancel();
    ref.read(youtubeDownloaderServiceProvider).cancel();
    _cleanupSession();
    state = state.copyWith(
      isDownloading: false,
      stage: YoutubeDownloadStage.idle,
      progress: 0.0,
      statusMessage: 'Descarga cancelada. Segmentos temporales eliminados.',
    );
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final youtubeDownloaderNotifierProvider =
    NotifierProvider<YoutubeDownloaderNotifier, YoutubeDownloaderState>(
  YoutubeDownloaderNotifier.new,
);
