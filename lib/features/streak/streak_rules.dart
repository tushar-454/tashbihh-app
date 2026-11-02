import '../../core/config/tasbih_config.dart';
import '../../core/models/app_state.dart';

/// Mirrors applyStreakIfEligible / rollForwardState in the reference script.
class StreakRules {
  static bool evaluate(AppState state, TasbihConfig config, DateTime now) {
    final today = dateKey(now);
    if (state.lastStreakDate == today ||
        !config.prayers.every(
          (p) =>
              state.prayers[p.id]!.completed.length >= config.minimumStreakDuas,
        )) {
      return false;
    }
    state.streak += 1;
    state.lastStreakDate = today;
    return true;
  }

  static bool rollForward(AppState state, TasbihConfig config, DateTime now) {
    final today = dateKey(now);
    var changed = false;
    if (state.date != today) {
      if (state.lastStreakDate != state.date ||
          localDayDifference(state.date, today) != 1) {
        state.streak = 0;
      }
      state.date = today;
      state.prayers = AppState.emptyPrayers(config);
      changed = true;
    }
    return evaluate(state, config, now) || changed;
  }
}
