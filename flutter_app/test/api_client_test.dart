import 'package:flutter_test/flutter_test.dart';
import 'package:audio_convert_app/services/api_client.dart';
import 'package:audio_convert_app/config/api_config.dart';
import 'package:audio_convert_app/models/job_status.dart';

void main() {
  group('ApiClient Tests', () {
    test('Initialization', () {
      final client = ApiClient();
      expect(client, isNotNull);
      expect(ApiClient.apiKey, 'YORCHAAI_SECRET_KEY');
    });

    test('ApiConfig handles IP with port and without http scheme cleanly', () {
      ApiConfig.setServer('192.168.1.100:5000');
      expect(ApiConfig.baseUrl, 'http://192.168.1.100:5000/api');
      expect(ApiConfig.serverUrl, 'http://192.168.1.100:5000');

      ApiConfig.setServer('http://192.168.1.100:5000/');
      expect(ApiConfig.baseUrl, 'http://192.168.1.100:5000/api');
      expect(ApiConfig.serverUrl, 'http://192.168.1.100:5000');

      ApiConfig.setServer('192.168.1.100', port: 5000);
      expect(ApiConfig.baseUrl, 'http://192.168.1.100:5000/api');
    });

    test('JobStatus correctly parses audio_file and source_file aliases', () {
      final job1 = JobStatus.fromJson({
        'id': 'job1',
        'type': 'transcribe',
        'audio_file': 'audio1.mp3',
        'status': 'completed',
        'progress': 100,
      });
      expect(job1.inputFile, 'audio1.mp3');

      final job2 = JobStatus.fromJson({
        'id': 'job2',
        'type': 'transcribe',
        'source_file': 'source1.mp3',
        'status': 'completed',
        'progress': 100,
      });
      expect(job2.inputFile, 'source1.mp3');
    });
  });
}
