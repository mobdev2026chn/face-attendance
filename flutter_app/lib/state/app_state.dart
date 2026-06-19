import 'package:flutter/foundation.dart';

import '../models/admin.dart';

class AppState extends ChangeNotifier {
  final List<Admin> _registeredAdmins = const [
    Admin(name: 'System Admin', email: 'temp@mail', password: '123'),
  ].toList();

  Admin currentUser = const Admin(name: 'System Admin', email: 'temp@mail', password: '123');

  Admin? login(String email, String password) {
    final normalizedEmail = email.trim().toLowerCase();
    for (final admin in _registeredAdmins) {
      if (admin.email.toLowerCase() == normalizedEmail && admin.password == password) {
        currentUser = admin;
        notifyListeners();
        return admin;
      }
    }
    return null;
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
