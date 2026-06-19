import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

/// Enroll + link a dev employee in one step.
/// - No [imageBase64] (dashboard): backend enrolls from the employee's EHRMS punch selfie (B).
/// - With [imageBase64] (kiosk first punch): enrolls from that live capture (A).
/// Pops `true` on success.
class EnrollLinkDialog extends StatefulWidget {
  final String? imageBase64;
  const EnrollLinkDialog({super.key, this.imageBase64});

  @override
  State<EnrollLinkDialog> createState() => _EnrollLinkDialogState();
}

class _EnrollLinkDialogState extends State<EnrollLinkDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  List<DevEmployee> _devEmployees = [];
  bool _loadingDir = true;
  String? _dirError;
  String? _selectedEmail;

  bool get _live => widget.imageBase64 != null && widget.imageBase64!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    try {
      // Load the dev directory + the already-enrolled faces, and drop employees that
      // are already linked (by EHRMS email) so the dropdown only shows linkable people.
      final results = await Future.wait([
        ApiService.fetchDevDirectory(),
        ApiService.fetchEnrolledFaces(),
      ]);
      final dir = results[0] as List<DevEmployee>;
      final faces = results[1] as List<EnrolledFace>;
      final linkedEmails = faces
          .where((f) => f.ehrmsLinked && (f.ehrmsEmail ?? '').isNotEmpty)
          .map((f) => f.ehrmsEmail!.toLowerCase())
          .toSet();
      final available = dir.where((e) => !linkedEmails.contains(e.email.toLowerCase())).toList();
      if (!mounted) return;
      setState(() { _devEmployees = available; _loadingDir = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _dirError = e.toString(); _loadingDir = false; });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedEmail == null || _password.text.isEmpty) {
      setState(() => _error = 'Pick an employee and enter their EHRMS password.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ApiService.enrollAndLink(
        email: _selectedEmail!,
        password: _password.text,
        imageBase64: widget.imageBase64,
      );
      if (mounted) Navigator.pop(context, true);
    } on NeedsLiveCapture catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '${e.message}\nNo usable EHRMS photo — enroll this person at the kiosk (their first scan becomes the enrollment).';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_live ? 'First punch — identify & enroll' : 'Enroll & link (from EHRMS)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _live
                  ? 'This captured face will be enrolled and linked to the selected employee.'
                  : "No face capture needed — the face is taken from the employee's EHRMS punch selfie.",
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            const Text('Dev EHRMS employee', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
            if (_loadingDir)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Loading dev directory...', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
              )
            else if (_dirError != null)
              Text('Directory unavailable: $_dirError', style: const TextStyle(color: AppColors.danger, fontSize: 11))
            else
              DropdownButton<String>(
                isExpanded: true,
                value: _selectedEmail,
                hint: const Text('Select employee'),
                items: _devEmployees
                    .map((e) => DropdownMenuItem(
                          value: e.email,
                          child: Text('${e.name} · ${e.email}', overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _selectedEmail = v),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'EHRMS password', prefixIcon: Icon(Icons.lock_outline)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_live ? 'Enroll & Punch' : 'Enroll & Link'),
        ),
      ],
    );
  }
}
