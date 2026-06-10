import 'package:flutter_test/flutter_test.dart';
import 'package:audio_convert_app/services/api_client.dart';

void main() {
  group('ApiClient Tests', () {
    test('Initialization', () {
      final client = ApiClient();
      expect(client, isNotNull);
      expect(ApiClient.apiKey, 'YORCHAAI_SECRET_KEY');
    });
  });
}
