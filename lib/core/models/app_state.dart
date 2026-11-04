import '../config/tasbih_config.dart';
import '../localization/app_localizations.dart';

enum AppMode { prayer, custom }

enum CounterStyle { classic, modern }

String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Matches JavaScript Math.floor((toMidnight - fromMidnight) / 86400000),
/// including its 23-hour spring-forward and negative-duration behavior.
int elapsedLocalDays(DateTime fromMidnight, DateTime toMidnight) =>
    (toMidnight.difference(fromMidnight).inMilliseconds /
            Duration.millisecondsPerDay)
        .floor();

int localDayDifference(String from, String to) =>
    elapsedLocalDays(DateTime.parse(from), DateTime.parse(to));

int safeInt(dynamic value, int fallback, int min, int max) =>
    value is num && value.isFinite ? value.floor().clamp(min, max) : fallback;

class AppSettings {
  AppSettings({
    this.vibrationIntensity = 40,
    this.language = 'en',
    this.mode = AppMode.prayer,
    this.style = CounterStyle.classic,
  });
  String language;
  int vibrationIntensity;
  AppMode mode;
  CounterStyle style;
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    language: AppLocalizations.supportedLanguage(
      json[AppLocalizations.preferenceKey],
    ),
    vibrationIntensity:
        safeInt(json['vibrationIntensity'], 40, 0, 100) ~/ 5 * 5,
    mode: json['mode'] == 'custom' ? AppMode.custom : AppMode.prayer,
    style: json['style'] == 'modern'
        ? CounterStyle.modern
        : CounterStyle.classic,
  );
  Map<String, dynamic> toJson() => {
    AppLocalizations.preferenceKey: language,
    'vibrationIntensity': vibrationIntensity,
    'mode': mode.name,
    'style': style.name,
  };
}

class PrayerProgress {
  PrayerProgress({
    required this.selectedDuaId,
    Map<String, int>? counts,
    Set<String>? completed,
  }) : counts = counts ?? {},
       completed = completed ?? {};
  String selectedDuaId;
  final Map<String, int> counts;
  final Set<String> completed;
  factory PrayerProgress.empty(TasbihConfig config, String prayer) =>
      PrayerProgress(selectedDuaId: config.forPrayer(prayer).first.id);
  factory PrayerProgress.fromJson(
    TasbihConfig config,
    String prayer,
    Map<String, dynamic> json,
  ) {
    final allowed = config.forPrayer(prayer);
    final counts = <String, int>{};
    final rawCounts = json['counts'] is Map ? json['counts'] as Map : {};
    for (final d in allowed) {
      counts[d.id] = safeInt(rawCounts[d.id], 0, 0, 2147483647);
    }
    final rawCompleted = json['completed'] is List
        ? json['completed'] as List
        : [];
    return PrayerProgress(
      selectedDuaId: allowed.any((d) => d.id == json['selectedDuaId'])
          ? json['selectedDuaId'] as String
          : allowed.first.id,
      counts: counts,
      completed: allowed
          .where(
            (d) => rawCompleted.contains(d.id) && counts[d.id]! >= d.target,
          )
          .map((d) => d.id)
          .toSet(),
    );
  }
  Map<String, dynamic> toJson() => {
    'selectedDuaId': selectedDuaId,
    'counts': counts,
    'completed': completed.toList(),
  };
}

class AppState {
  AppState({
    required this.date,
    required this.selectedPrayer,
    required this.prayers,
    this.customCount = 0,
    this.customTarget = 100,
    this.streak = 0,
    this.lastStreakDate,
    this.restoredDay,
  });
  String date, selectedPrayer;
  Map<String, PrayerProgress> prayers;
  int customCount, customTarget, streak;
  String? lastStreakDate;

  /// Original dated prayer/streak record from the last historical restore.
  Map<String, dynamic>? restoredDay;
  static Map<String, PrayerProgress> emptyPrayers(TasbihConfig config) => {
    for (final p in config.prayers) p.id: PrayerProgress.empty(config, p.id),
  };
  factory AppState.empty(TasbihConfig config, DateTime now) => AppState(
    date: dateKey(now),
    selectedPrayer: config.activePrayer(now) ?? 'fajr',
    prayers: emptyPrayers(config),
  );
  factory AppState.fromJson(TasbihConfig config, Map<String, dynamic> json) {
    final date = json['date'] as String;
    DateTime.parse(date);
    final rawPrayers = json['prayers'] as Map;
    final target = safeInt(json['customTarget'], 100, 1, 1000);
    final lastDate = json['lastStreakDate'];
    return AppState(
      date: date,
      restoredDay: json['restoredDay'] is Map
          ? Map<String, dynamic>.from(json['restoredDay'])
          : null,
      selectedPrayer: config.prayers.any((p) => p.id == json['selectedPrayer'])
          ? json['selectedPrayer'] as String
          : 'fajr',
      prayers: {
        for (final p in config.prayers)
          p.id: PrayerProgress.fromJson(
            config,
            p.id,
            rawPrayers[p.id] is Map
                ? Map<String, dynamic>.from(rawPrayers[p.id])
                : {},
          ),
      },
      customCount: safeInt(json['customCount'], 0, 0, target),
      customTarget: target,
      streak: safeInt(json['streak'], 0, 0, 2147483647),
      lastStreakDate: lastDate is String && DateTime.tryParse(lastDate) != null
          ? lastDate
          : null,
    );
  }
  Map<String, dynamic> toJson() => {
    'date': date,
    'selectedPrayer': selectedPrayer,
    'prayers': {for (final p in prayers.entries) p.key: p.value.toJson()},
    'customCount': customCount,
    'customTarget': customTarget,
    'streak': streak,
    'lastStreakDate': lastStreakDate,
    if (restoredDay != null) 'restoredDay': restoredDay,
  };
}
