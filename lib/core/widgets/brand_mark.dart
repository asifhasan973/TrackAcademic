import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double size;
  final double? borderRadius;

  const BrandMark({super.key, this.size = 72, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.3);
    final fontSize = size * 0.58;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3454D1), Color(0xFF6D5CE7)],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3454D1).withValues(alpha: 0.25),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'T',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            fontFamily: 'Roboto',
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
