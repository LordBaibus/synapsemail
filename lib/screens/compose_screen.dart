import 'package:file_picker/file_picker.dart';
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
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();

  bool _isSending = false;
  String? _errorMessage;

  // Cc/Bcc fields start collapsed behind a toggle link, Gmail-style, so
  // they don't clutter the form for the common case of a single recipient.
  bool _showCcBcc = false;

  // Files picked on-device, staged for upload on send. Each carries its
  // bytes in memory (works across platforms, including web).
  final List<PendingAttachment> _attachments = [];
  bool _isPickingFiles = false;

  bool get _isReply => widget.replyTo != null;

  int get _attachmentsTotalBytes =>
      _attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);

  String get _attachmentsTotalLabel {
    final mb = _attachmentsTotalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

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
    _ccController.dispose();
    _bccController.dispose();
    super.dispose();
  }

  /// Splits a comma/semicolon-separated "a@x.com, b@y.com" field into a
  /// clean list of addresses, same convention as the backend's own parser.
  List<String> _splitAddresses(String raw) => raw
      .split(RegExp(r'[,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

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
        cc: _splitAddresses(_ccController.text),
        bcc: _splitAddresses(_bccController.text),
        attachments: _attachments,
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

  /// Runs one of file_picker's pick modes, reads the picked files' bytes
  /// into memory, and appends them to the staged attachment list - up to
  /// the 30MB combined cap (matching the server's own limit).
  ///
  /// [type] chooses which native picker opens: [FileType.media] opens the
  /// system Photos grid (PHPickerViewController on iOS, the Photos app
  /// picker on Android) for images/videos, the same picker Gmail's
  /// "insert photo" option uses - while [FileType.any] opens the general
  /// Files browser, for anything else (PDFs, docs, etc.), matching
  /// Gmail's separate "attach file" option.
  Future<void> _pickAttachments(FileType type) async {
    setState(() => _isPickingFiles = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
        withData: true,
      );
      if (result == null) return;

      final picked = <PendingAttachment>[];
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue; // shouldn't happen with withData: true
        picked.add(PendingAttachment(
          fileName: file.name,
          bytes: bytes,
          mimeType: null,
        ));
      }

      final newTotal = _attachmentsTotalBytes +
          picked.fold<int>(0, (sum, a) => sum + a.sizeBytes);
      if (newTotal > ApiService.maxAttachmentsBytes) {
        setState(() => _errorMessage = 'Attachments are too large (max 30MB total)');
        return;
      }

      setState(() {
        _attachments.addAll(picked);
        _errorMessage = null;
      });
    } finally {
      if (mounted) setState(() => _isPickingFiles = false);
    }
  }

  void _removeAttachment(PendingAttachment attachment) {
    setState(() => _attachments.remove(attachment));
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
                        Row(
                          children: [
                            Expanded(
                              child: GlassTextField(
                                placeholder: 'To',
                                controller: _toController,
                                prefixIcon: const Icon(CupertinoIcons.at, size: 18, color: Colors.white54),
                              ),
                            ),
                            if (!_showCcBcc) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _showCcBcc = true),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                  child: Text(
                                    'Cc/Bcc',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accentBright),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_showCcBcc) ...[
                          const SizedBox(height: 12),
                          GlassTextField(
                            placeholder: 'Cc',
                            controller: _ccController,
                            prefixIcon: const Icon(CupertinoIcons.person_2, size: 18, color: Colors.white54),
                          ),
                          const SizedBox(height: 12),
                          GlassTextField(
                            placeholder: 'Bcc',
                            controller: _bccController,
                            prefixIcon: const Icon(CupertinoIcons.eye_slash, size: 18, color: Colors.white54),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                      GlassTextField(
                        placeholder: 'Subject',
                        controller: _subjectController,
                        prefixIcon: const Icon(CupertinoIcons.text_alignleft, size: 18, color: Colors.white54),
                      ),
                      const SizedBox(height: 12),
                      GlassTextArea(placeholder: 'Compose your message', controller: _bodyController),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _AttachmentChips(
                          attachments: _attachments,
                          accentBright: _accentBright,
                          onRemove: _removeAttachment,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_attachmentsTotalLabel of 30 MB',
                          style: const TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _ComposeToolButton(
                            icon: CupertinoIcons.photo,
                            label: 'Photos',
                            isLoading: _isPickingFiles,
                            onTap: _isPickingFiles ? null : () => _pickAttachments(FileType.media),
                          ),
                          _ComposeToolButton(
                            icon: CupertinoIcons.paperclip,
                            label: 'Files',
                            isLoading: _isPickingFiles,
                            onTap: _isPickingFiles ? null : () => _pickAttachments(FileType.any),
                          ),
                        ],
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
                              _isSending
                                  ? 'SENDING…'
                                  : (_isReply ? 'SEND REPLY' : 'SEND'),
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

/// Small pill button used for the attach actions below the compose body,
/// Gmail-toolbar-style.
class _ComposeToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  const _ComposeToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  static const _accentBright = Color(0xFF00E5FF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accentBright),
              )
            else
              Icon(icon, size: 15, color: _accentBright),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally-wrapped chips for each staged attachment, with a remove
/// button - shown above the attach-tools row once files are picked.
class _AttachmentChips extends StatelessWidget {
  final List<PendingAttachment> attachments;
  final Color accentBright;
  final ValueChanged<PendingAttachment> onRemove;
  const _AttachmentChips({
    required this.attachments,
    required this.accentBright,
    required this.onRemove,
  });

  IconData _iconFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'].contains(ext)) {
      return CupertinoIcons.photo;
    }
    if (ext == 'pdf') return CupertinoIcons.doc_richtext;
    return CupertinoIcons.doc;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((a) {
        final sizeMb = a.sizeBytes / (1024 * 1024);
        final sizeLabel = sizeMb >= 1
            ? '${sizeMb.toStringAsFixed(1)} MB'
            : '${(a.sizeBytes / 1024).toStringAsFixed(0)} KB';
        return Container(
          padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: accentBright.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accentBright.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(a.fileName), size: 14, color: accentBright),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  a.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                sizeLabel,
                style: const TextStyle(fontSize: 10.5, color: Colors.white54),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onRemove(a),
                child: const Icon(CupertinoIcons.xmark_circle_fill, size: 16, color: Colors.white38),
              ),
            ],
          ),
        );
      }).toList(),
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
