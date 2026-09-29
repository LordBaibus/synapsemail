import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../main.dart';
import '../models/email_message.dart';
import '../services/api_service.dart';
import '../widgets/message_action_sheet.dart';
import 'compose_screen.dart';
import 'email_detail_screen.dart';

/// Mail list body for one folder ("inbox" or "sent"). Loading state is
/// rendered with Skeletonizer wrapping a ListView.generate of placeholder
/// rows (per requirement: "Implement skeletonizer flutter library for
/// list.generate").
///
/// This widget only renders the list itself - it has no Scaffold, app bar
/// or tab bar of its own. Folder switching and the compose FAB live in
/// [AppShell], which hosts this widget alongside the bottom navigation bar.
class InboxScreen extends StatefulWidget {
  final String folder;
  const InboxScreen({super.key, required this.folder});

  @override
  State<InboxScreen> createState() => InboxScreenState();
}

class InboxScreenState extends State<InboxScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<EmailMessage> _emails = [];

  static const _accent = Color(0xFF6C5CE7);
  static const _accentBright = Color(0xFF00E5FF);

  // Elevated glass treatment for each row, matching the "pop" style used
  // on the compose/thread screens.
  static const _rowSettings = LiquidGlassSettings(
    thickness: 24,
    blur: 12,
    refractiveIndex: 1.55,
    chromaticAberration: 0.9,
    lightIntensity: 1.25,
    saturation: 1.05,
  );

  @override
  void initState() {
    super.initState();
    _loadEmails();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder != widget.folder) {
      _loadEmails();
    }
  }

  /// Called by [AppShell] when this folder's tab is re-selected or after
  /// returning from compose/detail, so the list stays current.
  Future<void> refresh() => _loadEmails();

  Future<void> _loadEmails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final emails = await apiService.fetchFolder(widget.folder);
      if (!mounted) return;
      setState(() {
        _emails = emails;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load your mail. Tap Retry to try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteEmail(EmailMessage email) async {
    final previous = List<EmailMessage>.of(_emails);
    setState(() => _emails.removeWhere((e) => e.id == email.id));
    try {
      await apiService.deleteEmail(email.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _emails = previous);
    }
  }

  /// Asks the user to confirm before a message is actually removed, since
  /// deleting is destructive and easy to trigger by accident with a swipe.
  Future<bool> _confirmDelete(EmailMessage email) async {
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

  Future<void> openCompose() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ComposeScreen()),
    );
    if (sent == true) {
      _loadEmails();
    }
  }

  Future<void> _openEmail(EmailMessage email) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EmailDetailScreen(emailId: email.id)),
    );
    _loadEmails();
  }

  Future<void> _openReply(EmailMessage email) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(replyTo: email)),
    );
    if (sent == true) {
      _loadEmails();
    }
  }

  /// Touch-and-hold action menu (Reply / Delete) for a row, since this
  /// app is sideloaded to iOS where long-press is the expected gesture
  /// for message actions. Opens as a [GlassMenu] right at the row instead
  /// of a bottom sheet.
  Future<void> _onRowAction(EmailMessage email, MessageAction action) async {
    if (action == MessageAction.reply) {
      _openReply(email);
    } else if (action == MessageAction.delete) {
      final confirmed = await _confirmDelete(email);
      if (confirmed) _deleteEmail(email);
    }
  }

  /// Placeholder rows shown by Skeletonizer while data is loading.
  List<EmailMessage> get _placeholderEmails => List.generate(
        8,
        (index) => EmailMessage(
          id: index,
          senderEmail: 'loading@example.com',
          recipientEmail: 'me@example.com',
          subject: 'Loading subject line',
          body: 'This is a placeholder line of body text used for the skeleton loading effect.',
          isRead: true,
          createdAt: DateTime.now(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null && !_isLoading) {
      return _buildError();
    }

    // The background wash is provided once by AppShell, not per-tab, so
    // the color stays consistent across Inbox/Sent/Profile and while
    // swiping between them.
    return Skeletonizer(
      enabled: _isLoading,
      effect: ShimmerEffect(
        baseColor: Colors.white.withValues(alpha: 0.14),
        highlightColor: Colors.white.withValues(alpha: 0.24),
      ),
      child: RefreshIndicator(
        onRefresh: _loadEmails,
        child: _buildList(_isLoading ? _placeholderEmails : _emails),
      ),
    );
  }

  Widget _buildList(List<EmailMessage> emails) {
    if (emails.isEmpty) {
      final isInbox = widget.folder == 'inbox';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_accent.withValues(alpha: 0.28), _accentBright.withValues(alpha: 0.12)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    isInbox ? CupertinoIcons.tray : CupertinoIcons.paperplane,
                    size: 32,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isInbox ? 'No mail yet' : 'No sent mail yet',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  isInbox ? 'New messages will show up here' : 'Messages you send will show up here',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: emails.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildEmailRow(emails[index]),
    );
  }

  Widget _buildEmailRow(EmailMessage email) {
    final counterpart =
        widget.folder == 'inbox' ? email.senderEmail : email.recipientEmail;
    final unread = !email.isRead;

    return Dismissible(
      key: ValueKey(email.id),
      direction: DismissDirection.horizontal,
      // Swipe right (drag start-to-end, i.e. left edge moves right): reply.
      // Flutter shows `background` behind this direction - icon sits on
      // the far left so it's visible after just a little swipe.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: _accentBright.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(CupertinoIcons.arrowshape_turn_up_left_fill, color: _accentBright),
      ),
      // Swipe left (drag end-to-start, i.e. right edge moves left): delete.
      // Flutter shows `secondaryBackground` behind this direction - icon
      // sits on the far right.
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(CupertinoIcons.delete, color: Color(0xFFFF3B30)),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Reply swipe: never actually removes the row from the list.
          _openReply(email);
          return false;
        }
        return _confirmDelete(email);
      },
      onDismissed: (_) => _deleteEmail(email),
      child: MessageActionMenu(
        onSelected: (action) => _onRowAction(email, action),
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isLoading ? null : () => _openEmail(email),
        child: GlassContainer(
          useOwnLayer: true,
          settings: _rowSettings,
          shape: const LiquidRoundedSuperellipse(borderRadius: 18),
          // Padding moved off GlassContainer (which insets the fill below
          // away from the glass edge) and onto the inner Padding instead,
          // so the accent tint fills the whole tile edge-to-edge.
          padding: EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: unread ? _accent.withValues(alpha: 0.10) : Colors.transparent,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(letter: email.initialFor(counterpart), unread: unread),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                counterpart,
                                style: TextStyle(
                                  fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('MMM d').format(email.createdAt),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: unread ? _accentBright : Colors.white54,
                                fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email.subject,
                          style: TextStyle(
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (unread) ...[
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _accentBright,
                                  boxShadow: [
                                    BoxShadow(color: _accentBright.withValues(alpha: 0.7), blurRadius: 6),
                                  ],
                                ),
                              ),
                            ],
                            Expanded(
                              child: Text(
                                email.preview,
                                style: const TextStyle(fontSize: 13, color: Colors.white60),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            GlassButton.custom(
              onTap: _loadEmails,
              width: 120,
              height: 44,
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient circular initial-letter avatar with a glow ring when the
/// message is unread.
class _Avatar extends StatelessWidget {
  final String letter;
  final bool unread;
  const _Avatar({required this.letter, this.unread = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: unread
              ? const [Color(0xFF6C5CE7), Color(0xFF00E5FF)]
              : [const Color(0xFF6C5CE7).withValues(alpha: 0.35), const Color(0xFF9D8CFF).withValues(alpha: 0.25)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: unread
            ? [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 0.5)]
            : null,
      ),
      child: Text(
        letter,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}
