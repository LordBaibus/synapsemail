import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/email_message.dart';
import '../services/api_service.dart';
import '../widgets/message_action_sheet.dart';
import '../widgets/simple_header.dart';

/// Messenger-style thread view: every message in the conversation shown as
/// chat bubbles (sent vs. received styling), with a persistent text box at
/// the bottom to send the next reply in place, instead of navigating to a
/// separate compose screen.
class EmailDetailScreen extends StatefulWidget {
  final int emailId;
  const EmailDetailScreen({super.key, required this.emailId});

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  static const _accent = Color(0xFF6C5CE7);
  static const _accentBright = Color(0xFF00E5FF);

  // Elevated glass settings for the message bubbles, so the thread reads
  // with more presence than the flat grouped cards used in the list.
  static const _popSettings = LiquidGlassSettings(
    thickness: 30,
    blur: 14,
    refractiveIndex: 1.58,
    chromaticAberration: 1.1,
    lightIntensity: 1.35,
    saturation: 1.08,
  );

  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  List<EmailMessage> _messages = [];
  String? _myEmail;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  String? _sendError;

  // The specific message the next reply will attach to. Defaults to the
  // latest message in the thread, but the user can long-press any bubble
  // and choose "Reply" to target that one instead - shown as a quoted
  // preview above the composer before sending.
  EmailMessage? _replyTarget;

  // Files staged for the NEXT reply from this thread's composer - separate
  // from the full compose screen's own attachment list, since this is a
  // different screen/state entirely. Cleared after a successful send.
  final List<PendingAttachment> _attachments = [];
  bool _isPickingFiles = false;

