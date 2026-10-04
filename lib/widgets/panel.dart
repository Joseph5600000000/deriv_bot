import 'package:flutter/material.dart';

class Pal {
  static const bg = Color(0xFF0E1115), metalTop = Color(0xFF2B3038), metalBot = Color(0xFF181B20), edge = Color(0xFF3B424C);
  static const green = Color(0xFF2ED47A), red = Color(0xFFFF4D5E), amber = Color(0xFFFFB020), neutral = Color(0xFF8A94A3),
      lcd = Color(0xFF0A0D10), text = Color(0xFFE6EAF0), dim = Color(0xFF8A94A3);
}

const TextStyle kMono = TextStyle(fontFamily: 'monospace', fontFeatures: [FontFeature.tabularFigures()]);

/// Brushed-metal panel with a bevel highlight and drop shadow.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Pal.metalTop, Pal.metalBot]),
          border: Border.all(color: Pal.edge, width: 1),
          boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 4)),
                            BoxShadow(color: Color(0x1FFFFFFF), blurRadius: 0, offset: Offset(0, -1))],
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: const TextStyle(color: Pal.dim, fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
            const Spacer(), if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8), child,
        ]),
      );
}

/// Inset LCD read-out.
class Lcd extends StatelessWidget {
  const Lcd(this.label, this.value, {super.key, this.color = Pal.text, this.size = 20});
  final String label, value;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Pal.lcd, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black),
          boxShadow: const [BoxShadow(color: Color(0x33FFFFFF), offset: Offset(0, 1), blurRadius: 0)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: Pal.dim, fontSize: 9, letterSpacing: 1.2)),
          Text(value, style: kMono.copyWith(color: color, fontSize: size, fontWeight: FontWeight.w600)),
        ]),
      );
}

class Led extends StatelessWidget {
  const Led(this.color, {super.key, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color,
            boxShadow: [BoxShadow(color: color.withOpacity(0.7), blurRadius: 6)], border: Border.all(color: Colors.black54)),
      );
}

/// Tactile raised key.
class MetalButton extends StatelessWidget {
  const MetalButton(this.label, {super.key, required this.onTap, this.color = Pal.neutral, this.filled = false});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: on ? 1 : 0.4,
        child: Container(
          alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: filled ? [color, color.withOpacity(0.65)] : [const Color(0xFF3A414B), const Color(0xFF20242A)]),
            border: Border.all(color: filled ? color : Pal.edge),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 3)),
                              BoxShadow(color: Color(0x33FFFFFF), blurRadius: 0, offset: Offset(0, -1))],
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(color: filled ? Colors.black : color, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8)),
        ),
      ),
    );
  }
}
