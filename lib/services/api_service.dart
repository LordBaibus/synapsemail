import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';
import '../models/email_message.dart';
import 'session_store.dart';

/// One file staged for sending, picked on-device via file_picker.
/// [bytes] is used on every platform (works for web too, where a
/// filesystem path isn't available); [path] is kept only for reference/UI.
class PendingAttachment {
  final String fileName;
  final List<int> bytes;
  final String? mimeType;

  const PendingAttachment({
    required this.fileName,
    required this.bytes,
    this.mimeType,
  });

  int get sizeBytes => bytes.length;
}

/// One registered-user match returned by [ApiService.searchUsers], used to
/// populate the To/Cc/Bcc autocomplete dropdown on the compose screen.
class UserSuggestion {
  final String fullName;
  final String email;
  const UserSuggestion({required this.fullName, required this.email});

  factory UserSuggestion.fromJson(Map<String, dynamic> json) => UserSuggestion(
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Thrown by [ApiService.login] when the account exists and the password
/// is correct, but the email address has not been verified yet (OTP not
/// confirmed). Carries the email so the UI can route straight to the OTP
/// verification screen without asking the user to type it again.
class UnverifiedAccountException implements Exception {
  final String email;
  final String message;
  UnverifiedAccountException(this.email, this.message);

  @override
  String toString() => message;
}

/// Result of fetching one email: the message itself, plus (when it is a
/// reply) the message it replied to, so the detail screen can show both
/// together like a chat reply preview.
class EmailDetail {
  final EmailMessage email;
  final EmailMessage? repliedTo;
  const EmailDetail({required this.email, this.repliedTo});
}

class ApiService {
  ApiService({required this.baseUrl, SessionStore? sessionStore})
      : _sessionStore = sessionStore ?? SessionStore();
  final String baseUrl;
  final SessionStore _sessionStore;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/$path').replace(queryParameters: query);

  Future<Map<String, String>> _headers({bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await _sessionStore.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Map<String, dynamic> _decodeRaw(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected server response (HTTP ${response.statusCode})');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final data = _decodeRaw(response);
    if (data['success'] != true) {
      throw ApiException(data['message'] as String? ?? 'Something went wrong');
    }
    return data;
  }

  /// Registers a new account. No session is created here - the account
  /// stays unverified until the emailed OTP is confirmed via [verifyOtp],
  /// so this only returns the email address the code was sent to.
  Future<String> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      _uri('register.php'),
      headers: await _headers(),
      body: jsonEncode({
        'full_name': fullName,
        'email': email,
        'password': password,
      }),
    );
    final data = _decode(response);
    return data['email'] as String? ?? email;
  }

  /// Logs in. Throws [UnverifiedAccountException] if the credentials are
  /// correct but the account's email hasn't been verified yet - the caller
  /// should route to the OTP verification screen in that case.
  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      _uri('login.php'),
      headers: await _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decodeRaw(response);

    if (data['success'] != true) {
      if (data['needs_verification'] == true) {
        throw UnverifiedAccountException(
          data['email'] as String? ?? email,
          data['message'] as String? ?? 'Please verify your email before logging in.',
        );
      }
      throw ApiException(data['message'] as String? ?? 'Something went wrong');
    }

    final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _sessionStore.save(data['token'] as String, user);
    return user;
  }

  /// Confirms a 6-digit OTP code for [email]. On success the account
  /// becomes verified and a real session token is issued and saved.
  Future<AppUser> verifyOtp({
    required String email,
    required String otpCode,
  }) async {
    final response = await http.post(
      _uri('verify_otp.php'),
      headers: await _headers(),
      body: jsonEncode({'email': email, 'otp_code': otpCode}),
    );
    final data = _decode(response);
    final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    await _sessionStore.save(data['token'] as String, user);
    return user;
  }

  /// Requests a fresh OTP code for an unverified account.
  Future<void> resendOtp(String email) async {
    final response = await http.post(
      _uri('resend_otp.php'),
      headers: await _headers(),
      body: jsonEncode({'email': email}),
    );
    _decode(response);
  }

  /// Requests a password-reset OTP be emailed to [email]. The backend
  /// always responds success (even for an unknown email) so this can't be
  /// used to check which addresses have accounts.
  Future<void> forgotPassword(String email) async {
    final response = await http.post(
      _uri('forgot_password.php'),
      headers: await _headers(),
      body: jsonEncode({'email': email}),
    );
    _decode(response);
  }

  /// Confirms the password-reset OTP and sets a new password. Any existing
  /// session for the account is invalidated server-side, so the caller
  /// should send the user back to the login screen afterward.
  Future<void> resetPassword({
    required String email,
    required String otpCode,
    required String newPassword,
  }) async {
    final response = await http.post(
      _uri('reset_password.php'),
      headers: await _headers(),
      body: jsonEncode({
        'email': email,
        'otp_code': otpCode,
        'new_password': newPassword,
      }),
    );
    _decode(response);
  }

  Future<void> logout() async {
    try {
      await http.post(_uri('logout.php'), headers: await _headers(auth: true));
    } finally {
      await _sessionStore.clear();
    }
  }

  Future<List<EmailMessage>> fetchFolder(String folder) async {
    final response = await http.get(
      _uri('inbox.php', {'folder': folder}),
      headers: await _headers(auth: true),
    );
    final data = _decode(response);
    final list = data['emails'] as List<dynamic>;
    return list
        .map((e) => EmailMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches a single email along with, if it is a reply, a compact
  /// snapshot of the message it replied to (for the inline "replied to"
  /// quote shown on the detail screen).
  Future<EmailDetail> fetchEmail(int id) async {
    final response = await http.get(
      _uri('view.php', {'id': '$id'}),
      headers: await _headers(auth: true),
    );
    final data = _decode(response);
    final email = EmailMessage.fromJson(data['email'] as Map<String, dynamic>);
    final repliedToJson = data['replied_to'] as Map<String, dynamic>?;
    return EmailDetail(
      email: email,
      repliedTo: repliedToJson != null ? EmailMessage.fromJson(repliedToJson) : null,
    );
  }

  /// Fetches every message in the same conversation as [anchorEmailId],
  /// oldest first, for the Messenger-style thread view.
  Future<List<EmailMessage>> fetchThread(int anchorEmailId) async {
    final response = await http.get(
      _uri('thread.php', {'id': '$anchorEmailId'}),
      headers: await _headers(auth: true),
    );
    final data = _decode(response);
    final list = data['messages'] as List<dynamic>;
    return list
        .map((e) => EmailMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Searches registered users by partial name/email match, for the
  /// To/Cc/Bcc autocomplete dropdown. Returns an empty list for queries
  /// under 2 characters (mirrors the backend's own early-return - no need
  /// to round-trip for a single keystroke).
  Future<List<UserSuggestion>> searchUsers(String query) async {
    if (query.trim().length < 2) return const [];
    final response = await http.get(
      _uri('search_users.php', {'q': query.trim()}),
      headers: await _headers(auth: true),
    );
    final data = _decode(response);
    final list = data['users'] as List<dynamic>? ?? [];
    return list
        .map((e) => UserSuggestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Total attachment size cap enforced client-side too, so a too-large
  /// selection is rejected before spending time on an upload the server
  /// will reject anyway (see MAX_ATTACHMENTS_BYTES in backend/config/helpers.php).
  static const maxAttachmentsBytes = 30 * 1024 * 1024;

  /// Sends a new message, or a reply when [replyToId] is set (the backend
  /// then attaches it to that message's thread). [cc]/[bcc] are lists of
  /// email addresses. [attachments] are files picked on-device. When
  /// [scheduledAt] is set (and in the future), the backend stores the
  /// message without delivering it yet - a cron job on the server sends it
  /// once that time arrives. Returns the new message's id.
  ///
  /// Always a multipart/form-data request (rather than JSON like the rest
  /// of this API) since it may carry file uploads.
  Future<int> sendEmail({
    required String recipientEmail,
    required String subject,
    required String body,
    int? replyToId,
    List<String> cc = const [],
    List<String> bcc = const [],
    List<PendingAttachment> attachments = const [],
    DateTime? scheduledAt,
  }) async {
    final totalBytes = attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    if (totalBytes > maxAttachmentsBytes) {
      throw ApiException('Attachments are too large (max 30MB total)');
    }

    final request = http.MultipartRequest('POST', _uri('send.php'));
    final token = await _sessionStore.getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['recipient_email'] = recipientEmail;
    request.fields['subject'] = subject;
    request.fields['body'] = body;
    if (replyToId != null) request.fields['reply_to_id'] = '$replyToId';
    if (cc.isNotEmpty) request.fields['cc'] = cc.join(', ');
    if (bcc.isNotEmpty) request.fields['bcc'] = bcc.join(', ');
    if (scheduledAt != null) {
      request.fields['scheduled_at'] = _formatScheduledAt(scheduledAt);
    }

    for (final attachment in attachments) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'attachments[]',
          attachment.bytes,
          filename: attachment.fileName,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final data = _decode(response);
    return data['id'] as int;
  }

  /// Formats a [DateTime] (as picked on-device, in the phone's local
  /// timezone) as the "YYYY-MM-DD HH:MM:SS" string send.php expects for
  /// scheduled_at.
  ///
  /// The Hostinger server runs on UTC (confirmed via `date` on the box),
  /// and send.php compares this string against the server's own `NOW()`/
  /// `time()`, both UTC. A phone set to Philippine time (UTC+8) picking
  /// "3:45 PM" means 3:45 PM PH time, i.e. 07:45 UTC - so this must
  /// convert to UTC before formatting, or a schedule set for "5 minutes
  /// from now" would actually fire 8 hours+5 minutes from now instead.
  String _formatScheduledAt(DateTime dt) {
    final utc = dt.toUtc();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${pad(utc.month)}-${pad(utc.day)} ${pad(utc.hour)}:${pad(utc.minute)}:${pad(utc.second)}';
  }

  /// URL to fetch one attachment's raw bytes (for previewing an image
  /// in-app) - the caller must add the Authorization header itself (see
  /// [attachmentHeaders]) since this is used directly in things like
  /// Image.network.
  Uri attachmentUri(int attachmentId) =>
      _uri('attachment.php', {'id': '$attachmentId'});

  /// Auth header map for attachment requests (e.g. Image.network, which
  /// can't await inside its build method) - call this once (e.g. in
  /// initState) and cache the result.
  Future<Map<String, String>> attachmentHeaders() => _headers(auth: true);

  /// URL to fetch one attachment for opening OUTSIDE the app (a non-image
  /// file handed to the device's own viewer/browser via url_launcher's
  /// LaunchMode.externalApplication). That external app makes its own
  /// plain HTTP request with no way for us to attach an Authorization
  /// header, so the session token rides along as a query parameter instead
  /// (backend/api/attachment.php's requireAuthFromRequest() accepts
  /// either). Never use this for anything rendered inside our own app -
  /// [attachmentUri] + [attachmentHeaders] keeps the token out of the URL
  /// there, which is the better place for it whenever a header is possible.
  Future<Uri> attachmentDownloadUri(int attachmentId) async {
    final token = await _sessionStore.getToken();
    return _uri('attachment.php', {
      'id': '$attachmentId',
      if (token != null) 'token': token,
    });
  }

  Future<void> deleteEmail(int id) async {
    final response = await http.post(
      _uri('delete.php'),
      headers: await _headers(auth: true),
      body: jsonEncode({'id': id}),
    );
    _decode(response);
  }
}
