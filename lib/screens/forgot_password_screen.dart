import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../widgets/synapse_logo.dart';

/// Two-step "forgot password" flow: first request a 6-digit code sent to
/// the account's registered email, then confirm that code alongside a new
/// password. Nothing is changed until the code is verified.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();

  bool _codeRequested = false;
  bool _isSubmitting = false;
  bool _isResetDone = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your account email');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await apiService.forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _infoMessage = 'If an account exists for this email, a code is on its way.';
      });
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;

    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your email');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _errorMessage = 'New password must be at least 6 characters');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await apiService.resetPassword(
        email: _emailController.text.trim(),
        otpCode: code,
        newPassword: newPassword,
      );
      if (!mounted) return;
      setState(() => _isResetDone = true);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SynapseBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: CupertinoIcons.back,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(child: SynapseLogo(size: 72)),
                const SizedBox(height: 20),
                Text(
                  _isResetDone ? 'Password reset' : 'Reset your password',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  _isResetDone
                      ? 'Your password has been changed. You can now log in with your new password.'
                      : (_codeRequested
                          ? 'Enter the 6-digit code sent to ${_emailController.text.trim()} and choose a new password.'
                          : 'Enter your account email and we\'ll send a 6-digit verification code before you change your password.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 28),
                if (!_isResetDone) ...[
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_codeRequested) ...[
                          GlassTextField(
                            placeholder: 'Email address',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: const Icon(CupertinoIcons.at, size: 18, color: Colors.white54),
                          ),
                        ] else ...[
                          GlassTextField(
                            placeholder: '6-digit code',
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            prefixIcon: const Icon(CupertinoIcons.lock_shield, size: 18, color: Colors.white54),
                          ),
                          const SizedBox(height: 12),
                          GlassPasswordField(
                            placeholder: 'New password',
                            controller: _newPasswordController,
                          ),
                        ],
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
                          onTap: _isSubmitting ? () {} : (_codeRequested ? _resetPassword : _requestCode),
                          width: double.infinity,
                          height: 50,
                          shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isSubmitting
                                    ? 'PLEASE WAIT…'
                                    : (_codeRequested ? 'RESET PASSWORD' : 'SEND CODE'),
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
                  if (_codeRequested) ...[
                    const SizedBox(height: 16),
                    GlassButton.custom(
                      onTap: _isSubmitting
                          ? () {}
                          : () => setState(() {
                                _codeRequested = false;
                                _errorMessage = null;
                                _infoMessage = null;
                              }),
                      width: double.infinity,
                      height: 44,
                      shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                      style: GlassButtonStyle.transparent,
                      child: const Text(
                        'Use a different email',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ] else ...[
                  GlassButton.custom(
                    onTap: () => Navigator.of(context).pop(),
                    width: double.infinity,
                    height: 50,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                    child: const Text(
                      'BACK TO LOG IN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
