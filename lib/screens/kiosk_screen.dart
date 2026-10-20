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
  bool _pinRequired = false;
  Timer? _resetTimer;
  Timer? _clockTimer;
  String _currentTime = '';
  // Standby content from the server: company, pinned announcements, next holidays
  Map<String, dynamic>? _standby;
  Timer? _standbyTimer;
  Timer? _rotateTimer;
  int _announcementIndex = 0;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _loadStandby();
    _standbyTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadStandby());
    _rotateTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final n = _announcements.length;
      if (n > 1 && mounted) setState(() => _announcementIndex = (_announcementIndex + 1) % n);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  List<dynamic> get _announcements => (_standby?['announcements'] as List?) ?? const [];
  List<dynamic> get _holidays => (_standby?['holidays'] as List?) ?? const [];
  String get _companyName => (_standby?['company']?['name'] as String?) ?? 'Charlie HRMS';
  String? get _logoUrl => _standby?['company']?['logo_url'] as String?;

  Future<void> _loadStandby() async {
    try {
      final res = await _dio.get('/standby');
      if (!mounted) return;
      setState(() {
        _standby = Map<String, dynamic>.from(res.data as Map);
        _offline = false;
        if (_announcementIndex >= _announcements.length) _announcementIndex = 0;
      });
    } on DioException {
      if (mounted) setState(() => _offline = true);
    }
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
    _standbyTimer?.cancel();
    _rotateTimer?.cancel();
    super.dispose();
  }

  Future<void> _onSubmit(String code) async {
    code = code.trim();
    if (code.isEmpty) return;
    _inputCtrl.clear();

    // While confirming a PIN-protected punch, the typed text is the PIN
    if (_state == KioskState.confirm && _pinRequired) {
      await _executeAction(pin: code);
      return;
    }

    // If confirming, cancel and look up new scan
    _resetPending();

    setState(() { _state = KioskState.loading; _message = 'Looking up...'; });

    try {
      final lookupRes = await _dio.get('/lookup', queryParameters: {'code': code});
      final emp = lookupRes.data['employee'];
      final today = lookupRes.data['today'];
      _pinRequired = lookupRes.data['pin_required'] == true;

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
          _message = "You're all done for today";
          _statusDetail = 'In ${today['clock_in']} · Out ${today['clock_out']}';
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

  Future<void> _executeAction({String? pin}) async {
    setState(() { _state = KioskState.loading; _message = 'Recording...'; });

    try {
      final res = await _dio.post(_pendingEndpoint!, data: {'code': _pendingCode, 'pin': ?pin});

      final time = res.data['clock_in'] ?? res.data['clock_out'] ?? DateFormat('hh:mm a').format(DateTime.now());
      setState(() {
        _state = KioskState.success;
        _message = '$_pendingAction at $time';
        _statusDetail = _thanks(_pendingAction ?? '');
      });
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['pin_required'] == true) {
        // Missing or wrong PIN: stay on the confirmation so they can try again
        setState(() {
          _state = KioskState.confirm;
          _message = _pendingAction ?? _message;
          _statusDetail = data['message'] ?? 'Enter your PIN';
        });
        _resetTimer?.cancel();
        _resetTimer = Timer(const Duration(seconds: 15), _resetToIdle);
        _focusNode.requestFocus();
        return;
      }
      setState(() {
        _state = KioskState.error;
        _message = data is Map ? (data['message'] ?? 'Failed') : 'Failed';
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

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _thanks(String action) {
    switch (action) {
      case 'Clock In': return 'Have a good shift!';
      case 'Break Out': return 'Enjoy your break.';
      case 'Break In': return 'Welcome back.';
      case 'Clock Out': return 'Thanks for today. See you!';
      default: return '';
    }
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
      case 'Break In': return const Color(0xFF1ABC9C);
      case 'Clock Out': return const Color(0xFFF1416C);
      default: return const Color(0xFF2ECC71);
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
              colors: [Color(0xFF0F1A14), Color(0xFF14261B)]),
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
                      Row(
                        children: [
                          if (_logoUrl != null && _logoUrl!.isNotEmpty)
                            CachedNetworkImage(imageUrl: _logoUrl!, height: 32, errorWidget: (_, _, _) => const Icon(Icons.business, color: Color(0xFF2ECC71), size: 28))
                          else
                            const Icon(Icons.business, color: Color(0xFF2ECC71), size: 28),
                          const SizedBox(width: 10),
                          Text(_companyName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                          if (_offline) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.cloud_off, size: 16, color: Colors.white.withValues(alpha: 0.4)),
                          ],
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
                    obscureText: _state == KioskState.confirm && _pinRequired,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: _state == KioskState.confirm && _pinRequired ? 'Type your PIN and press Enter' : 'Employee number',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      prefixIcon: Icon(Icons.qr_code_scanner, color: Colors.white.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2ECC71), width: 2)),
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
        return _buildStandby();

      case KioskState.loading:
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 60, height: 60, child: CircularProgressIndicator(color: Color(0xFF2ECC71), strokeWidth: 3)),
            SizedBox(height: 20),
            Text('One moment...', style: TextStyle(color: Colors.white, fontSize: 18)),
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
            Text('Hi, ${_employeeName.split(' ').first}!', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
            Text(_employeeName, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15)),
            if (_statusDetail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_statusDetail, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
            ],
            if (_pinRequired) ...[
              const SizedBox(height: 10),
              const Text('Type your PIN below, then press Enter', style: TextStyle(color: Color(0xFFFFC700), fontSize: 14, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: 260,
              height: 64,
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
              child: Text("That's not me", style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
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
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF2ECC71).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2ECC71), size: 26),
                  const SizedBox(width: 10),
                  Text(_message, style: const TextStyle(color: Color(0xFF2ECC71), fontSize: 19, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (_statusDetail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_statusDetail, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
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
  /// Idle screen: the scan prompt and the next holidays on the left, pinned announcements on the right.
  Widget _buildStandby() {
    final prompt = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.waving_hand_outlined, size: 72, color: const Color(0xFF2ECC71).withValues(alpha: 0.8)),
        const SizedBox(height: 14),
        Text('$_greeting!', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Tap your ID on the reader or type your employee number', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 16)),
        if (_holidays.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('COMING UP', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
            children: [for (final h in _holidays) _holidayChip(h)],
          ),
        ],
      ],
    );
    if (_announcements.isEmpty) return prompt;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 700;
      final card = _announcementCard(_announcements[_announcementIndex % _announcements.length]);
      if (!wide) {
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [Expanded(child: prompt), Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: card)]);
      }
      return Row(
        children: [
          Expanded(child: prompt),
          Container(width: 1, height: 220, color: Colors.white.withValues(alpha: 0.08)),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: card)),
        ],
      );
    });
  }

  Widget _holidayChip(dynamic h) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(h['label'] ?? '', style: const TextStyle(color: Color(0xFFFFC700), fontSize: 12, fontWeight: FontWeight.w700)),
          Text(h['name'] ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _announcementCard(dynamic a) {
    final n = _announcements.length;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Container(
        key: ValueKey(_announcementIndex),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin, size: 16, color: Color(0xFF2ECC71)),
                const SizedBox(width: 6),
                Text('ANNOUNCEMENT', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(a['published_at'] ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(a['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(a['body'] ?? '', maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15, height: 1.4)),
            if (n > 1) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Container(
                      width: i == _announcementIndex % n ? 18 : 6, height: 6, margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _announcementIndex % n ? 0.9 : 0.3), borderRadius: BorderRadius.circular(3)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
