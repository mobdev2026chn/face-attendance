import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Image.asset('assets/images/logo.png', width: 40, height: 40),
                  const SizedBox(width: 12),
                  const Text('Menu Bar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'QUICK ACTIONS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 1.2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _MenuButton(
                    label: 'View Dashboard',
                    onTap: () {
                      // Capture the navigator BEFORE popping the drawer — popping
                      // unmounts this widget, leaving `context` defunct.
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.pushNamed('/dashboard');
                    },
                  ),
                  const SizedBox(height: 14),
                  _MenuButton(
                    label: 'Admin Panel',
                    onTap: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      navigator.pushNamed('/passcode');
                    },
                  ),
                  const SizedBox(height: 14),
                  _MenuButton(
                    label: 'Log Out',
                    color: AppColors.danger,
                    onTap: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      _confirmLogout(navigator);
                    },
                  ),
                ],
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('v1.0.0 • Powered by EktaHR', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(NavigatorState navigator) {
    showDialog(
      // The drawer (and its context) is already gone, so anchor the dialog on the
      // navigator's own context, and drive every action from the dialog's OWN
      // builder context / the captured navigator — never the dead drawer context.
      context: navigator.context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Stay Logged In')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // close the dialog
              navigator.pushNamedAndRemoveUntil('/login', (route) => false);
            },
            child: const Text('Log Out', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuButton({required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: color ?? AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label, style: TextStyle(color: color ?? AppColors.textDark, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
