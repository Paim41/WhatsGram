import 'dart:ui';
import 'package:flutter/material.dart';

/// A restrained glass surface used only by settings, with bounded blur.
class SettingsCard extends StatefulWidget {
  const SettingsCard({super.key, required this.child});
  final Widget child;
  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: reducedMotion ? 0 : 180),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .12 : .035),
              blurRadius: hovered ? 24 : 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: AnimatedContainer(
              duration: Duration(milliseconds: reducedMotion ? 0 : 180),
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 20 : 28,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [
                          const Color(0xff223749).withValues(alpha: .88),
                          const Color(0xff17212b).withValues(alpha: .94),
                        ]
                      : [
                          Colors.white.withValues(alpha: .94),
                          const Color(0xffedf7ff).withValues(alpha: .85),
                        ],
                ),
                border: Border.all(
                  color: hovered
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .5)
                      : (dark
                            ? Colors.white.withValues(alpha: .12)
                            : Colors.white),
                ),
              ),
              child: ListTileTheme(
                data: const ListTileThemeData(
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  minVerticalPadding: 12,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsField<T> extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
