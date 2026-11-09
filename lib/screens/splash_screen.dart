import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    setState(() => _showRetry = false);
    final prefs = await SharedPreferences.getInstance();
    final bool isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;

    if (isLockEnabled) {
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Please authenticate to access your documents',
          biometricOnly: false,
        );
        if (didAuthenticate) {
          _navigateToHome();
        } else {
          setState(() => _showRetry = true);
        }
      } catch (e) {
        // PlatformException if no hardware or permission denied
        setState(() => _showRetry = true);
      }
    } else {
      await Future.delayed(const Duration(seconds: 1));
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.redAccent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.picture_as_pdf, size: 100, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              'PDF Reader',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            if (_showRetry)
              ElevatedButton.icon(
                onPressed: _checkAuth,
                icon: const Icon(Icons.lock_open, color: Colors.red),
                label: const Text('Unlock App', style: TextStyle(color: Colors.red)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              )
            else
              const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
