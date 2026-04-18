import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../network/api_exception.dart';

class AppToast {
  AppToast._();

  static const String _fallbackMessage = '操作失败，请稍后重试';

  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color(0xEE1C1C1E),
  }) {
    final content = message.trim().isEmpty ? _fallbackMessage : message.trim();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
        content: Text(
          content,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  static void error(BuildContext context, Object error) {
    show(
      context,
      normalizeMessage(error),
      backgroundColor: AppTheme.errorColor,
    );
  }

  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    final normalized = normalizeMessage(_extractSnackBarText(snackBar));
    show(
      context,
      normalized,
      backgroundColor: snackBar.backgroundColor ?? const Color(0xEE1C1C1E),
    );
  }

  static String normalizeMessage(Object? input) {
    if (input == null) return _fallbackMessage;
    if (input is ApiException) {
      return input.message.trim().isEmpty
          ? _fallbackMessage
          : input.message.trim();
    }

    final raw = input.toString().trim();
    if (raw.isEmpty) return _fallbackMessage;

    if (raw.startsWith('Exception:')) {
      final trimmed = raw.substring('Exception:'.length).trim();
      return trimmed.isEmpty ? _fallbackMessage : trimmed;
    }
    if (raw.startsWith('Error:')) {
      final trimmed = raw.substring('Error:'.length).trim();
      return trimmed.isEmpty ? _fallbackMessage : trimmed;
    }
    return raw;
  }

  static Object? _extractSnackBarText(SnackBar snackBar) {
    final widget = snackBar.content;
    if (widget is Text) {
      return widget.data;
    }
    return widget.toStringShort();
  }
}
