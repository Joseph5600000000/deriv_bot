import 'package:flutter/material.dart';

/// Light, warm "cream + deep green + lime" palette. Legacy names (text, dim, lcd, edge, ...) are kept as aliases
/// so existing widgets keep working.
class Pal {
  static const bg = Color(0xFFEAE7E0), card = Color(0xFFF6F4EF), line = Color(0xFFD9D5CC);
  static const deep = Color(0xFF0B2B1D), deep2 = Color(0xFF133B28), surface = Color(0xFF1E4A34);
  static const lime = Color(0xFFD6F55C), ink = Color(0xFF14231A), inkDim = Color(0xFF5E6D63);
  static const onDeep = Color(0xFFF2F5EE), onDeepDim = Color(0xFFA3BBAA);
  static const green = Color(0xFF7BE8A8), red = Color(0xFFFF8F85), amber = Color(0xFFFFD36B), neutral = Color(0xFFB4C4B9);
  static const greyCard = Color(0xFFD7D8D2), greyInk = Color(0xFF7C857F);
  // legacy aliases
  static const text = onDeep, dim = onDeepDim, lcd = surface, edge = Color(0x33FFFFFF), metalTop = deep2, metalBot = deep;
}

const TextStyle kMono = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Page heading on the cream background.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle(this.title, {super.key, this.sub, this.trailing});
  final String title;
  final String? sub;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Pal.ink, fontSize: 32, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -0.5)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub!, style: const TextStyle(color: Pal.inkDim, fontSize: 13))),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Deep-green rounded card with a soft shadow.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Pal.deep2, Pal.deep]),
          boxShadow: const [BoxShadow(color: Color(0x330B2B1D), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(color: Pal.onDeepDim, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Muted-green value tile.
class Lcd extends StatelessWidget {
  const Lcd(this.label, this.value, {super.key, this.color = Pal.onDeep, this.size = 20, this.sub});
  final String label, value;
  final String? sub;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: Pal.onDeepDim, fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Text(value, style: kMono.copyWith(color: color, fontSize: size, fontWeight: FontWeight.w700))),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(color: Pal.onDeepDim, fontSize: 9.5))),
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
        decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 5)]),
      );
}

/// Pill button. filled => accent background with dark text; otherwise muted-green with light text.
class MetalButton extends StatelessWidget {
  const MetalButton(this.label, {super.key, required this.onTap, this.color = Pal.lime, this.filled = false});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final bg = filled ? color : Pal.surface;
    final fg = filled ? Pal.deep : (color == Pal.lime ? Pal.onDeep : color);
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: Material(
        color: bg, borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40), onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Center(child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.4))),
          ),
        ),
      ),
    );
  }
}

/// Small rounded status pill.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg = Pal.lime, this.fg = Pal.deep});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      );
}

/// Input style used inside deep-green panels.
InputDecoration fieldDecoration(String label, {String? hint, Widget? suffix}) => InputDecoration(
      labelText: label, hintText: hint, isDense: true, filled: true, fillColor: Pal.surface, suffixIcon: suffix,
      labelStyle: const TextStyle(color: Pal.onDeepDim, fontSize: 13), hintStyle: const TextStyle(color: Pal.onDeepDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Pal.lime, width: 1.5)),
    );

/// Rounded segmented selector for use inside panels.
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<String> options;
  final int value;
  final void Function(int) onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: i == value ? Pal.lime : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                child: Text(options[i], style: TextStyle(color: i == value ? Pal.deep : Pal.onDeep, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ),
        ]),
      );
}
