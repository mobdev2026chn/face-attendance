import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/admin.dart';

/// Outcome of an admin login attempt: [admin] on success, otherwise a
/// human-readable [error] explaining why login was refused.
class LoginResult {
  final Admin? admin;
  final String? error;
  const LoginResult({this.admin, this.error});

  bool get ok => admin != null;
}

class AppState extends ChangeNotifier {
  // Locally signed-up admins (kept only so the legacy Sign Up screen still
  // works); kiosk login authenticates against EHRMS, not this list.
  final List<Admin> _registeredAdmins = <Admin>[];

  Admin? currentUser;

  /// EHRMS `users.role` values allowed to operate the face kiosk. Login is
  /// admin-only: the dev DB holds exactly Admin / Super Admin / Employee /
  /// Candidate, so only "Admin" and "Super Admin" may log in — everything else
  /// (Employee, Candidate, …) is rejected.
  static bool isAdminRole(String? role) {
    final r = (role ?? '').trim().toLowerCase();
    const allowed = {'admin', 'super admin', 'superadmin'};
    return allowed.contains(r);
  }

  /// Authenticate against the EHRMS users collection (single source of truth)
  /// and admit ONLY admin-role users. Returns a [LoginResult] — never throws.
  Future<LoginResult> login(String email, String password) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      return const LoginResult(error: 'Please enter both your email and password.');
    }

    final base = kEhrmsBaseUrl.replaceAll(RegExp(r'/+$'), '');
    http.Response res;
    try {
      // Kiosk admin gate: verifies credentials + role against the EHRMS `users`
      // collection ONLY (no Staff profile required, unlike /auth/login). The
      // server admits only Admin / Super Admin and 403s everyone else.
      res = await http
          .post(
            Uri.parse('$base/api/auth/kiosk-admin-login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': normalizedEmail, 'password': password}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      return const LoginResult(
          error: 'Could not reach the server. Check your connection and try again.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }

    String detail(String fallback) {
      final err = body['error'];
      final msg = (err is Map ? err['message'] : null) ?? body['message'];
      return (msg ?? fallback).toString();
    }

    // 403 = authenticated but not an admin → surface the server's "not an admin" message.
    if (res.statusCode == 403) {
      return LoginResult(error: detail('You are not an admin. Only admin accounts can log in.'));
    }
    if (res.statusCode != 200 || body['success'] != true) {
      return LoginResult(error: detail('Incorrect email or password.'));
    }

    final data = (body['data'] is Map) ? body['data'] as Map<String, dynamic> : const {};
    if (data['user'] is! Map) {
      return LoginResult(error: detail('Login failed. Please try again.'));
    }

    final user = data['user'] as Map<String, dynamic>;
    final role = user['role']?.toString();

    // Defense-in-depth: the server already enforced this, but re-check client-side.
    if (!isAdminRole(role)) {
      final shown = (role != null && role.trim().isNotEmpty) ? ' (your role: $role)' : '';
      return LoginResult(
          error: 'You are not an admin. Only admin accounts can log in$shown.');
    }

    final admin = Admin(
      name: (user['name'] ?? 'Admin').toString(),
      email: (user['email'] ?? normalizedEmail).toString(),
      password: password,
    );
    currentUser = admin;
    notifyListeners();
    return LoginResult(admin: admin);
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

    _registeredAdmins.add(Admin(name: name.trim(), email: normalizedEmail, password: password));
    notifyListeners();
    return null;
  }
}
