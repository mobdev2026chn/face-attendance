import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin.dart';
import '../services/api_service.dart';

/// Outcome of an admin login attempt: [admin] on success, otherwise a
/// human-readable [error] explaining why login was refused.
class LoginResult {
  final Admin? admin;
  final String? error;
  const LoginResult({this.admin, this.error});

  bool get ok => admin != null;
}

const String kAdminOnlyMessage = 'Only company admin accounts can sign in to the kiosk.';

class AppState extends ChangeNotifier {
  // SharedPreferences keys. Only the token + admin identity are persisted —
  // never the password.
  static const _kToken = 'auth_token';
  static const _kName = 'admin_name';
  static const _kEmail = 'admin_email';
  static const _kAdminId = 'admin_id';
  // Legacy keys written by older builds; always purged.
  static const _legacyKeys = ['admin_password', 'refresh_token', 'user_data'];

  // Locally signed-up admins (kept only so the legacy Sign Up screen still
  // works); kiosk login authenticates against HRMS, not this list.
  final List<Admin> _registeredAdmins = <Admin>[];

  Admin? currentUser;
  String? authToken;

  /// Current admin bearer token (null when signed out). Used by [ApiService].
  static String? get token => ApiService.authToken;

  static Future<void> _purgeLegacy(SharedPreferences prefs) async {
    for (final k in _legacyKeys) {
      await prefs.remove(k);
    }
  }

  /// Restores saved session on app startup so login is not asked every time.
  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _purgeLegacy(prefs);
      final token = prefs.getString(_kToken);
      final email = prefs.getString(_kEmail);
      final name = prefs.getString(_kName) ?? 'Admin';

      if (token != null && token.isNotEmpty && email != null && email.isNotEmpty) {
        authToken = token;
        ApiService.authToken = token;
        currentUser = Admin(name: name, email: email, id: prefs.getString(_kAdminId));
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Clears the stored session (also used when the server reports 401).
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kToken);
      await prefs.remove(_kName);
      await prefs.remove(_kEmail);
      await prefs.remove(_kAdminId);
      await _purgeLegacy(prefs);
    } catch (_) {}
    authToken = null;
    ApiService.authToken = null;
    currentUser = null;
    notifyListeners();
  }

  /// Kiosk operators must be company admins (HRMS `user.role == 'admin'`).
  static bool isAdminRole(String? role) => (role ?? '').trim().toLowerCase() == 'admin';

  /// Authenticate against HRMS `POST /auth/login` and admit ONLY admin users.
  /// Returns a [LoginResult] — never throws.
  Future<LoginResult> login(String email, String password) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      return const LoginResult(error: 'Please enter both your email and password.');
    }

    final LoginPayload payload;
    try {
      payload = await ApiService.login(normalizedEmail, password);
    } on ApiException catch (e) {
      return LoginResult(error: e.message);
    } catch (_) {
      return const LoginResult(error: 'Could not reach the server. Check your connection and try again.');
    }

    if (!payload.isAdmin) {
      return const LoginResult(error: kAdminOnlyMessage);
    }

    final admin = Admin(
      name: payload.name.isNotEmpty ? payload.name : 'Admin',
      email: payload.email.isNotEmpty ? payload.email : normalizedEmail,
      id: payload.adminId ?? payload.id,
    );
    await _saveSession(admin, payload.token);
    return LoginResult(admin: admin);
  }

  /// Re-verify the signed-in admin with their password (Admin Panel gate,
  /// face reset). Returns null on success, or an error message. On success the
  /// fresh token replaces the stored one.
  Future<String?> verifyAdminPassword(String password) async {
    final email = currentUser?.email ?? '';
    if (email.isEmpty) return 'Your session has expired. Please sign in again.';
    if (password.isEmpty) return 'Please enter your admin password.';

    final LoginPayload payload;
    try {
      payload = await ApiService.login(email, password);
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
    if (!payload.isAdmin) return kAdminOnlyMessage;

    await _saveSession(currentUser!, payload.token);
    return null;
  }

  Future<void> _saveSession(Admin admin, String token) async {
    currentUser = admin;
    authToken = token;
    ApiService.authToken = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kToken, token);
      await prefs.setString(_kName, admin.name);
      await prefs.setString(_kEmail, admin.email);
      if (admin.id != null && admin.id!.isNotEmpty) {
        await prefs.setString(_kAdminId, admin.id!);
      } else {
        await prefs.remove(_kAdminId);
      }
      await _purgeLegacy(prefs);
    } catch (_) {}
    notifyListeners();
  }

  /// Returns null on success, or an error message on failure.
  String? signUp({required String name, required String email, required String password, required String confirmPassword}) {
    final normalizedEmail = email.trim().toLowerCase();
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (!emailRegex.hasMatch(normalizedEmail)) {
      return 'Please enter a valid email address.';
    }
    if (password != confirmPassword) {
      return 'Passwords do not match. Please verify.';
    }
    if (_registeredAdmins.any((a) => a.email.toLowerCase() == normalizedEmail)) {
      return 'Email "$normalizedEmail" is already registered. Please log in.';
    }

    _registeredAdmins.add(Admin(name: name.trim(), email: normalizedEmail));
    notifyListeners();
    return null;
  }
}
