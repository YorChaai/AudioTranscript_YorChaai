import 'package:flutter_test/flutter_test.dart';
import 'package:audio_convert_app/repositories/transcribe_repository.dart';

void main() {
  group('TranscribeRepository Tests', () {
    test('Initialization', () {
      final repository = TranscribeRepository();
      expect(repository, isNotNull);
    });
  });
}
