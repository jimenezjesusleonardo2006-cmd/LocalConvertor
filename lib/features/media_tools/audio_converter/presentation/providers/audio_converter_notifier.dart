import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../../core/media/media_processing_engine.dart';
import '../../../../../core/utils/local_file_exporter.dart';
import '../../../../pdf_tools/images_to_pdf/presentation/providers/image_to_pdf_notifier.dart';
import '../../data/audio_converter_service.dart';
import '../../domain/audio_converter_config.dart';

final audioConverterServiceProvider =
    Provider.autoDispose<AudioConverterService>((ref) {
  final engine = ref.watch(mediaProcessingEngineProvider);
  final cleaner = ref.watch(sandboxCleanerProvider);
  final service = AudioConverterService(
    engine: engine,
    sandboxCleaner: cleaner,
  );
  ref.onDispose(service.cancel);
  return service;
});

class AudioConverterState {
  final List<AudioBatchItem> files;
  final AudioOutputFormat targetFormat;
  final AudioBitrateOption bitrate;
  final AudioSampleRateOption sampleRate;
  final bool packageAsZip;
  final bool isProcessing;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;

  const AudioConverterState({
    this.files = const [],
    this.targetFormat = AudioOutputFormat.mp3,
    this.bitrate = AudioBitrateOption.k192,
    this.sampleRate = AudioSampleRateOption.hz44100,
    this.packageAsZip = false,
    this.isProcessing = false,
    this.progress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  AudioConverterState copyWith({
    List<AudioBatchItem>? files,
    AudioOutputFormat? targetFormat,
    AudioBitrateOption? bitrate,
    AudioSampleRateOption? sampleRate,
    bool? packageAsZip,
    bool? isProcessing,
    double? progress,
    String? statusMessage,
    String? errorMessage,
  }) {
    return AudioConverterState(
      files: files ?? this.files,
      targetFormat: targetFormat ?? this.targetFormat,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      packageAsZip: packageAsZip ?? this.packageAsZip,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class AudioConverterNotifier extends Notifier<AudioConverterState> {
  StreamSubscription<MediaProgressEvent>? _subscription;
  String? _currentSessionId;

  @override
  AudioConverterState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _cleanupSession();
    });
    return const AudioConverterState();
  }

  Future<void> addAudioFiles(List<String> paths) async {
    const allowed = {
      '.mp3',
      '.wav',
      '.m4a',
      '.ogg',
      '.flac',
      '.opus',
      '.aac',
      '.wma',
    };
    final added = <AudioBatchItem>[];

    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      if (!allowed.contains(ext)) continue;
      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        added.add(
          AudioBatchItem(
            path: path,
            fileName: p.basename(path),
            sizeBytes: stat.size,
            sourceExtension: ext.replaceFirst('.', '').toUpperCase(),
          ),
        );
      }
    }

    if (added.isNotEmpty) {
      state = state.copyWith(
        files: [...state.files, ...added],
        statusMessage:
            '${state.files.length + added.length} archivo(s) de audio listos.',
      );
    }
  }

  void removeFileAt(int index) {
    final updated = List<AudioBatchItem>.from(state.files)..removeAt(index);
    state = state.copyWith(files: updated);
  }

  void clearAll() {
    state = state.copyWith(files: const []);
  }

  void updateConfig({
    AudioOutputFormat? targetFormat,
    AudioBitrateOption? bitrate,
    AudioSampleRateOption? sampleRate,
    bool? packageAsZip,
  }) {
    state = state.copyWith(
      targetFormat: targetFormat,
      bitrate: bitrate,
      sampleRate: sampleRate,
      packageAsZip: packageAsZip,
    );
  }

  Future<void> convertAndExport() async {
    if (state.files.isEmpty || state.isProcessing) return;

    final cleaner = ref.read(sandboxCleanerProvider);
    final service = ref.read(audioConverterServiceProvider);

    _currentSessionId = 'audio_${DateTime.now().millisecondsSinceEpoch}';
    final sessionDir = await cleaner.createSessionDir(_currentSessionId!);

    state = state.copyWith(
      isProcessing: true,
      progress: 0.02,
      statusMessage: 'Iniciando lote de audio local...',
    );

    _subscription = service
        .convertBatch(
      AudioConverterBatchConfig(
        inputPaths: state.files.map((e) => e.path).toList(),
        sessionDirPath: sessionDir.path,
        targetFormat: state.targetFormat,
        bitrate: state.bitrate,
        sampleRate: state.sampleRate,
        packageAsZip: state.packageAsZip || state.files.length > 1,
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

      if (event.isCompleted) {
        await _exportResult(event);
        return;
      }

      state = state.copyWith(
        isProcessing: true,
        progress: event.progress,
        statusMessage: event.statusMessage,
      );
    });
  }

  Future<void> _exportResult(MediaProgressEvent event) async {
    try {
      final pathToSave = event.zipFilePath ?? event.outputPath;
      if (pathToSave == null) return;
      final fileName = p.basename(pathToSave);
      final uri = await LocalFileExporter.saveTempFile(
        dialogTitle: 'Guardar audio convertido (LocalConvert)',
        fileName: fileName,
        sourceFilePath: pathToSave,
      );
      state = state.copyWith(
        isProcessing: false,
        progress: 1.0,
        statusMessage: uri != null
            ? 'Exportado "$fileName" correctamente.'
            : 'Exportación cancelada.',
      );
    } finally {
      await _cleanupSession();
    }
  }

  void cancelConversion() {
    _subscription?.cancel();
    ref.read(audioConverterServiceProvider).cancel();
    _cleanupSession();
    state = state.copyWith(
      isProcessing: false,
      progress: 0.0,
      statusMessage: 'Conversión de audio cancelada. Sandbox limpio.',
    );
  }

  Future<void> _cleanupSession() async {
    if (_currentSessionId != null) {
      await ref.read(sandboxCleanerProvider).purgeSession(_currentSessionId!);
      _currentSessionId = null;
    }
  }
}

final audioConverterNotifierProvider =
    NotifierProvider<AudioConverterNotifier, AudioConverterState>(
  AudioConverterNotifier.new,
);
