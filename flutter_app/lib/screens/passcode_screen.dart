import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PasscodeScreen extends StatefulWidget {
  const PasscodeScreen({super.key});

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  String _passcode = '';

  void _onKeyTap(String key) {
    setState(() {
      if (key == 'CLEAR') {
        _passcode = '';
      } else if (key == 'BACK') {
        if (_passcode.isNotEmpty) _passcode = _passcode.substring(0, _passcode.length - 1);
      } else if (_passcode.length < 4) {
        _passcode += key;
      }
    });
  }

  void _verify() {
    if (_passcode == '1234') {
      setState(() => _passcode = '');
      Navigator.of(context).pushReplacementNamed('/admin');
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Access Denied'),
          content: const Text('Incorrect Admin Passkey!'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      setState(() => _passcode = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text('Mark Attendance', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 30),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    const Text('Enter PIN', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('Verify your identity to proceed', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final filled = index < _passcode.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? AppColors.primary : Colors.transparent,
                            border: filled ? null : Border.all(color: AppColors.textMuted, width: 1.5),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.4,
                  children: [
                    ...['1', '2', '3', '4', '5', '6', '7', '8', '9'].map(_buildKey),
                    _buildKey('CLEAR'),
                    _buildKey('0'),
                    _buildKey('BACK'),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Unlock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKey(String key) {
    final isSpecial = key == 'CLEAR' || key == 'BACK';
    return Material(
      color: isSpecial ? Colors.transparent : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onKeyTap(key),
        child: Center(
          child: key == 'BACK'
              ? const Icon(Icons.backspace_outlined, color: Colors.white)
              : Text(
                  key,
                  style: TextStyle(
                    color: isSpecial ? AppColors.textMuted : Colors.white,
                    fontSize: isSpecial ? 13 : 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
