import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../main.dart';
import '../models/email_message.dart';
import '../services/api_service.dart';
import '../widgets/simple_header.dart';

/// Compose screen, used both for a brand-new message and for replying to
/// an existing one. When [replyTo] is set, the recipient/subject are
/// pre-filled, the field is locked, a quoted preview of the original
/// message is shown above the body, and the send call links the new
/// message to that thread via `reply_to_id`.
class ComposeScreen extends StatefulWidget {
  final EmailMessage? replyTo;
  const ComposeScreen({super.key, this.replyTo});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final _toController = TextEditingController(
    text: widget.replyTo?.senderEmail ?? '',
  );
  late final _subjectController = TextEditingController(
    text: widget.replyTo != null ? _replySubject(widget.replyTo!.subject) : '',
  );
  final _bodyController = TextEditingController();

  bool _isSending = false;
  String? _errorMessage;

  bool get _isReply => widget.replyTo != null;

  static const _accent = Color(0xFF6C5CE7);
  static const _accentBright = Color(0xFF00E5FF);

  // A more dramatic glass treatment for this screen's standalone panels -
  // higher thickness/blur/refraction than the flat grouped cards used
  // elsewhere, so it visually "pops" as its own moment.
  static const _popSettings = LiquidGlassSettings(
    thickness: 34,
    blur: 14,
    refractiveIndex: 1.6,
    chromaticAberration: 1.2,
    lightIntensity: 1.4,
    saturation: 1.1,
  );

  static String _replySubject(String original) {
    return original.toLowerCase().startsWith('re:') ? original : 'Re: $original';
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final recipient = _toController.text.trim();
    final body = _bodyController.text.trim();

    if (recipient.isEmpty || body.isEmpty) {
      setState(() => _errorMessage = 'Recipient and message body are required');
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await apiService.sendEmail(
        recipientEmail: recipient,
        subject: _subjectController.text.trim(),
        body: body,
        replyToId: widget.replyTo?.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Could not send. Check your connection.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final replyTo = widget.replyTo;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SimpleHeader(
        title: Text(
          _isReply ? 'Reply' : 'New message',
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        leading: GlassIconButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.7),
            radius: 1.5,
            colors: [
              (_isReply ? _accentBright : _accent).withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isReply) ...[
                  _HeaderBadge(isReply: _isReply, recipient: replyTo?.senderEmail),
                  const SizedBox(height: 16),
                ],
                if (replyTo != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.arrowshape_turn_up_left_fill, size: 13, color: _accentBright),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Replying to ${replyTo.senderEmail}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _accentBright),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _QuotedMessage(email: replyTo, accent: _accent, accentBright: _accentBright),
                  const SizedBox(height: 16),
                ],
                GlassPanel(
                  useOwnLayer: true,
                  settings: _popSettings,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isReply) ...[
                        GlassTextField(
                          placeholder: 'To',
                          controller: _toController,
                          prefixIcon: const Icon(CupertinoIcons.at, size: 18, color: Colors.white54),
                        ),
                        const SizedBox(height: 12),
                      ],
                      GlassTextField(
                        placeholder: 'Subject',
                        controller: _subjectController,
                        prefixIcon: const Icon(CupertinoIcons.text_alignleft, size: 18, color: Colors.white54),
                      ),
                      const SizedBox(height: 12),
                      GlassTextArea(placeholder: 'Compose your message', controller: _bodyController),
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
                      const SizedBox(height: 18),
                      GlassButton.custom(
                        onTap: _isSending ? () {} : _send,
                        width: double.infinity,
                        height: 52,
                        shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                        glowColor: _accentBright,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSending ? 'SENDING…' : (_isReply ? 'SEND REPLY' : 'SEND'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(CupertinoIcons.paperplane_fill, color: _accentBright, size: 16),
                          ],
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
    );
  }
}

/// Small glowing badge above the form for a brand-new message, naming
/// what this screen is for so it reads with more presence than a bare
/// app-bar title. Not shown when replying - the quoted message below
/// already makes clear who this is going to.
class _HeaderBadge extends StatelessWidget {
  final bool isReply;
  final String? recipient;
  const _HeaderBadge({required this.isReply, this.recipient});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: isReply
                  ? const [Color(0xFF00E5FF), Color(0xFF6C5CE7)]
                  : const [Color(0xFF6C5CE7), Color(0xFF9D8CFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: (isReply ? const Color(0xFF00E5FF) : const Color(0xFF6C5CE7)).withValues(alpha: 0.45),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            isReply ? CupertinoIcons.arrowshape_turn_up_left_fill : CupertinoIcons.envelope_fill,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isReply ? 'Replying' : 'Composing',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              if (isReply && recipient != null)
                Text(
                  'to $recipient',
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quoted preview of the message being replied to, shown Messenger-style
/// above the compose body so both sides of the reply stay together. Given
/// its own elevated glow so it reads as a distinct "quoted" surface rather
/// than blending into the form panel.
class _QuotedMessage extends StatelessWidget {
  final EmailMessage email;
  final Color accent;
  final Color accentBright;
  const _QuotedMessage({required this.email, required this.accent, required this.accentBright});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: -4),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: accentBright,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              email.preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
