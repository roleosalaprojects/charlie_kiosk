import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/api.dart';

enum KioskState { idle, loading, confirm, success, error }

class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final Dio _dio = KioskApi.createDio();

  KioskState _state = KioskState.idle;
  String _message = '';
  String _employeeName = '';
  String? _photoUrl;
  String _statusDetail = '';
  String? _pendingAction;
  String? _pendingEndpoint;
  String? _pendingCode;
  Timer? _resetTimer;
  Timer? _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _updateClock() {
    setState(() => _currentTime = DateFormat('hh:mm:ss a').format(DateTime.now()));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    _resetTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _onSubmit(String code) async {
    code = code.trim();
    if (code.isEmpty) return;
    _inputCtrl.clear();

    // If confirming, cancel and look up new scan
    _resetPending();

    setState(() { _state = KioskState.loading; _message = 'Looking up...'; });

    try {
      final lookupRes = await _dio.get('/lookup', queryParameters: {'code': code});
      final emp = lookupRes.data['employee'];
      final today = lookupRes.data['today'];

      _employeeName = emp['name'] ?? '';
      _photoUrl = emp['photo_url'];

      // Determine next action
      String action;
      String endpoint;
      if (today == null || today['clock_in'] == null) {
        action = 'Clock In';
        endpoint = '/clock-in';
      } else if (today['break_start'] == null) {
        action = 'Break Out';
        endpoint = '/break-out';
      } else if (today['break_end'] == null) {
        action = 'Break In';
        endpoint = '/break-in';
      } else if (today['clock_out'] == null) {
        action = 'Clock Out';
        endpoint = '/clock-out';
      } else {
        setState(() {
          _state = KioskState.success;
          _message = 'Day Complete';
          _statusDetail = 'In: ${today['clock_in']} | Out: ${today['clock_out']}';
        });
        _scheduleReset();
        return;
      }

      // Show confirmation — don't execute yet
      _pendingAction = action;
      _pendingEndpoint = endpoint;
      _pendingCode = code;

      setState(() {
        _state = KioskState.confirm;
        _message = action;
        _statusDetail = today != null && today['clock_in'] != null ? 'In: ${today['clock_in']}' : '';
      });

      // Auto-cancel after 10 seconds if not confirmed
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 10), _resetToIdle);

    } on DioException catch (e) {
      setState(() {
        _state = KioskState.error;
        _message = e.response?.data?['message'] ?? 'Something went wrong';
        _employeeName = '';
        _photoUrl = null;
      });
      _scheduleReset();
    }
  }

  Future<void> _executeAction() async {
    setState(() { _state = KioskState.loading; _message = 'Recording...'; });

    try {
      final res = await _dio.post(_pendingEndpoint!, data: {'code': _pendingCode});

      setState(() {
        _state = KioskState.success;
        _message = res.data['message'] ?? '${_pendingAction} recorded';
        _statusDetail = res.data['tardiness'] ?? res.data['hours_worked'] ?? '';
      });
    } on DioException catch (e) {
      setState(() {
        _state = KioskState.error;
        _message = e.response?.data?['message'] ?? 'Failed';
      });
    }

    _resetPending();
    _scheduleReset();
  }

  void _resetPending() {
    _pendingAction = null;
    _pendingEndpoint = null;
    _pendingCode = null;
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'Clock In': return Icons.login;
      case 'Break Out': return Icons.free_breakfast;
      case 'Break In': return Icons.keyboard_return;
      case 'Clock Out': return Icons.logout;
      default: return Icons.access_time;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'Clock In': return const Color(0xFF50CD89);
      case 'Break Out': return const Color(0xFFFFC700);
      case 'Break In': return const Color(0xFF009EF7);
      case 'Clock Out': return const Color(0xFFF1416C);
      default: return const Color(0xFF009EF7);
    }
  }

  void _resetToIdle() {
    _resetPending();
    _focusNode.requestFocus();
    setState(() {
      _state = KioskState.idle;
      _message = '';
      _employeeName = '';
      _photoUrl = null;
      _statusDetail = '';
    });
    _focusNode.requestFocus();
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 5), () {
      setState(() {
        _state = KioskState.idle;
        _message = '';
        _employeeName = '';
        _photoUrl = null;
        _statusDetail = '';
      });
      _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF1a1a2e), Color(0xFF16213e)]),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.business, color: Color(0xFF009EF7), size: 28),
                          SizedBox(width: 10),
                          Text('Charlie HRMS', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_currentTime, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300)),
                          Text(DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Main content
                Expanded(
                  child: Center(
                    child: _buildContent(),
                  ),
                ),

                // Input bar
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _focusNode,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: 'Scan barcode or enter employee number...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      prefixIcon: Icon(Icons.qr_code_scanner, color: Colors.white.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF009EF7), width: 2)),
                    ),
                    onSubmitted: _onSubmit,
                  ),
                ),

                // Settings link
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextButton.icon(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/setup'),
                    icon: Icon(Icons.settings, size: 14, color: Colors.white.withValues(alpha: 0.3)),
                    label: Text('Settings', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case KioskState.idle:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint, size: 120, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            Text('Scan your ID or enter employee number', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 18)),
          ],
        );

      case KioskState.loading:
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 60, height: 60, child: CircularProgressIndicator(color: Color(0xFF009EF7), strokeWidth: 3)),
            SizedBox(height: 20),
            Text('Processing...', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        );

      case KioskState.confirm:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_photoUrl != null && _photoUrl!.isNotEmpty)
              CircleAvatar(radius: 50, backgroundImage: CachedNetworkImageProvider(_photoUrl!))
            else
              CircleAvatar(radius: 50, backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.person, size: 50, color: Colors.white)),
            const SizedBox(height: 16),
            Text(_employeeName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
            if (_statusDetail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_statusDetail, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _executeAction,
                icon: Icon(_actionIcon(_message), size: 22),
                label: Text(_message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _actionColor(_message),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _resetToIdle,
              child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
            ),
          ],
        );

      case KioskState.success:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_photoUrl != null && _photoUrl!.isNotEmpty)
              CircleAvatar(
                radius: 50,
                backgroundImage: CachedNetworkImageProvider(_photoUrl!),
              )
            else
              CircleAvatar(radius: 50, backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.person, size: 50, color: Colors.white)),
            const SizedBox(height: 16),
            Text(_employeeName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF50CD89).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF50CD89), size: 22),
                  const SizedBox(width: 8),
                  Text(_message, style: const TextStyle(color: Color(0xFF50CD89), fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (_statusDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_statusDetail, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
            ],
          ],
        );

      case KioskState.error:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 80, color: Color(0xFFF1416C)),
            const SizedBox(height: 16),
            Text(_message, style: const TextStyle(color: Color(0xFFF1416C), fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        );
    }
  }
}
