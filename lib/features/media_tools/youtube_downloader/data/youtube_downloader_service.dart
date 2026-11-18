import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/media/ffmpeg_cli_builder.dart';
import '../../../../core/media/media_processing_engine.dart';
import '../../../../core/sandbox/sandbox_cleaner_service.dart';
import '../domain/youtube_downloader_config.dart';

/// Servicio directo cliente -> YouTube (sin intermediarios ni telemetría)
/// con unión automática en sandbox local mediante [MediaProcessingEngine].
class YoutubeDownloaderService {
  final MediaProcessingEngine _mediaEngine;
  final SandboxCleanerService _sandboxCleaner;
  bool _isCancelled = false;

  YoutubeDownloaderService({
    required MediaProcessingEngine mediaEngine,
    required SandboxCleanerService sandboxCleaner,
  })  : _mediaEngine = mediaEngine,
        _sandboxCleaner = sandboxCleaner;

  Future<YoutubeVideoInfo> fetchVideoInfo(String urlOrId) async {
    final videoId = YoutubeUrlValidator.extractVideoId(urlOrId);
    if (videoId == null) {
      throw const FormatException(
        'Enlace de YouTube no válido. Usa un enlace watch?v=, youtu.be/ o shorts/.',
      );
    }

    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoId);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final heights = <int>{
        for (final s in manifest.video) s.videoResolution.height,
      }.toList()
        ..sort((a, b) => b.compareTo(a));

