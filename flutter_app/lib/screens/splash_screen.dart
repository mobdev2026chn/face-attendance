import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  int _activeDot = 0;

  @override
  void initState() {
    super.initState();

    // Cycle the loading dots animation.
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      setState(() => _activeDot = _activeDot == 0 ? 1 : 0);
      return mounted;
    });

    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final wait = Future.delayed(const Duration(milliseconds: 2000));
    final autoLogin = context.read<AppState>().tryAutoLogin();
    final results = await Future.wait([wait, autoLogin]);
    final loggedIn = results[1] as bool;

    if (!mounted) return;
    if (loggedIn) {
      Navigator.of(context).pushReplacementNamed('/scanner');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo mark ("e" icon).
              Image.asset(
                'assets/images/ekta_logo.jpeg',
                width: 160,
              ),
              const SizedBox(height: 20),
              // Wordmark ("ektaHr").
              Image.asset(
                'assets/images/logo.png',
                width: 200,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDot(_activeDot == 0),
                  const SizedBox(width: 10),
                  _buildDot(_activeDot == 1),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
      ),
    );
  }
}
