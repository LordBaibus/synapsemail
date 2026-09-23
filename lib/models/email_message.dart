class EmailMessage {
  final int id;
  final String senderEmail;
  final String recipientEmail;
  final String subject;
  final String body;
  final bool isRead;
  final int? threadId;
  final int? replyToId;
  final DateTime createdAt;

  const EmailMessage({
    required this.id,
    required this.senderEmail,
    required this.recipientEmail,
    required this.subject,
    required this.body,
    required this.isRead,
    this.threadId,
    this.replyToId,
    required this.createdAt,
  });

  factory EmailMessage.fromJson(Map<String, dynamic> json) {
    return EmailMessage(
      id: json['id'] as int,
      senderEmail: json['sender_email'] as String? ?? '',
      recipientEmail: json['recipient_email'] as String? ?? '',
      subject: (json['subject'] as String?)?.trim().isNotEmpty == true
          ? json['subject'] as String
          : '(no subject)',
      body: json['body'] as String? ?? '',
      isRead: json['is_read'] == true,
      threadId: json['thread_id'] as int?,
      replyToId: json['reply_to_id'] as int?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Whether this message is a reply to another message.
  bool get isReply => replyToId != null;

  /// Short preview of the body, used in the inbox list rows.
  String get preview {
    final singleLine = body.replaceAll('\n', ' ').trim();
    return singleLine.length > 80
        ? '${singleLine.substring(0, 80)}…'
        : singleLine;
  }

  String initialFor(String email) =>
      email.isNotEmpty ? email[0].toUpperCase() : '?';
}
