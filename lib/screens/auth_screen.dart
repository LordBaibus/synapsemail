import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../widgets/synapse_logo.dart';
import 'app_shell.dart';
import 'forgot_password_screen.dart';
import 'otp_verification_screen.dart';

/// Combined login / sign-up screen for SynapseMail, built with Liquid Glass
/// input and button widgets inside a Material Scaffold (the app shell
/// required by the liquid_glass_widgets package itself).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isRegisterMode = false;
  bool _isLoading = false;
  String? _errorMessage;

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isRegisterMode) {
        final email = await apiService.register(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OtpVerificationScreen(email: email)),
        );
        return;
      }

      await apiService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } on UnverifiedAccountException catch (e) {
      // Correct credentials, but the account hasn't confirmed its OTP yet -
      // send the user straight to the verification screen instead of just
      // showing an error.
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtpVerificationScreen(email: e.email)),
      );
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                const Center(child: SynapseLogo(size: 88)),
                const SizedBox(height: 20),
                _buildWordmark(),
                const SizedBox(height: 6),
                Text(
                  _isRegisterMode ? 'CREATE YOUR NEURAL INBOX' : 'RECONNECT YOUR NETWORK',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9D8CFF),
                  ),
                ),
                const SizedBox(height: 32),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isRegisterMode) ...[
                        GlassTextField(
                          placeholder: 'Full name',
                          controller: _fullNameController,
                          prefixIcon: const Icon(CupertinoIcons.person, size: 18, color: Colors.white54),
                        ),
                        const SizedBox(height: 12),
                      ],
                      GlassTextField(
                        placeholder: 'Email address',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(CupertinoIcons.at, size: 18, color: Colors.white54),
                      ),
                      const SizedBox(height: 12),
                      GlassPasswordField(
                        placeholder: 'Password',
                        controller: _passwordController,
                      ),
                      if (!_isRegisterMode) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordScreen(
                                    initialEmail: _emailController.text.trim(),
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(color: Color(0xFF9D8CFF), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
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
                      const SizedBox(height: 20),
                      GlassButton.custom(
                        onTap: _isLoading ? () {} : _submit,
                        width: double.infinity,
                        height: 50,
                        shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isLoading
                                  ? 'SYNCING…'
                                  : (_isRegisterMode ? 'CREATE ACCOUNT' : 'LOG IN'),
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
                  onTap: () => setState(() {
                    _isRegisterMode = !_isRegisterMode;
                    _errorMessage = null;
                  }),
                  width: double.infinity,
                  height: 44,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                  style: GlassButtonStyle.transparent,
                  child: Text(
                    _isRegisterMode
                        ? 'Already have an account? Log in'
                        : "Don't have an account? Sign up",
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

  Widget _buildWordmark() {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        children: [
          TextSpan(text: 'Synapse', style: TextStyle(color: Colors.white)),
          TextSpan(text: 'Mail', style: TextStyle(color: Color(0xFF00E5FF))),
        ],
      ),
    );
  }
}
