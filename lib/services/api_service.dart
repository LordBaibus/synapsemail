import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';
import '../models/email_message.dart';
import 'session_store.dart';

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

  /// Sends a new message, or a reply when [replyToId] is set (the backend
  /// then attaches it to that message's thread). Returns the new
  /// message's id.
  Future<int> sendEmail({
    required String recipientEmail,
    required String subject,
    required String body,
    int? replyToId,
  }) async {
    final response = await http.post(
      _uri('send.php'),
      headers: await _headers(auth: true),
      body: jsonEncode({
        'recipient_email': recipientEmail,
        'subject': subject,
        'body': body,
        if (replyToId != null) 'reply_to_id': replyToId,
      }),
    );
    final data = _decode(response);
    return data['id'] as int;
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