  // Anchors the glass attach-menu popup to the "+" button so it opens right
  // above it (same LayerLink/OverlayEntry pattern compose_screen.dart uses
  // for its recipient-suggestion dropdown).
  final _attachButtonLink = LayerLink();
  OverlayEntry? _attachMenuEntry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    _replyFocusNode.dispose();
    _removeAttachMenu();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = await sessionStore.getUser();
      final messages = await apiService.fetchThread(widget.emailId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _myEmail = user?.email;
        _isLoading = false;
        _replyTarget = messages.isNotEmpty ? messages.last : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load this conversation.';
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(target);
    }
  }

  EmailMessage get _latest => _messages.last;

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    final anchor = _replyTarget ?? (_messages.isNotEmpty ? _latest : null);
    // A reply with no typed text but at least one attachment is still a
    // valid send (Messenger-style "just a photo") - only block when BOTH
    // are empty.
    if ((text.isEmpty && _attachments.isEmpty) || anchor == null) return;

    final recipient = anchor.senderEmail == _myEmail ? anchor.recipientEmail : anchor.senderEmail;
    final subject = anchor.subject.toLowerCase().startsWith('re:') ? anchor.subject : 'Re: ${anchor.subject}';

    setState(() {
      _isSending = true;
      _sendError = null;
    });

    try {
      await apiService.sendEmail(
        recipientEmail: recipient,
        subject: subject,
        body: text,
        replyToId: anchor.id,
        attachments: _attachments,
      );
      _replyController.clear();
      final messages = await apiService.fetchThread(widget.emailId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _attachments.clear();
        // Back to replying to the newest message by default until the
        // user picks a specific one again.
        _replyTarget = messages.isNotEmpty ? messages.last : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } on ApiException catch (e) {
      setState(() => _sendError = e.message);
    } catch (_) {
      setState(() => _sendError = 'Could not send. Check your connection.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Runs one of file_picker's pick modes and stages the result for the
  /// next reply - mirrors compose_screen.dart's _pickAttachments, kept as
  /// its own copy here since this screen has its own separate attachment
  /// list scoped to the thread reply bar.
  Future<void> _pickComposerAttachments(FileType type) async {
    _removeAttachMenu();
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
        if (bytes == null) continue;
        picked.add(PendingAttachment(fileName: file.name, bytes: bytes, mimeType: null));
      }

      final currentTotal = _attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
      final newTotal = currentTotal + picked.fold<int>(0, (sum, a) => sum + a.sizeBytes);
      if (newTotal > ApiService.maxAttachmentsBytes) {
        setState(() => _sendError = 'Attachments are too large (max 30MB total)');
        return;
      }

      setState(() {
        _attachments.addAll(picked);
        _sendError = null;
      });
    } finally {
      if (mounted) setState(() => _isPickingFiles = false);
    }
  }

  void _removeComposerAttachment(PendingAttachment attachment) {
    setState(() => _attachments.remove(attachment));
  }

  void _toggleAttachMenu() {
    if (_attachMenuEntry != null) {
      _removeAttachMenu();
    } else {
      _showAttachMenu();
    }
  }

  void _showAttachMenu() {
    _removeAttachMenu();
    _attachMenuEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Full-screen transparent barrier so tapping anywhere outside the
          // menu closes it, same as a standard popup menu.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeAttachMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _attachButtonLink,
            showWhenUnlinked: false,
            // Anchored by its right edge, growing upward-and-leftward from
            // the attach button's top-right corner - the button sits near
            // the right side of the screen (beside Send), so anchoring by
            // the left edge instead would push most of a 200px-wide menu
            // off the right edge of the screen.
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -8),
            child: _GlassAttachMenu(
              onInsertImage: () => _pickComposerAttachments(FileType.media),
              onAddAttachment: () => _pickComposerAttachments(FileType.any),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_attachMenuEntry!);
  }

  void _removeAttachMenu() {
    _attachMenuEntry?.remove();
    _attachMenuEntry = null;
  }

  Future<void> _deleteMessage(EmailMessage message) async {
    try {
      await apiService.deleteEmail(message.id);
    } catch (_) {
      // Best-effort; refresh below reflects whatever the server has.
    }
    if (!mounted) return;
    if (_messages.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    final messages = await apiService.fetchThread(widget.emailId);
    if (!mounted) return;
    setState(() => _messages = messages);
  }

  final _replyFocusNode = FocusNode();

  void _prefillReplyTo(EmailMessage message) {
    // "Reply" from a specific bubble targets that exact message - shown as
    // a quoted preview above the composer - rather than always attaching
    // to the newest message in the thread.
    setState(() => _replyTarget = message);
    _replyFocusNode.requestFocus();
  }

  void _cancelReplyTarget() {
    setState(() => _replyTarget = _messages.isNotEmpty ? _latest : null);
  }

  Future<bool> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete message?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This message will be permanently deleted.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF6961), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onBubbleAction(EmailMessage message, MessageAction action) async {
    if (action == MessageAction.reply) {
      _prefillReplyTo(message);
    } else if (action == MessageAction.delete) {
      final confirmed = await _confirmDelete();
      if (confirmed) _deleteMessage(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      appBar: SimpleHeader(
        leading: GlassIconButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _messages.isNotEmpty
            ? Text(
                _counterpartLabelFor(_latest),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              )
            : null,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.6),
            radius: 1.5,
            colors: [_accent.withValues(alpha: 0.14), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_messages.isNotEmpty) _buildSubjectBar(),
              Expanded(child: _buildBody()),
              if (!_isLoading && _errorMessage == null) _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  /// The other people on this message - everyone besides the signed-in
  /// user. When the message was sent BY the user, that's the recipient plus
  /// anyone on Cc (extra "To" addresses ride along as Cc under the hood,
  /// since recipient_email is a single column - see compose_screen.dart's
  /// _send()), so all of them need to show here, not just the first one.
  /// When the message was sent TO the user, it's just the sender - Bcc is
  /// intentionally never shown (the whole point of Bcc).
  List<String> _counterpartsFor(EmailMessage message) {
    if (message.senderEmail != _myEmail) return [message.senderEmail];
    return [
      message.recipientEmail,
      ...message.cc,
    ].where((e) => e.isNotEmpty && e != _myEmail).toSet().toList();
  }

  String _counterpartLabelFor(EmailMessage message) {
    final others = _counterpartsFor(message);
    if (others.isEmpty) return message.recipientEmail;
    if (others.length <= 2) return others.join(', ');
    return '${others.take(2).join(', ')} +${others.length - 2} more';
  }

  Widget _buildSubjectBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        _latest.subject,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white54),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null && !_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              GlassButton.custom(
                onTap: _load,
                width: 120,
                height: 44,
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Skeletonizer(
        enabled: true,
        effect: ShimmerEffect(
          baseColor: Colors.white.withValues(alpha: 0.14),
          highlightColor: Colors.white.withValues(alpha: 0.24),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _BubbleSkeleton(alignEnd: false),
            _BubbleSkeleton(alignEnd: true),
            _BubbleSkeleton(alignEnd: false),
          ],
        ),
      );
    }

    final byId = {for (final m in _messages) m.id: m};

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.senderEmail == _myEmail;
        final showDateDivider = index == 0 ||
            !_isSameDay(_messages[index - 1].createdAt, message.createdAt);
        final repliedTo = message.replyToId != null ? byId[message.replyToId] : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateDivider) _DateDivider(date: message.createdAt),
            _MessageBubble(
              message: message,
              repliedTo: repliedTo,
              // Standard Messenger convention: the current user's own
              // messages sit on the right, the other person's on the left.
              alignRight: isMine,
              accent: _accent,
              accentBright: _accentBright,
              settings: _popSettings,
              onAction: (action) => _onBubbleAction(message, action),
            ),
          ],
        );
      },
    );
  }

  Widget _buildComposer() {
    // Only show the "replying to" quote when the target isn't simply the
    // newest message - that's the implicit default and doesn't need
    // calling out every time.
    final showTargetQuote = _replyTarget != null && _replyTarget!.id != _latest.id;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTargetQuote) ...[
              _ReplyTargetBar(
                message: _replyTarget!,
                accentBright: _accentBright,
                onCancel: _cancelReplyTarget,
              ),
              const SizedBox(height: 6),
            ],
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text(
                  _sendError!,
                  style: const TextStyle(color: Color(0xFFFF6961), fontSize: 12),
                ),
              ),
            if (_attachments.isNotEmpty) ...[
              _ComposerAttachmentChips(
                attachments: _attachments,
                accentBright: _accentBright,
                onRemove: _removeComposerAttachment,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: GlassTextField(
                    placeholder: 'Reply…',
                    controller: _replyController,
                    focusNode: _replyFocusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _isSending ? null : _sendReply(),
                  ),
                ),
                const SizedBox(width: 8),
                // Attach button, right beside the send button - tapping it
                // expands a small glass popup menu with "Insert Image" and
                // "Add Attachment" instead of guessing which picker the
                // user wants.
                CompositedTransformTarget(
                  link: _attachButtonLink,
                  child: GlassButton.custom(
                    onTap: _isPickingFiles ? () {} : _toggleAttachMenu,
                    width: 44,
                    height: 44,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                    child: Center(
                      child: _isPickingFiles
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _accentBright),
                            )
                          : const Icon(CupertinoIcons.paperclip, color: _accentBright, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GlassButton.custom(
                  onTap: _isSending ? () {} : _sendReply,
                  width: 44,
                  height: 44,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                  glowColor: _accentBright,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accentBright,
                    ),
                    child: const SizedBox.expand(
                      child: Icon(CupertinoIcons.paperplane_fill, color: Colors.black, size: 18),
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

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

/// One chat bubble, with Gmail-style sender/recipient/time details and,
/// when the message is a reply, a small quoted preview of the message it
/// replied to (Messenger-style). Per the requested layout, [alignRight]
/// controls which side the bubble sits on - the other person's messages on
/// the right, the current user's own messages on the left.
class _MessageBubble extends StatelessWidget {
  final EmailMessage message;
  final EmailMessage? repliedTo;
  final bool alignRight;
  final Color accent;
  final Color accentBright;
  final LiquidGlassSettings settings;
  final ValueChanged<MessageAction> onAction;

  const _MessageBubble({
    required this.message,
    this.repliedTo,
    required this.alignRight,
    required this.accent,
    required this.accentBright,
    required this.settings,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          child: MessageActionMenu(
            onSelected: onAction,
            child: GlassPanel(
              useOwnLayer: true,
              settings: settings,
              shape: LiquidRoundedSuperellipse(
                borderRadius: 18,
              ),
              // GlassPanel defaults to 24px of its own padding around the
              // child - that gap was showing as empty glass around the
              // colored fill below. Zero it out; the real content padding
              // is the Padding(14, 10) inside the DecoratedBox already.
              padding: EdgeInsets.zero,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: alignRight ? accent.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.05),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gmail-style per-message details: who it's from, who
                      // it's to, and the subject line for this specific
                      // message.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message.senderEmail,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat.jm().format(message.createdAt),
                            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.55)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        // Includes Cc'd addresses too - a message sent to
                        // several people has any extras beyond the first
                        // "To" riding along as Cc (see compose_screen.dart's
                        // _send()), so this needs all of them, not just the
                        // recipient_email column.
                        'to ${[message.recipientEmail, ...message.cc].join(', ')}',
                        style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.45)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message.subject,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (repliedTo != null) ...[
                        const SizedBox(height: 8),
                        _RepliedToQuote(message: repliedTo!, accentBright: accentBright),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        message.body,
                        style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.white),
                      ),
                      if (message.hasAttachments) ...[
                        const SizedBox(height: 10),
                        _BubbleAttachments(
                          attachments: message.attachments,
                          accentBright: accentBright,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Downloads an attachment's bytes (authenticated) and hands them to the
/// OS share sheet, from which the user can pick "Save Image"/"Save to
/// Files" or share it to another app - this is what actually lets someone
/// keep a copy of a photo or file, rather than just viewing it in-app.
/// Shows a brief SnackBar on failure (e.g. no connection).
Future<void> _saveOrShareAttachment(BuildContext context, EmailAttachment attachment) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await apiService.downloadAttachmentBytes(attachment.id);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${attachment.originalName}');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: attachment.mimeType)]),
    );
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not save this attachment. Check your connection.')),
    );
  }
}

/// Attachments carried by a single message bubble: image attachments show
/// as tappable thumbnails (fetched from the authenticated attachment
/// endpoint), everything else shows as a small file chip with name and
/// size. Tapping either opens the raw file in a full-screen viewer/browser
/// tab depending on type.
class _BubbleAttachments extends StatelessWidget {
  final List<EmailAttachment> attachments;
  final Color accentBright;
  const _BubbleAttachments({required this.attachments, required this.accentBright});

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => !a.isImage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: images.map((a) => _AttachmentThumbnail(attachment: a)).toList(),
          ),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 8),
        if (files.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: files
                .map((a) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _AttachmentFileChip(attachment: a, accentBright: accentBright),
                    ))
                .toList(),
          ),
      ],
    );
  }
}

