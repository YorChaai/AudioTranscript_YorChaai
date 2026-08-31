import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';

/// service untuk cek koneksi ke server secara berkala
class ConnectionService extends ChangeNotifier {
  bool _isConnected = false;
  bool _isChecking = true;
  String? _serverTime;
  Timer? _timer;

  bool get isConnected => _isConnected;
  bool get isChecking => _isChecking;
  String? get serverTime => _serverTime;

  ConnectionService() {
    checkConnection();
    // auto check setiap 10 detik
    _timer = Timer.periodic(
      const Duration(seconds: ApiConfig.healthCheckInterval),
      (_) => checkConnection(),
    );
  }

  bool _disposed = false;

  Future<void> checkConnection() async {
    if (_disposed) return;
    _isChecking = true;
    notifyListeners();

    try {
      final result = await ApiService.healthCheck();
      if (_disposed) return;
      _isConnected = result['status'] == 'ok';
      _serverTime = result['timestamp'];
    } catch (e) {
      if (_disposed) return;
      _isConnected = false;
      _serverTime = null;
    }

    if (!_disposed) {
      _isChecking = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
