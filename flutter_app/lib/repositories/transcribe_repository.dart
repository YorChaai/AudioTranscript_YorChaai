import 'dart:io';
import '../services/api_service.dart';

/// The Data Layer (Repository Pattern) for Transcribe features.
class TranscribeRepository {
  TranscribeRepository();

  Future<Map<String, dynamic>> listAudio({String path = ''}) async {
    return await ApiService.listAudio(path: path);
  }

  Future<Map<String, dynamic>> uploadAudio(File file, {String path = '', void Function(int bytes, int totalBytes)? onProgress}) async {
    return await ApiService.uploadAudio(file, path: path, onProgress: onProgress);
  }

  Future<Map<String, dynamic>> uploadVideoAndConvert(File file, {String path = '', void Function(int bytes, int totalBytes)? onProgress}) async {
    return await ApiService.uploadVideoAndConvertToMp3(file, path: path, onProgress: onProgress);
  }

  Future<Map<String, dynamic>> createFolder(String name, {String path = ''}) async {
    return await ApiService.createFolder(name, path: path);
  }

  Future<Map<String, dynamic>> moveFiles(List<String> files, String targetPath) async {
    return await ApiService.moveFiles(files, targetPath);
  }

  Future<Map<String, dynamic>> startTranscribe({
    required List<String> files,
    required String language,
    required bool doTranslate,
    required String targetLang,
  }) async {
    return await ApiService.startTranscribe(
      audioFiles: files,
      language: language,
      translate: doTranslate,
      targetLang: targetLang,
    );
  }

  Stream<Map<String, dynamic>> streamJobStatus(String jobId) {
    return ApiService.streamJobStatus(jobId);
  }

  Future<Map<String, dynamic>> cancelTranscribe(String jobId) async {
    return await ApiService.cancelTranscribe(jobId);
  }
}
