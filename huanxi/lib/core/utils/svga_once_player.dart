import 'dart:async';

import 'package:flutter/material.dart';
import 'package:svgaplayer_flutter/svgaplayer_flutter.dart';

class SvgaOncePlayer extends StatefulWidget {
  final String resUrl;
  final BoxFit fit;
  final VoidCallback? onCompleted;

  const SvgaOncePlayer({
    super.key,
    required this.resUrl,
    this.fit = BoxFit.contain,
    this.onCompleted,
  });

  @override
  State<SvgaOncePlayer> createState() => _SvgaOncePlayerState();
}

class _SvgaOncePlayerState extends State<SvgaOncePlayer>
    with SingleTickerProviderStateMixin {
  late final SVGAAnimationController _controller;
  Timer? _fallbackTimer;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = SVGAAnimationController(vsync: this);
    _playOnce();
  }

  @override
  void didUpdateWidget(covariant SvgaOncePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resUrl != widget.resUrl) {
      _hasCompleted = false;
      _fallbackTimer?.cancel();
      _playOnce();
    }
  }

  Future<void> _playOnce() async {
    final url = widget.resUrl.trim();
    if (url.isEmpty) {
      _notifyCompleted();
      return;
    }
    try {
      final videoItem = await SVGAParser.shared.decodeFromURL(url);
      if (!mounted) {
        videoItem.dispose();
        return;
      }
      _controller.videoItem = videoItem;
      final duration =
          (_controller.duration ?? Duration.zero) +
          const Duration(milliseconds: 600);
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(duration, _notifyCompleted);
      _controller.forward(from: 0).whenComplete(_notifyCompleted);
    } catch (_) {
      _notifyCompleted();
    }
  }

  void _notifyCompleted() {
    if (_hasCompleted) {
      return;
    }
    _hasCompleted = true;
    _fallbackTimer?.cancel();
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SVGAImage(_controller, fit: widget.fit);
  }
}
