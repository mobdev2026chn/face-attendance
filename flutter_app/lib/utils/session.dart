import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../state/app_state.dart';

bool _expiring = false;

/// The admin token was rejected (HTTP 401): sign out and return to /login.
/// Safe to call more than once — only the first call navigates.
Future<void> handleSessionExpired(BuildContext context) async {
  if (_expiring) return;
  _expiring = true;
  try {
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await appState.logout();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Your session has expired. Please sign in again.')),
    );
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
  } finally {
    _expiring = false;
  }
}

/// Wraps an admin API future: on [SessionExpired] it logs out + goes to /login,
/// then rethrows so the caller's FutureBuilder still sees an error.
Future<T> guardSession<T>(BuildContext context, Future<T> future) async {
  try {
    return await future;
  } on SessionExpired {
    if (context.mounted) await handleSessionExpired(context);
    rethrow;
  }
}
