import 'dart:async';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../widgets/synapse_logo.dart';
import 'app_shell.dart';

/// 6-digit email verification (OTP) screen shown right after registration
/// (and after a login attempt on an unverified account). The account has
/// no session token yet - one is only issued once the code is confirmed.
class OtpVerificationScreen extends StatefulWidget {
  final String email;
  const OtpVerificationScreen({super.key, required this.email});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _infoMessage;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown -= 1;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your email');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await apiService.verifyOtp(email: widget.email, otpCode: code);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await apiService.resendOtp(widget.email);
      if (!mounted) return;
      setState(() => _infoMessage = 'A new code is on its way to your inbox.');
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SynapseBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                const Center(child: SynapseLogo(size: 72)),
                const SizedBox(height: 20),
                const Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code we sent to\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 28),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassTextField(
                        placeholder: '6-digit code',
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(CupertinoIcons.lock_shield, size: 18, color: Colors.white54),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(CupertinoIcons.exclamationmark_circle, size: 15, color: Color(0xFFFF6961)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFFFF6961), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_infoMessage != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(CupertinoIcons.checkmark_circle, size: 15, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _infoMessage!,
                                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      GlassButton.custom(
                        onTap: _isVerifying ? () {} : _verify,
                        width: double.infinity,
                        height: 50,
                        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isVerifying ? 'VERIFYING…' : 'VERIFY',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(CupertinoIcons.bolt_fill, color: Color(0xFF00E5FF), size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GlassButton.custom(
                  onTap: _resend,
                  width: double.infinity,
                  height: 44,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                  style: GlassButtonStyle.transparent,
                  child: Text(
                    _isResending
                        ? 'Sending…'
                        : (_resendCooldown > 0
                            ? 'Resend code in ${_resendCooldown}s'
                            : "Didn't get it? Resend code"),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
