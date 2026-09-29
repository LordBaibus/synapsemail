import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../main.dart';
import '../models/app_user.dart';
import 'auth_screen.dart';

/// Profile tab: shows the signed-in user's details and the sign-out
/// action (moved here from the old top app bar).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUser? _user;
  bool _isLoggingOut = false;

  static const _accentBright = Color(0xFF00E5FF);

  static const _popSettings = LiquidGlassSettings(
    thickness: 30,
    blur: 14,
    refractiveIndex: 1.58,
    chromaticAberration: 1.1,
    lightIntensity: 1.35,
    saturation: 1.08,
  );

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await sessionStore.getUser();
    if (!mounted) return;
    setState(() => _user = user);
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    await apiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    // The background wash is provided once by AppShell, not per-tab, so
    // the color stays consistent across Inbox/Sent/Profile and while
    // swiping between them.
    return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero panel: gradient avatar with glow ring, name and email,
              // given the same elevated "pop" glass treatment as the
              // compose/thread screens so the tab reads with more presence.
              GlassPanel(
                useOwnLayer: true,
                settings: _popSettings,
                shape: const LiquidRoundedSuperellipse(borderRadius: 26),
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                child: Column(
                  children: [
                    _Avatar(letter: (user?.fullName ?? '?').isNotEmpty
                        ? user!.fullName.trim()[0].toUpperCase()
                        : '?'),
                    const SizedBox(height: 16),
                    Text(
                      user?.fullName ?? 'Loading…',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(fontSize: 14, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailRow(
                      icon: CupertinoIcons.person,
                      label: 'Full name',
                      value: user?.fullName ?? '—',
                      accentBright: _accentBright,
                    ),
                    const Divider(color: Colors.white24, height: 28),
                    _DetailRow(
                      icon: CupertinoIcons.at,
                      label: 'Email address',
                      value: user?.email ?? '—',
                      accentBright: _accentBright,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GlassButton.custom(
                onTap: _isLoggingOut ? () {} : _logout,
                width: double.infinity,
                height: 52,
                shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                glowColor: const Color(0xFFFF6961),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLoggingOut ? 'LOGGING OUT…' : 'LOG OUT',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.square_arrow_right, color: Color(0xFFFF6961), size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accentBright;
  const _DetailRow({required this.icon, required this.label, required this.value, required this.accentBright});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentBright.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 16, color: accentBright),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontSize: 15, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String letter;
  const _Avatar({required this.letter});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF00E5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), blurRadius: 26, spreadRadius: 1),
        ],
      ),
      child: Text(
        letter,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 32),
      ),
    );
  }
}
