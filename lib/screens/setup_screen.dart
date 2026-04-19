import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../config/api.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _testing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    await KioskApi.loadConfig();
    if (KioskApi.baseUrl != null) _urlCtrl.text = KioskApi.baseUrl!;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (_urlCtrl.text.isEmpty || _keyCtrl.text.isEmpty) return;
    setState(() { _testing = true; _status = null; });

    try {
      var url = _urlCtrl.text.trim();
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        headers: {'Accept': 'application/json', 'X-Kiosk-Key': _keyCtrl.text.trim()},
      ));
      await dio.get('$url/api/kiosk/lookup', queryParameters: {'code': 'TEST'});
      setState(() => _status = 'connected');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        setState(() => _status = 'connected'); // 404 = employee not found, but server is reachable
      } else if (e.response?.statusCode == 401) {
        setState(() => _status = 'invalid_key');
      } else {
        setState(() => _status = 'failed');
      }
    } catch (_) {
      setState(() => _status = 'failed');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (_urlCtrl.text.isEmpty || _keyCtrl.text.isEmpty) return;
    await KioskApi.saveConfig(_urlCtrl.text.trim(), _keyCtrl.text.trim());
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/kiosk');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0078D4), Color(0xFF00BCF2)]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: const Center(child: Text('C', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Color(0xFF009EF7)))),
                  ),
                  const SizedBox(height: 16),
                  const Text('Kiosk Setup', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('Configure this device to connect to Charlie HRMS', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      children: [
                        TextField(
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'https://hrms.yourcompany.com',
                            prefixIcon: Icon(Icons.dns_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _keyCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Kiosk API Key',
                            hintText: 'kiosk_abc123...',
                            prefixIcon: Icon(Icons.key),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _testing ? null : _testConnection,
                            icon: _testing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_find),
                            label: const Text('Test Connection'),
                          ),
                        ),

                        if (_status != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _status == 'connected' ? Icons.check_circle : (_status == 'invalid_key' ? Icons.key_off : Icons.error),
                                color: _status == 'connected' ? Colors.green : Colors.red, size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _status == 'connected' ? 'Connected!' : (_status == 'invalid_key' ? 'Invalid API key' : 'Cannot reach server'),
                                style: TextStyle(color: _status == 'connected' ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF009EF7), foregroundColor: Colors.white),
                            child: const Text('Save & Start Kiosk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
