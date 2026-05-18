import 'package:flutter/material.dart';

class VipBadge extends StatelessWidget {
  final bool dense;

  const VipBadge({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 7,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD76A), Color(0xFFD79A2B)],
        ),
        borderRadius: BorderRadius.circular(dense ? 5 : 7),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD79A2B).withValues(alpha: 0.18),
            blurRadius: dense ? 3 : 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          color: const Color(0xFF5C3900),
          fontSize: dense ? 9 : 11,
          fontWeight: FontWeight.w900,
          height: 1.1,
        ),
      ),
    );
  }
}
