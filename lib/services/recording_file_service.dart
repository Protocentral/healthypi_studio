import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/recording_models.dart';
import 'biosignal_file_reader.dart';

/// Metadata for a recording file
class RecordingFileInfo {
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int fileSize;
  final RecordingMetadata? metadata;
  final Duration? duration;
  final int? totalSamples;
  final List<String> channels;

  const RecordingFileInfo({
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.fileSize,
    this.metadata,
    this.duration,
    this.totalSamples,
    this.channels = const [],
  });

  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get durationFormatted {
    if (duration == null) return 'Unknown';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

/// Service for managing recording files
class RecordingFileService extends ChangeNotifier {
  List<RecordingFileInfo> _recordings = [];
  bool _isLoading = false;
  String? _error;

  List<RecordingFileInfo> get recordings => _recordings;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasRecordings => _recordings.isNotEmpty;

  int get totalRecordings => _recordings.length;

  int get totalSizeBytes => _recordings.fold(
    0,
    (sum, recording) => sum + recording.fileSize,
  );

  Duration get totalDuration => _recordings.fold(
    Duration.zero,
    (sum, recording) => sum + (recording.duration ?? Duration.zero),
  );

  /// Get the recordings directory path
  Future<Directory> getRecordingsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return Directory(path.join(directory.path, 'HealthyPi_Recordings'));
  }

  /// Load all recording files
  Future<void> loadRecordings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final recordingsDir = await getRecordingsDirectory();

      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
        _recordings = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final files = await recordingsDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.hpd'))
          .cast<File>()
          .toList();

      final List<RecordingFileInfo> loadedRecordings = [];

      for (final file in files) {
        try {
          final stat = await file.stat();
          final fileName = path.basename(file.path);

          // Try to read metadata from file
          RecordingMetadata? metadata;
          Duration? duration;
          int? totalSamples;
          List<String> channels = [];

          try {
            final reader = BiosignalFileReader(file);
            await reader.open();
            metadata = await reader.readHeader();
            await reader.close();

            duration = metadata.recordingDuration;
            totalSamples = metadata.totalSamples;
            channels = metadata.channels.map((c) => c.name).toList();
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Could not read metadata from $fileName: $e');
            }
          }

          loadedRecordings.add(RecordingFileInfo(
            fileName: fileName,
            filePath: file.path,
            createdAt: stat.modified,
            fileSize: stat.size,
            metadata: metadata,
            duration: duration,
            totalSamples: totalSamples,
            channels: channels,
          ));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Error loading file ${file.path}: $e');
          }
        }
      }

      // Sort by creation date (newest first)
      loadedRecordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _recordings = loadedRecordings;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load recordings: $e';
      _isLoading = false;
      _recordings = [];
      notifyListeners();
      if (kDebugMode) {
        debugPrint('❌ Error loading recordings: $e');
      }
    }
  }

  /// Delete a recording file
  Future<void> deleteRecording(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        _recordings.removeWhere((r) => r.filePath == filePath);
        notifyListeners();
        if (kDebugMode) {
          debugPrint('✅ Deleted recording: $filePath');
        }
      }
    } catch (e) {
      _error = 'Failed to delete recording: $e';
      notifyListeners();
      if (kDebugMode) {
        debugPrint('❌ Error deleting recording: $e');
      }
      rethrow;
    }
  }

  /// Search recordings by name
  List<RecordingFileInfo> searchRecordings(String query) {
    if (query.isEmpty) return _recordings;

    final lowerQuery = query.toLowerCase();
    return _recordings.where((recording) {
      return recording.fileName.toLowerCase().contains(lowerQuery) ||
          recording.channels.any((c) => c.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
