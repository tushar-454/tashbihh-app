import 'package:flutter/material.dart';

import '../../app/theme/tasbih_theme.dart';
import '../counter/counter_controller.dart';

class DuaSelector extends StatelessWidget {
  const DuaSelector({
    super.key,
    required this.controller,
    required this.open,
    required this.onTap,
  });
  final CounterController controller;
  final bool open;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Semantics(
      button: true,
      expanded: open,
      label: 'Select a Dua',
      child: Material(
        color: TasbihTheme.soft,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: TasbihTheme.border),
          borderRadius: BorderRadius.circular(13.6),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('dua-selector'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12.8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.dua.arabic,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 16,
                          height: 1.1,
                          color: TasbihTheme.gold,
                        ),
                      ),
                      const SizedBox(height: 3.52),
                      Text(
                        '${c.dua.transliteration} · ${c.target}x',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.2,
                          color: TasbihTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12.8),
                CompletionMark(done: c.completed(c.dua)),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: open ? .5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    '▾',
                    style: TextStyle(color: TasbihTheme.muted, fontSize: 14.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CompletionMark extends StatelessWidget {
  const CompletionMark({super.key, required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) => Semantics(
    label: done ? 'Completed' : 'Incomplete',
    child: Text(
      done ? '✓' : '✗',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        height: 1,
        color: done ? TasbihTheme.success : TasbihTheme.todo,
      ),
    ),
  );
}

class DuaMenu extends StatelessWidget {
  const DuaMenu({
    super.key,
    required this.controller,
    required this.onSelected,
  });
  final CounterController controller;
  final VoidCallback onSelected;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final duas = c.config.forPrayer(c.state.selectedPrayer);
    return Material(
      color: hsl(220, 15, 13, .98),
      elevation: 14,
      shadowColor: hsl(220, 60, 3, .4),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: TasbihTheme.border),
        borderRadius: BorderRadius.circular(13.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: duas.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: TasbihTheme.border.withValues(alpha: .75),
        ),
        itemBuilder: (context, index) {
          final dua = duas[index];
          final selected = c.dua.id == dua.id;
          return Semantics(
            selected: selected,
            button: true,
            child: Ink(
              color: selected
                  ? TasbihTheme.gold.withValues(alpha: .12)
                  : Colors.transparent,
              child: InkWell(
                key: Key('dua-${dua.id}'),
                onTap: () {
                  c.selectDua(dua.id);
                  onSelected();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11.2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dua.arabic,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontFamily: 'Amiri',
                                fontSize: 16,
                                color: TasbihTheme.gold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CompletionMark(done: c.completed(dua)),
                        ],
                      ),
                      const SizedBox(height: 2.4),
                      Text(
                        '${dua.transliteration} - ${dua.meaning}',
                        style: TextStyle(
                          fontSize: 11.84,
                          color: TasbihTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 1.92),
                      Text(
                        'Target: ${dua.target}x',
                        style: TextStyle(
                          fontSize: 10.72,
                          color: TasbihTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
