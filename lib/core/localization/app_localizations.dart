import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture, mapEquals;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A message keeps its identity and arguments until it reaches the UI. This
/// also lets a pending cloud status change language without another operation.
class AppMessage {
  const AppMessage(this.key, [this.arguments = const {}]);
  const AppMessage.raw(String text) : key = text, arguments = const {};
  final String key;
  final Map<String, Object> arguments;
  String get english => AppLocalizations(const Locale('en')).message(this);

  @override
  bool operator ==(Object other) =>
      other is AppMessage &&
      key == other.key &&
      mapEquals(arguments, other.arguments);
  @override
  int get hashCode => Object.hash(
    key,
    Object.hashAllUnordered(
      arguments.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

class AppLocalizations {
  AppLocalizations(this.locale) : _catalog = _translations;
  @visibleForTesting
  AppLocalizations.fromTranslations(
    this.locale,
    Map<String, Map<String, String>> translations,
  ) : _catalog = translations;
  final Map<String, Map<String, String>> _catalog;
  final Locale locale;
  static const supportedLocales = [Locale('en'), Locale('bn')];
  static const preferenceKey = 'app_language';
  static Map<String, Map<String, String>> _translations = {};
  static Future<void>? _loading;
  static bool _loaded = false;

  /// Shared by startup and the delegate; the asset is decoded once per process.
  static Future<void> load() => _loading ??= _load();
  static Future<void> _load() async {
    final raw = jsonDecode(
      await rootBundle.loadString('assets/localization/translations.json'),
    ) as Map<String, dynamic>;
    _translations = raw.map(
      (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
    );
    _loaded = true;
  }

  static String supportedLanguage(Object? value) => value == 'bn' ? 'bn' : 'en';
  String get fontFamily =>
      locale.languageCode == 'bn' ? 'KohinoorBangla' : 'Comfortaa';

  String tr(String key, [Map<String, Object> arguments = const {}]) {
    final entry = _catalog[key];
    final translated = entry?[locale.languageCode];
    final template = translated == null || translated.isEmpty
        ? (entry?['en'] ?? key)
        : translated;
    return template.replaceAllMapped(RegExp(r'\{([a-zA-Z_][a-zA-Z_0-9]*)\}'), (
      match,
    ) {
      final value = arguments[match[1]];
      return value is AppMessage
          ? message(value)
          : value?.toString() ?? match[0]!;
    });
  }

  String message(AppMessage value) => tr(value.key, value.arguments);
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizations(const Locale('en'));
  static const delegate = _AppLocalizationsDelegate();
}

extension LocalizedContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String tr(String key, [Map<String, Object> arguments = const {}]) =>
      l10n.tr(key, arguments);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['en', 'bn'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations._loaded
      ? SynchronousFuture(AppLocalizations(locale))
      : AppLocalizations.load().then((_) => AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
