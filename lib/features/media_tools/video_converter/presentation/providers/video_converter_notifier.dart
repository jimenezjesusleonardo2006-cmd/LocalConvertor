import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../../core/media/ffmpeg_progress_parser.dart';
import '../../../../../core/media/media_processing_engine.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/video_converter_service.dart';
import '../../domain/video_converter_config.dart';

final videoConverterServiceProvider =
    Provider.autoDispose<VideoConverterService>((ref) {
  final engine = ref.watch(mediaProcessingEngineProvider);
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = VideoConverterService(
    engine: engine,
    sandboxCleaner: cleaner,
  );
  ref.onDispose(service.cancel);
  return service;
});

class VideoConverterState {
  final String? selectedVideoPath;
  final int originalSizeBytes;
  final VideoOutputFormat format;
  final VideoResolutionPreset resolution;
  final VideoCrfPreset crfPreset;
  final bool muteAudio;
  final String trimStartText;
  final String trimEndText;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const VideoConverterState({
    this.selectedVideoPath,
    this.originalSizeBytes = 0,
    this.format = VideoOutputFormat.mp4,
    this.resolution = VideoResolutionPreset.original,
    this.crfPreset = VideoCrfPreset.balanced,
    this.muteAudio = false,
    this.trimStartText = '',
    this.trimEndText = '',
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  VideoConverterState copyWith({
    String? selectedVideoPath,
    bool clearSelected = false,
    int? originalSizeBytes,
    VideoOutputFormat? format,
    VideoResolutionPreset? resolution,
    VideoCrfPreset? crfPreset,
    bool? muteAudio,
    String? trimStartText,
    String? trimEndText,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return VideoConverterState(
      selectedVideoPath: clearSelected
          ? null
          : (selectedVideoPath ?? this.selectedVideoPath),
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      format: format ?? this.format,
      resolution: resolution ?? this.resolution,
      crfPreset: crfPreset ?? this.crfPreset,
      muteAudio: muteAudio ?? this.muteAudio,
      trimStartText: trimStartText ?? this.trimStartText,
      trimEndText: trimEndText ?? this.trimEndText,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class VideoConverterNotifier extends Notifier<VideoConverterState> {
  StreamSubscription<MediaProgressEvent>? _subscription;
  String? _currentSessionId;

  @override
  VideoConverterState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupSession();
    });
    return const VideoConverterState();
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
      statusMessage: 'Video "${p.basename(filePath)}" listo para convertir.',
    );
  }

  void clear() {
    state = const VideoConverterState();
  }

  void updateConfig({
    VideoOutputFormat? format,
    VideoResolutionPreset? resolution,
    VideoCrfPreset? crfPreset,
    bool? muteAudio,
    String? trimStartText,
    String? trimEndText,
  }) {
    state = state.copyWith(
      format: format,
      resolution: resolution,
      crfPreset: crfPreset,
      muteAudio: muteAudio,
      trimStartText: trimStartText,
      trimEndText: trimEndText,
    );
  }

  Future<void> convertAndExport() async {
    if (state.selectedVideoPath == null || state.isProcessing) return;

    final startDur = FfmpegProgressParser.parseUserTimestamp(state.trimStartText);
    final endDur = FfmpegProgressParser.parseUserTimestamp(state.trimEndText);
    if (state.trimStartText.trim().isNotEmpty && startDur == null) {
      state = state.copyWith(
        errorMessage: 'Formato de inicio Trim inválido. Usa MM:SS o HH:MM:SS.',
      );
      return;
    }
    if (state.trimEndText.trim().isNotEmpty && endDur == null) {
      state = state.copyWith(
        errorMessage: 'Formato de fin Trim inválido. Usa MM:SS o HH:MM:SS.',
      );
      return;
    }

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(videoConverterServiceProvider);

    _currentSessionId = 'video_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);
    final baseName = p.basenameWithoutExtension(state.selectedVideoPath!);
    final outName = '${baseName}_convertido.${state.format.extension}';
    final tempOut = p.join(sessionDir.path, outName);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando transcodificación local de video...',
    );

    _subscription = service
        .convertVideo(
      VideoConverterConfig(
        inputPath: state.selectedVideoPath!,
        outputPath: tempOut,
        sessionDirPath: sessionDir.path,
        format: state.format,
        resolution: state.resolution,
        crfPreset: state.crfPreset,
        muteAudio: state.muteAudio,
        trimStart: startDur,
        trimEnd: endDur,
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
            dialogTitle: 'Guardar video convertido (LocalConvert)',
            fileName: outName,
            sourceFilePath: event.outputPath!,
          );
          state = state.copyWith(
            isProcessing: false,
            progress: 1.0,
            statusMessage: uri != null
                ? 'Video guardado como "$outName".'
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

  void cancelConversion() {
    _subscription?.cancel();
    ref.read(videoConverterServiceProvider).cancel();
    _cleanupSession();
    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Transcodificación cancelada. Sandbox limpio.',
    );
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final videoConverterNotifierProvider =
    NotifierProvider<VideoConverterNotifier, VideoConverterState>(
  VideoConverterNotifier.new,
);
