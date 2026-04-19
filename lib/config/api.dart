import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KioskApi {
  static const storage = FlutterSecureStorage();
  static String? _baseUrl;
  static String? _apiKey;

  static Future<void> loadConfig() async {
    _baseUrl = await storage.read(key: 'kiosk_base_url');
    _apiKey = await storage.read(key: 'kiosk_api_key');
  }

  static Future<void> saveConfig(String baseUrl, String apiKey) async {
    var url = baseUrl.trimRight();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    _baseUrl = url;
    _apiKey = apiKey;
    await storage.write(key: 'kiosk_base_url', value: url);
    await storage.write(key: 'kiosk_api_key', value: apiKey);
  }

  static bool get isConfigured => _baseUrl != null && _apiKey != null;
  static String? get baseUrl => _baseUrl;

  static Dio createDio() {
    return Dio(BaseOptions(
      baseUrl: '${_baseUrl ?? ""}/api/kiosk',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Kiosk-Key': _apiKey ?? '',
      },
    ))
      ..interceptors.add(kDebugMode
          ? LogInterceptor(requestBody: true, responseBody: true, logPrint: (o) => debugPrint(o.toString()))
          : Interceptor());
  }
}
