import 'package:flutter/material.dart';
import '../main.dart';
import '../widgets/synapse_logo.dart';
import 'app_shell.dart';
import 'auth_screen.dart';

/// Checks whether a session token already exists and routes straight to
/// the inbox, or to the login/register screen otherwise.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final token = await sessionStore.getToken();
    final user = await sessionStore.getUser();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            (token != null && user != null) ? const AppShell() : const AuthScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SynapseBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SynapseLogo(size: 96),
              const SizedBox(height: 20),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  children: [
                    TextSpan(text: 'Synapse', style: TextStyle(color: Colors.white)),
                    TextSpan(text: 'Mail', style: TextStyle(color: Color(0xFF00E5FF))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
