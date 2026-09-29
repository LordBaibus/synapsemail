import 'dart:async';
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
  late final _subjectController = TextEditingController(
    text: widget.replyTo != null ? _replySubject(widget.replyTo!.subject) : '',
  );
  final _bodyController = TextEditingController();

  // Each of To/Cc/Bcc is a list of picked addresses (chips) - either chosen
  // from the registered-user autocomplete dropdown, or typed and confirmed
  // manually (the backend accepts any valid email via Cc/Bcc, and "To"
  // needs to support emailing someone who isn't a registered user of this
  // app too, since delivery goes out over real SMTP regardless).
  late final List<String> _toRecipients =
      widget.replyTo != null ? [widget.replyTo!.senderEmail] : [];
  final List<String> _ccRecipients = [];
  final List<String> _bccRecipients = [];

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
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _bodyController.text.trim();

    if (_toRecipients.isEmpty || body.isEmpty) {
      setState(() => _errorMessage = 'Recipient and message body are required');
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await apiService.sendEmail(
        recipientEmail: _toRecipients.first,
        subject: _subjectController.text.trim(),
        body: body,
        replyToId: widget.replyTo?.id,
        // Any additional "To" entries beyond the first ride along as Cc -
        // the backend's recipient_email column is a single address, so
        // this is how multiple direct recipients are supported (all of
        // them still receive the real email via SMTP either way).
        cc: [..._toRecipients.skip(1), ..._ccRecipients],
        bcc: _bccRecipients,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _RecipientField(
                                label: 'To',
                                icon: CupertinoIcons.at,
                                recipients: _toRecipients,
                                onChanged: () => setState(() {}),
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
                          _RecipientField(
                            label: 'Cc',
                            icon: CupertinoIcons.person_2,
                            recipients: _ccRecipients,
                            onChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          _RecipientField(
                            label: 'Bcc',
                            icon: CupertinoIcons.eye_slash,
                            recipients: _bccRecipients,
                            onChanged: () => setState(() {}),
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

/// A To/Cc/Bcc field: picked addresses show as removable chips, with a
/// text box alongside for typing the next one. As the user types (2+
/// chars), a debounced search hits the registered-users autocomplete
/// endpoint and shows matches in a dropdown below the field - tapping one
/// adds it as a chip, Gmail-style. Pressing enter/done on a manually typed
/// address that looks like a valid email adds it directly too, since the
/// backend accepts any address via Cc/Bcc (and To isn't limited to
/// registered users either - real delivery goes out over SMTP regardless).
class _RecipientField extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<String> recipients;
  final VoidCallback onChanged;
  const _RecipientField({
    required this.label,
    required this.icon,
    required this.recipients,
    required this.onChanged,
  });

  @override
  State<_RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<_RecipientField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();

  Timer? _debounce;
  List<UserSuggestion> _suggestions = [];
  bool _isSearching = false;
  OverlayEntry? _overlayEntry;

  static const _accentBright = Color(0xFF00E5FF);
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      _updateOverlay();
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await apiService.searchUsers(query);
        if (!mounted) return;
        // Don't suggest someone already picked in this field.
        final already = widget.recipients.toSet();
        setState(() {
          _suggestions = results.where((u) => !already.contains(u.email)).toList();
          _isSearching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _suggestions = [];
          _isSearching = false;
        });
      }
      _updateOverlay();
    });
  }

  void _addRecipient(String email) {
    final clean = email.trim();
    if (clean.isEmpty || widget.recipients.contains(clean)) {
      _controller.clear();
      setState(() => _suggestions = []);
      _updateOverlay();
      return;
    }
    widget.recipients.add(clean);
    _controller.clear();
    setState(() => _suggestions = []);
    widget.onChanged();
    _updateOverlay();
  }

  void _removeRecipient(String email) {
    widget.recipients.remove(email);
    widget.onChanged();
  }

  /// Confirms whatever's currently typed as a chip, if it looks like a
  /// valid email - called only on an explicit submit (keyboard "done"/
  /// enter). Deliberately NOT called on losing focus: silently turning
  /// whatever's mid-typed into a chip the moment the user taps elsewhere is
  /// surprising (it skips the suggestion step entirely) - tapping a
  /// suggestion or pressing done are the only two ways to commit an address.
  void _confirmTypedText() {
    final text = _controller.text.trim();
    if (_emailPattern.hasMatch(text)) {
      _addRecipient(text);
    }
  }

  void _showOverlay() {
    _removeOverlay();
    // Anchored to the field's own current height (rather than a fixed
    // offset) so the dropdown still lands right below the input row even
    // when a chips row above it has made the field taller.
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldHeight = box?.size.height ?? 44;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, fieldHeight + 4),
          child: _SuggestionDropdown(
            suggestions: _suggestions,
            isSearching: _isSearching,
            onSelected: (user) => _addRecipient(user.email),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateOverlay() {
    final shouldShow = _focusNode.hasFocus && (_suggestions.isNotEmpty || _isSearching);
    if (shouldShow) {
      if (_overlayEntry == null) {
        _showOverlay();
      } else {
        _overlayEntry!.markNeedsBuild();
      }
    } else {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        key: _fieldKey,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        // Chips (if any) get their own wrapped row above the input, and the
        // text box always spans the full remaining width on its own row -
        // rather than packing the icon/chips/input into one Wrap, where a
        // fixed-width input box made typed text visually scroll sideways
        // inside its own tiny box instead of wrapping like the chips do.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.recipients.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final email in widget.recipients)
                    _RecipientChip(email: email, onRemove: () => _removeRecipient(email)),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Icon(widget.icon, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) {
                        // Losing focus discards unconfirmed text rather than
                        // silently turning it into a chip - only tapping a
                        // suggestion or pressing done/enter commits one.
                        _controller.clear();
                        setState(() => _suggestions = []);
                        _removeOverlay();
                      } else {
                        _updateOverlay();
                      }
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: _onTextChanged,
                      onSubmitted: (_) => _confirmTypedText(),
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: widget.recipients.isEmpty ? widget.label : null,
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One picked recipient, shown as a small removable pill inside a
/// [_RecipientField].
class _RecipientChip extends StatelessWidget {
  final String email;
  final VoidCallback onRemove;
  const _RecipientChip({required this.email, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(CupertinoIcons.xmark, size: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dropdown of registered-user matches shown below a [_RecipientField]
/// while the person types, Gmail-style.
class _SuggestionDropdown extends StatelessWidget {
  final List<UserSuggestion> suggestions;
  final bool isSearching;
  final ValueChanged<UserSuggestion> onSelected;
  const _SuggestionDropdown({
    required this.suggestions,
    required this.isSearching,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1B2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: isSearching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                    ),
                    SizedBox(width: 10),
                    Text('Searching…', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              )
            : suggestions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('No matches', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final user = suggestions[index];
                      return InkWell(
                        onTap: () => onSelected(user),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFF6C5CE7),
                                child: Text(
                                  user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.fullName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                    Text(
                                      user.email,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