      return YoutubeVideoInfo(
        videoId: video.id.value,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
        availableHeights: heights.isEmpty ? const [720, 360] : heights,
      );
    } finally {
      yt.close();
    }
  }

  Stream<YoutubeDownloadProgress> download({
    required YoutubeVideoInfo videoInfo,
    required String sessionDirPath,
    required String outputPath,
    required YoutubeDownloadMode mode,
    required YoutubeVideoQualityOption videoQuality,
    required YoutubeAudioFormatOption audioFormat,
  }) async* {
    _isCancelled = false;
    final yt = YoutubeExplode();

    try {
      yield const YoutubeDownloadProgress(
        stage: YoutubeDownloadStage.fetchingStreams,
        progress: 0.04,
        statusMessage: 'Obteniendo flujos directos desde YouTube...',
      );

      final manifest = await yt.videos.streamsClient.getManifest(
        videoInfo.videoId,
      );

      if (_isCancelled) {
        await _sandboxCleaner.deleteSessionDir(sessionDirPath);
        return;
      }

      if (mode == YoutubeDownloadMode.audioOnly) {
        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        final rawAudioPath = p.join(sessionDirPath, 'yt_raw_audio.m4a');

        await for (final dlPct in _downloadStreamToFile(
          yt,
          audioStreamInfo,
          rawAudioPath,
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(sessionDirPath);
            return;
          }
          yield YoutubeDownloadProgress(
            stage: YoutubeDownloadStage.downloading,
            progress: (dlPct * 0.72).clamp(0.05, 0.72),
            statusMessage:
                'Descargando pista de audio (${(dlPct * 100).round()}%)...',
          );
        }

        final ffmpegReady = await _mediaEngine.isAvailable();
        if (audioFormat == YoutubeAudioFormatOption.mp3 || ffmpegReady) {
          yield YoutubeDownloadProgress(
            stage: YoutubeDownloadStage.assembling,
            progress: 0.78,
            statusMessage:
                'Convirtiendo a .${audioFormat.extension.toUpperCase()} e incrustando metadatos...',
          );

          final targetFmt = audioFormat == YoutubeAudioFormatOption.mp3
              ? AudioOutputFormat.mp3
              : AudioOutputFormat.m4a;
          final args = FfmpegCliBuilder.buildAudioConversionArgs(
            inputPath: rawAudioPath,
            outputPath: outputPath,
            format: targetFmt,
            bitrate: AudioBitrateOption.k192,
            sampleRate: AudioSampleRateOption.hz44100,
            metadata: {
              'title': videoInfo.title,
              'artist': videoInfo.author,
            },
          );

          String? ffmpegErr;
          await for (final ev in _mediaEngine.executeCommand(
            arguments: args,
            outputPath: outputPath,
            knownDuration: videoInfo.duration,
            statusPrefix: 'Empaquetando audio',
          )) {
            if (_isCancelled) {
              await _sandboxCleaner.deleteSessionDir(sessionDirPath);
              return;
            }
            if (ev.errorMessage != null) {
              ffmpegErr = ev.errorMessage;
              break;
            }
            yield YoutubeDownloadProgress(
              stage: YoutubeDownloadStage.assembling,
              progress: (0.75 + ev.progress * 0.24).clamp(0.75, 0.99),
              statusMessage: ev.statusMessage,
            );
          }

          if (ffmpegErr != null &&
              audioFormat == YoutubeAudioFormatOption.m4a) {
            await File(rawAudioPath).copy(outputPath);
          } else if (ffmpegErr != null) {
            throw Exception(ffmpegErr);
          }
        } else {
          await File(rawAudioPath).copy(outputPath);
        }

        yield YoutubeDownloadProgress(
          stage: YoutubeDownloadStage.completed,
          progress: 1.0,
          statusMessage: 'Audio descargado y ensamblado con éxito.',
          isCompleted: true,
          outputPath: outputPath,
        );
        return;
      }

      final ffmpegAvailable = await _mediaEngine.isAvailable();
      final matchingMuxed = manifest.muxed
          .where((s) => s.videoResolution.height <= videoQuality.height)
          .toList()
        ..sort(
          (a, b) =>
              b.videoResolution.height.compareTo(a.videoResolution.height),
        );

      final matchingVideoOnly = manifest.videoOnly
          .where(
            (s) =>
                s.container.name.toLowerCase() == 'mp4' &&
                s.videoResolution.height <= videoQuality.height,
          )
          .toList()
        ..sort(
          (a, b) =>
              b.videoResolution.height.compareTo(a.videoResolution.height),
        );

      final bestMuxedHeight = matchingMuxed.isNotEmpty
          ? matchingMuxed.first.videoResolution.height
          : 0;
      final bestAdaptiveHeight = matchingVideoOnly.isNotEmpty
          ? matchingVideoOnly.first.videoResolution.height
          : 0;

      if (ffmpegAvailable &&
          matchingVideoOnly.isNotEmpty &&
          bestAdaptiveHeight > bestMuxedHeight) {
        final chosenVideo = matchingVideoOnly.first;
        final chosenAudio = manifest.audioOnly.withHighestBitrate();
        final tempVideoPath = p.join(sessionDirPath, 'yt_video_only.mp4');
        final tempAudioPath = p.join(sessionDirPath, 'yt_audio_only.m4a');

        await for (final dlPct in _downloadStreamToFile(
          yt,
          chosenVideo,
          tempVideoPath,
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(sessionDirPath);
            return;
          }
          yield YoutubeDownloadProgress(
            stage: YoutubeDownloadStage.downloading,
            progress: (dlPct * 0.55).clamp(0.05, 0.55),
            statusMessage:
                'Descargando video ${chosenVideo.videoResolution.height}p (${(dlPct * 100).round()}%)...',
          );
        }

        await for (final dlPct in _downloadStreamToFile(
          yt,
          chosenAudio,
          tempAudioPath,
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(sessionDirPath);
            return;
          }
          yield YoutubeDownloadProgress(
            stage: YoutubeDownloadStage.downloading,
            progress: (0.55 + dlPct * 0.20).clamp(0.55, 0.75),
            statusMessage:
                'Descargando pista de audio (${(dlPct * 100).round()}%)...',
          );
        }

        yield const YoutubeDownloadProgress(
          stage: YoutubeDownloadStage.assembling,
          progress: 0.78,
          statusMessage:
              'Uniendo pistas de video y audio en Sandbox local (-c:v copy)...',
        );

        final muxArgs = FfmpegCliBuilder.buildMuxVideoAndAudioArgs(
          videoPath: tempVideoPath,
          audioPath: tempAudioPath,
          outputPath: outputPath,
        );

        String? muxError;
        await for (final ev in _mediaEngine.executeCommand(
          arguments: muxArgs,
          outputPath: outputPath,
          knownDuration: videoInfo.duration,
          statusPrefix: 'Ensamblando MP4',
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(sessionDirPath);
            return;
          }
          if (ev.errorMessage != null) {
            muxError = ev.errorMessage;
            break;
          }
          yield YoutubeDownloadProgress(
            stage: YoutubeDownloadStage.assembling,
            progress: (0.78 + ev.progress * 0.21).clamp(0.78, 0.99),
            statusMessage: ev.statusMessage,
          );
        }

        if (muxError != null) {
          throw Exception(muxError);
        }
      } else {
        final chosenMuxed = matchingMuxed.isNotEmpty
            ? matchingMuxed.first
            : manifest.muxed.withHighestBitrate();

        await for (final dlPct in _downloadStreamToFile(
          yt,
          chosenMuxed,
          outputPath,
        )) {
          if (_isCancelled) {
            await _sandboxCleaner.deleteSessionDir(sessionDirPath);
            return;
          }
          yield YoutubeDownloadProgress(
            stage: YoutubeDownloadStage.downloading,
            progress: (dlPct * 0.98).clamp(0.05, 0.98),
            statusMessage:
                'Descargando MP4 ${chosenMuxed.videoResolution.height}p (${(dlPct * 100).round()}%)...',
          );
        }
      }

      yield YoutubeDownloadProgress(
        stage: YoutubeDownloadStage.completed,
        progress: 1.0,
        statusMessage: 'Video descargado y listo para guardar.',
        isCompleted: true,
        outputPath: outputPath,
      );
    } catch (e) {
      await _sandboxCleaner.deleteSessionDir(sessionDirPath);
      yield YoutubeDownloadProgress(
        stage: YoutubeDownloadStage.idle,
        progress: 0.0,
        statusMessage: 'Error durante la descarga desde YouTube.',
        errorMessage: e.toString(),
      );
    } finally {
      yt.close();
    }
  }

  Stream<double> _downloadStreamToFile(
    YoutubeExplode yt,
    StreamInfo streamInfo,
    String targetPath,
  ) async* {
    final totalBytes = streamInfo.size.totalBytes;
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    int received = 0;

    try {
      await for (final chunk in yt.videos.streamsClient.get(streamInfo)) {
        if (_isCancelled) break;
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          yield (received / totalBytes).clamp(0.0, 1.0);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> cancel() async {
    _isCancelled = true;
    await _mediaEngine.cancelCurrent();
  }
}
