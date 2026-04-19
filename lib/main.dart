import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/api.dart';
import 'screens/setup_screen.dart';
import 'screens/kiosk_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to landscape for kiosk/tablet mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  // Hide status bar for kiosk mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const CharlieKiosk());
}

class CharlieKiosk extends StatelessWidget {
  const CharlieKiosk({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Charlie Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF009EF7),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const SplashScreen(),
      routes: {
        '/setup': (_) => const SetupScreen(),
        '/kiosk': (_) => const KioskScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    await KioskApi.loadConfig();
    if (!mounted) return;

    if (KioskApi.isConfigured) {
      Navigator.pushReplacementNamed(context, '/kiosk');
    } else {
      Navigator.pushReplacementNamed(context, '/setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)]),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.business, size: 64, color: Color(0xFF009EF7)),
              SizedBox(height: 16),
              Text('Charlie Kiosk', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFF009EF7)),
            ],
          ),
        ),
      ),
    );
  }
}
