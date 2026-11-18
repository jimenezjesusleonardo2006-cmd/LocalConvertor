import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../../core/media/media_processing_engine.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/video_to_audio_service.dart';
import '../../domain/video_to_audio_config.dart';

final videoToAudioServiceProvider =
    Provider.autoDispose<VideoToAudioService>((ref) {
  final engine = ref.watch(mediaProcessingEngineProvider);
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = VideoToAudioService(
    engine: engine,
    sandboxCleaner: cleaner,
  );
  ref.onDispose(service.cancel);
  return service;
});

class VideoToAudioState {
  final String? selectedVideoPath;
  final int originalSizeBytes;
  final AudioExtractFormat format;
  final bool streamCopyFastMode;
  final AudioBitrateOption bitrate;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const VideoToAudioState({
    this.selectedVideoPath,
    this.originalSizeBytes = 0,
    this.format = AudioExtractFormat.mp3,
    this.streamCopyFastMode = false,
    this.bitrate = AudioBitrateOption.k192,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  VideoToAudioState copyWith({
    String? selectedVideoPath,
    bool clearSelected = false,
    int? originalSizeBytes,
    AudioExtractFormat? format,
    bool? streamCopyFastMode,
    AudioBitrateOption? bitrate,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return VideoToAudioState(
      selectedVideoPath: clearSelected
          ? null
          : (selectedVideoPath ?? this.selectedVideoPath),
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      format: format ?? this.format,
      streamCopyFastMode: streamCopyFastMode ?? this.streamCopyFastMode,
      bitrate: bitrate ?? this.bitrate,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class VideoToAudioNotifier extends Notifier<VideoToAudioState> {
  StreamSubscription<MediaProgressEvent>? _subscription;
  String? _currentSessionId;

  @override
  VideoToAudioState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupSession();
    });
    return const VideoToAudioState();
  }

  Future<void> loadVideoFile(String filePath) async {
    const valid = {'.mp4', '.mkv', '.webm', '.mov', '.avi', '.m4v'};
    if (!valid.contains(p.extension(filePath).toLowerCase())) return;
    final file = File(filePath);
    if (!await file.exists()) return;
    final stat = await file.stat();
    state = state.copyWith(
      selectedVideoPath: filePath,
      originalSizeBytes: stat.size,
      statusMessage:
          'Video "${p.basename(filePath)}" listo para extraer pista de audio.',
    );
  }

  void clear() {
    state = const VideoToAudioState();
  }

  void updateConfig({
    AudioExtractFormat? format,
    bool? streamCopyFastMode,
    AudioBitrateOption? bitrate,
  }) {
    state = state.copyWith(
      format: format,
      streamCopyFastMode: streamCopyFastMode,
      bitrate: bitrate,
    );
  }

  Future<void> extractAndExport() async {
    if (state.selectedVideoPath == null || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(videoToAudioServiceProvider);

    _currentSessionId = 'v2a_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(state.selectedVideoPath!);
    final outName = '${baseName}_audio.${state.format.extension}';
    final tempOut = p.join(sessionDir.path, outName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Extrayendo pista de audio en local...',
    );

    _subscription = service
        .extractAudio(
      VideoToAudioConfig(
        inputVideoPath: state.selectedVideoPath!,
        outputAudioPath: tempOut,
        sessionDirPath: sessionDir.path,
        format: state.format,
        streamCopyFastMode: state.streamCopyFastMode,
        bitrate: state.bitrate,
      ),
    )
        .listen((event) async {
      if (event.errorMessage != null) {
        await _cleanupSession();
        state = state.copyWith(
          isProcessing: false,
          progress: 0.0,
          errorMessage: event.errorMessage,
        );
        return;
      }

      if (event.isCompleted && event.outputPath != null) {
        try {
          final uri = await LocalFileExporter.saveTempFile(
            dialogTitle: 'Guardar pista de audio extraída (LocalConvert)',
            fileName: outName,
            sourceFilePath: event.outputPath!,
          );
          state = state.copyWith(
            isProcessing: false,
            progress: 1.0,
            statusMessage: uri != null
                ? 'Audio extraído y guardado como "$outName".'
                : 'Guardado cancelado.',
          );
        } finally {
          await _cleanupSession();
        }
        return;
      }

      state = state.copyWith(
        isProcessing: true,
        progress: event.progress,
        statusMessage: event.statusMessage,
      );
    });
  }

  void cancelExtraction() {
    _subscription?.cancel();
    ref.read(videoToAudioServiceProvider).cancel();
    _cleanupSession();
    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Extracción cancelada. Sandbox limpio.',
    );
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final videoToAudioNotifierProvider =
    NotifierProvider<VideoToAudioNotifier, VideoToAudioState>(
  VideoToAudioNotifier.new,
);
