import 'package:flutter/material.dart';

import '../../app/theme/tasbih_theme.dart';
import '../counter/counter_controller.dart';

class PrayerSelector extends StatelessWidget {
  const PrayerSelector({super.key, required this.controller});
  final CounterController controller;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 400),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9.6),
      child: Row(
        children: [
          for (var i = 0; i < controller.config.prayers.length; i++) ...[
            if (i > 0) const SizedBox(width: 7.2),
            Expanded(child: _tile(context, i)),
          ],
        ],
      ),
    ),
  );
  Widget _tile(BuildContext context, int index) {
    final c = controller;
    final p = c.config.prayers[index];
    final selected = c.state.selectedPrayer == p.id;
    final enabled = c.canSelect(p.id);
    final locked = p.isLocked(c.now);
    return Tooltip(
      message:
          '${p.label} · ${p.arabic}\n${p.windowLabel}${locked ? ' · Locked' : ''}',
      child: Semantics(
        selected: selected,
        button: true,
        enabled: enabled,
        label:
            '${p.label}, ${p.arabic}, ${p.windowLabel}${locked ? ', locked' : ''}',
        excludeSemantics: true,
        child: Opacity(
          opacity: enabled ? 1 : .45,
          child: Material(
            color: selected
                ? TasbihTheme.gold.withValues(alpha: .14)
                : hsl(220, 15, 18, .55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.8),
              side: BorderSide(
                color: selected
                    ? TasbihTheme.gold.withValues(alpha: .34)
                    : Colors.transparent,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.8),
                border: locked ? Border.all(color: hsl(0, 70, 62, .4)) : null,
              ),
              child: InkWell(
                key: Key('prayer-${p.id}'),
                onTap: () {
                  if (enabled) c.selectPrayer(p.id);
                },
                borderRadius: BorderRadius.circular(12.8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 2,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.icon,
                          style: const TextStyle(fontSize: 16, height: 1.2),
                        ),
                        const SizedBox(height: 3.2),
                        Text(
                          p.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.92,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? TasbihTheme.gold
                                : TasbihTheme.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
