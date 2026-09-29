/// One file attached to an [EmailMessage]. The actual bytes live on the
/// server (backend/uploads/<email_id>/) and are fetched on demand via
/// ApiService.attachmentUrl(id) - only metadata is carried here.
class EmailAttachment {
  final int id;
  final String originalName;
  final String mimeType;
  final int sizeBytes;

  const EmailAttachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory EmailAttachment.fromJson(Map<String, dynamic> json) {
    return EmailAttachment(
      id: json['id'] as int,
      originalName: json['original_name'] as String? ?? 'attachment',
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      sizeBytes: json['size_bytes'] as int? ?? 0,
    );
  }

  bool get isImage => mimeType.startsWith('image/');

  /// Human-readable size, e.g. "2.4 MB".
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Status of an outgoing message, as tracked server-side.
enum EmailStatus { sent, scheduled, failed }

/// Parses a timestamp string from the backend ("YYYY-MM-DD HH:MM:SS", as
/// MySQL/PHP's DATETIME format prints it) and returns it as local time.
///
/// The backend server runs on UTC (confirmed via `date` / `php -r
/// "echo date(...)"` on the Hostinger box), but these strings carry no
/// timezone marker at all - just a bare "2026-09-29 19:42:31". Dart's
/// DateTime.parse/tryParse treats a marker-less string as already being
/// local time to whichever device parses it, so on a phone set to
/// Philippine time (UTC+8) that string was being displayed completely
/// unconverted, 8 hours behind the real time. Appending "Z" tells Dart
/// this is UTC, so parsing it correctly returns a UTC DateTime that
/// .toLocal() then converts to the device's actual timezone.
DateTime? _parseServerUtc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  // Turn "2026-09-29 19:42:31" into "2026-09-29T19:42:31Z" (ISO 8601 UTC).
  final isoUtc = '${raw.trim().replaceFirst(' ', 'T')}Z';
  final parsed = DateTime.tryParse(isoUtc);
  return parsed?.toLocal();
}

EmailStatus _statusFromJson(String? raw) {
  switch (raw) {
    case 'scheduled':
      return EmailStatus.scheduled;
    case 'failed':
      return EmailStatus.failed;
    default:
      return EmailStatus.sent;
  }
}

class EmailMessage {
  final int id;
  final String senderEmail;
  final String recipientEmail;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String body;
  final bool isRead;
  final int? threadId;
  final int? replyToId;
  final List<EmailAttachment> attachments;
  final DateTime? scheduledAt;
  final EmailStatus status;
  final DateTime createdAt;

  const EmailMessage({
    required this.id,
    required this.senderEmail,
    required this.recipientEmail,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.body,
    required this.isRead,
    this.threadId,
    this.replyToId,
    this.attachments = const [],
    this.scheduledAt,
    this.status = EmailStatus.sent,
    required this.createdAt,
  });

  factory EmailMessage.fromJson(Map<String, dynamic> json) {
    return EmailMessage(
      id: json['id'] as int,
      senderEmail: json['sender_email'] as String? ?? '',
      recipientEmail: json['recipient_email'] as String? ?? '',
      cc: _splitAddresses(json['cc'] as String?),
      bcc: _splitAddresses(json['bcc'] as String?),
      subject: (json['subject'] as String?)?.trim().isNotEmpty == true
          ? json['subject'] as String
          : '(no subject)',
      body: json['body'] as String? ?? '',
      isRead: json['is_read'] == true,
      threadId: json['thread_id'] as int?,
      replyToId: json['reply_to_id'] as int?,
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((a) => EmailAttachment.fromJson(a as Map<String, dynamic>))
          .toList(),
      scheduledAt: _parseServerUtc(json['scheduled_at'] as String?),
      status: _statusFromJson(json['status'] as String?),
      createdAt: _parseServerUtc(json['created_at'] as String?) ?? DateTime.now(),
    );
  }

  static List<String> _splitAddresses(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Whether this message is a reply to another message.
  bool get isReply => replyToId != null;

  /// Whether this message still has attachments.
  bool get hasAttachments => attachments.isNotEmpty;

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
