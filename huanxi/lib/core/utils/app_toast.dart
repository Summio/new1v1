import 'package:flutter/material.dart';
import 'dart:async';

import '../../app/theme/app_theme.dart';
import '../network/api_exception.dart';

class AppToast {
  AppToast._();

  static const String _fallbackMessage = '操作失败，请稍后重试';
  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color(0xEE1C1C1E),
  }) {
    final content = message.trim().isEmpty ? _fallbackMessage : message.trim();
    final overlay = Overlay.of(context, rootOverlay: true);
    _activeEntry?.remove();
    _dismissTimer?.cancel();

    final entry = OverlayEntry(
      builder: (overlayContext) => IgnorePointer(
        child: SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  content,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(const Duration(seconds: 2), () {
      _activeEntry?.remove();
      _activeEntry = null;
      _dismissTimer = null;
    });
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