/// One image attachment, fetched via the authenticated attachment endpoint
/// and shown as a rounded thumbnail. Tapping opens it full-screen.
class _AttachmentThumbnail extends StatelessWidget {
  final EmailAttachment attachment;
  const _AttachmentThumbnail({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: apiService.attachmentHeaders(),
      builder: (context, snapshot) {
        final headers = snapshot.data;
        return GestureDetector(
          onTap: headers == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _AttachmentImageViewer(attachment: attachment, headers: headers),
                    ),
                  ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 140,
              height: 140,
              child: headers == null
                  ? const ColoredBox(color: Colors.black26)
                  : Image.network(
                      apiService.attachmentUri(attachment.id).toString(),
                      headers: headers,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const ColoredBox(
                          color: Colors.black26,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stack) => const ColoredBox(
                        color: Colors.black26,
                        child: Center(
                          child: Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.white38, size: 22),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen viewer for a tapped image attachment.
class _AttachmentImageViewer extends StatelessWidget {
  final EmailAttachment attachment;
  final Map<String, String> headers;
  const _AttachmentImageViewer({required this.attachment, required this.headers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(attachment.originalName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            tooltip: 'Save or share',
            onPressed: () => _saveOrShareAttachment(context, attachment),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            apiService.attachmentUri(attachment.id).toString(),
            headers: headers,
          ),
        ),
      ),
    );
  }
}

/// Non-image attachment (PDF, doc, etc.) shown as a small tappable chip
/// with an icon, filename and size. Tapping opens it in the device browser,
/// which is enough to view/download most common file types.
class _AttachmentFileChip extends StatelessWidget {
  final EmailAttachment attachment;
  final Color accentBright;
  const _AttachmentFileChip({required this.attachment, required this.accentBright});

  IconData get _icon {
    if (attachment.mimeType == 'application/pdf') return CupertinoIcons.doc_richtext;
    return CupertinoIcons.doc;
  }

  /// Opening this in the device's own viewer/browser (LaunchMode.
  /// externalApplication) means that external app makes its own plain HTTP
  /// request - it can't carry the Authorization header our own app would
  /// normally send, which is exactly why this was failing with "Missing or
  /// invalid Authorization header" instead of actually opening the file.
  /// attachmentDownloadUri() embeds the session token in the URL itself
  /// instead, which the backend also accepts (see
  /// backend/config/helpers.php's requireAuthFromRequest()).
  Future<void> _open() async {
    final uri = await apiService.attachmentDownloadUri(attachment.id);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // The "open" tap area and the "save" icon are siblings, not nested
    // GestureDetectors - nesting two tap handlers over the same pixels is
    // ambiguous in Flutter's gesture arena, so they're kept side by side
    // in this Row instead.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentBright.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _open,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: 16, color: accentBright),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    attachment.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  attachment.formattedSize,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(CupertinoIcons.share, size: 15, color: accentBright),
            tooltip: 'Save or share',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () => _saveOrShareAttachment(context, attachment),
          ),
        ],
      ),
    );
  }
}

