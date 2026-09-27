import 'package:flutter/foundation.dart';

class AuthScreenArgs {
  final String baseUrl;
  final Future<void> Function(String token) onSuccess;
  final VoidCallback onCancel;
  final Future<void> Function()? googleSignInHandler;
  final Future<bool> Function()? appleSignInHandler;
  final String? guestId;

  AuthScreenArgs({
    required this.baseUrl,
    required this.onSuccess,
    required this.onCancel,
    this.googleSignInHandler,
    this.appleSignInHandler,
    this.guestId,
  });
}