/// Small quoted snippet of the message a reply was sent in response to,
/// shown inline above the reply's own body (Messenger-style "replying to").
class _RepliedToQuote extends StatelessWidget {
  final EmailMessage message;
  final Color accentBright;
  const _RepliedToQuote({required this.message, required this.accentBright});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accentBright.withValues(alpha: 0.7), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.arrowshape_turn_up_left_fill, size: 11, color: accentBright),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  message.senderEmail,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentBright),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            message.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Centered date pill shown before the first message of a new day, same
/// pattern as Messenger/iMessage.
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final label = isToday ? 'Today' : DateFormat.yMMMd().format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Small glass-styled popup menu shown above the thread composer's attach
/// button, offering the same two picker modes compose_screen.dart's
/// standalone Photos/Files buttons do - Gmail/Messenger-style, condensed
/// into one menu since there's only room for a single "+" button here.
class _GlassAttachMenu extends StatelessWidget {
  final VoidCallback onInsertImage;
  final VoidCallback onAddAttachment;
  const _GlassAttachMenu({required this.onInsertImage, required this.onAddAttachment});

  static const _accentBright = Color(0xFF00E5FF);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GlassPanel(
        useOwnLayer: true,
        shape: const LiquidRoundedSuperellipse(borderRadius: 18),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                icon: CupertinoIcons.photo,
                label: 'Insert Image',
                onTap: onInsertImage,
              ),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              _MenuRow(
                icon: CupertinoIcons.paperclip,
                label: 'Add Attachment',
                onTap: onAddAttachment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: _GlassAttachMenu._accentBright),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally-wrapped chips for files staged for the thread's next reply,
/// shown above the reply bar once something's picked - mirrors
/// compose_screen.dart's _AttachmentChips (kept as its own copy since that
/// one is private to the other file).
class _ComposerAttachmentChips extends StatelessWidget {
  final List<PendingAttachment> attachments;
  final Color accentBright;
  final ValueChanged<PendingAttachment> onRemove;
  const _ComposerAttachmentChips({
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
              Text(sizeLabel, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
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

/// Shown above the composer when the user has picked a specific earlier
/// message to reply to (via long-press → Reply), quoting that message so
/// it's clear what the next message will attach to before it's sent.
class _ReplyTargetBar extends StatelessWidget {
  final EmailMessage message;
  final Color accentBright;
  final VoidCallback onCancel;
  const _ReplyTargetBar({required this.message, required this.accentBright, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accentBright.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accentBright.withValues(alpha: 0.8), width: 3)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.arrowshape_turn_up_left_fill, size: 13, color: accentBright),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${message.senderEmail}',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accentBright),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

/// Placeholder bubble shown by Skeletonizer while the thread loads.
class _BubbleSkeleton extends StatelessWidget {
  final bool alignEnd;
  const _BubbleSkeleton({required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: 220,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
