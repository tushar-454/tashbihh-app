import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tashbihh/app/app.dart';
import 'package:tashbihh/core/backup/cloud_backup_coordinator.dart';
import 'package:tashbihh/core/localization/app_localizations.dart';
import 'package:tashbihh/core/models/app_state.dart';
import 'package:tashbihh/core/storage/progress_repository.dart';
import 'package:tashbihh/features/counter/counter_controller.dart';
import 'package:tashbihh/features/counter/counter_screen.dart';
import 'package:tashbihh/features/settings/settings_panel.dart';

import 'cloud_backup_support.dart';
import 'test_support.dart';

void main() {
  final en = AppLocalizations(const Locale('en'));
  final bn = AppLocalizations(const Locale('bn'));

  test(
    'catalog is complete, has exactly two languages and matching placeholders',
    () {
      final catalog = jsonDecode(
        File('assets/localization/translations.json').readAsStringSync(),
      ) as Map;
      Set<String> placeholders(String text) =>
          RegExp(r'\{([a-zA-Z_][a-zA-Z_0-9]*)\}')
              .allMatches(text)
              .map((m) => m[1]!)
              .toSet();
      for (final entry in catalog.entries) {
        final values = entry.value as Map;
        expect(values.keys.toSet(), {'en', 'bn'}, reason: entry.key);
        expect(values['en'], isNotEmpty, reason: entry.key);
        expect(values['bn'], isNotEmpty, reason: entry.key);
        expect(
          placeholders(values['en']),
          placeholders(values['bn']),
          reason: entry.key,
        );
      }
      final config = testConfig();
      for (final prayer in config.prayers) {
        expect(catalog, contains('prayer_${prayer.id}'));
      }
      for (final dhikr in config.duas) {
        for (final prefix in ['dhikr', 'meaning', 'arabic']) {
          expect(catalog, contains('${prefix}_${dhikr.id}'));
        }
      }
    },
  );

  test(
    'catalog load is cached and missing Bangla falls back to English',
    () async {
      expect(
        identical(AppLocalizations.load(), AppLocalizations.load()),
        isTrue,
      );
      final partial = AppLocalizations.fromTranslations(const Locale('bn'), {
        'missing': {'en': 'English fallback'},
        'empty': {'en': 'Empty fallback', 'bn': ''},
      });
      expect(partial.tr('missing'), 'English fallback');
      expect(partial.tr('empty'), 'Empty fallback');
      expect(partial.tr('unknown'), 'unknown');
    },
  );

  test('placeholders support dates, counts and nested localized messages', () {
    expect(en.tr('counter_value', {'count': 4, 'target': 33}), '4 of 33');
    expect(bn.tr('counter_value', {'count': 4, 'target': 33}), '33 এর মধ্যে 4');
    expect(
      bn.tr('checking_account', {'email': 'me@example.com'}),
      contains('me@example.com'),
    );
    expect(
      bn.message(
        const AppMessage('prayer_sync_error', {
          'fallback': AppMessage('using_saved', {'date': '2026-11-04'}),
        }),
      ),
      contains('2026-11-04'),
    );
    expect(en.tr('counter_value', {'count': 4}), '4 of {target}');
    expect(
      en.tr('checking_account', {'email': r'$literal{count}'}),
      contains(r'$literal{count}'),
    );
  });

  group('local language persistence', () {
    test('new installation and old snapshots default to English', () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      final (_, fresh) = await h.repository.load(h.config, h.now);
      expect(fresh.language, 'en');
      final old = jsonDecode(
        h.repository.encode(h.controller.state, h.controller.settings),
      );
      (old['settings'] as Map).remove('app_language');
      h.store.value = jsonEncode(old);
      final (_, upgraded) = await h.repository.load(h.config, h.now);
      expect(upgraded.language, 'en');
    });

    test('Bangla survives new repository/controller with existing SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final h = Harness();
      addTearDown(h.controller.dispose);
      final repository = ProgressRepository(PreferencesStore(preferences));
      final c = CounterController(
        config: h.config,
        repository: repository,
        state: AppState.empty(h.config, h.now),
        settings: AppSettings(),
        clock: () => h.now,
      );
      c.increment();
      final progress = jsonEncode(
        AppState.fromJson(h.config, c.state.toJson()).toJson(),
      );
      c.setLanguage('bn');
      await c.flush();
      c.dispose();
      await preferences.reload();
      final restartedRepository = ProgressRepository(
        PreferencesStore(preferences),
      );
      final (state, settings) = await restartedRepository.load(h.config, h.now);
      final restarted = CounterController(
        config: h.config,
        repository: restartedRepository,
        state: state,
        settings: settings,
        clock: () => h.now,
      );
      addTearDown(restarted.dispose);
      expect(restarted.settings.language, 'bn');
      expect(jsonEncode(restarted.state.toJson()), progress);
      expect(
        jsonDecode(
          preferences.getString(PreferencesStore.key)!,
        )['settings']['app_language'],
        'bn',
      );
    });

    test('language changes do not mutate prayers, targets, streak or cloud identity', () async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      h.controller.increment();
      h.repository.cloudMetadata = {'accountId': 'a', 'email': 'a@example.com'};
      final before = jsonEncode(h.controller.state.toJson());
      h.controller.setLanguage('bn');
      await h.controller.flush();
      expect(jsonEncode(h.controller.state.toJson()), before);
      expect(h.repository.cloudMetadata['accountId'], 'a');
      final writes = h.store.writes.length;
      var changes = 0;
      h.controller.addListener(() => changes++);
      h.controller.setLanguage('bn');
      await h.controller.flush();
      expect(changes, 0);
      expect(h.store.writes.length, writes);
      h.controller.resetCounter();
      expect(h.controller.settings.language, 'bn');
      await h.controller.resetAll();
      expect(h.controller.settings.language, 'bn');
      final (_, saved) = await h.repository.load(h.config, h.now);
      expect(saved.language, 'bn');
    });

    test('invalid local language safely falls back to English', () {
      for (final value in [
        null,
        'ar',
        '',
        'BN',
        4,
        {},
        ['bn'],
      ]) {
        expect(AppSettings.fromJson({'app_language': value}).language, 'en');
      }
    });

    test(
      'storage failure is reported in the active language and can recover',
      () async {
        final h = Harness();
        addTearDown(h.controller.dispose);
        h.store.fail = true;
        h.controller.setLanguage('bn');
        await h.controller.flush();
        expect(
          bn.message(h.controller.storageMessage!),
          bn.tr('progress_save_failed'),
        );
        h.store.fail = false;
        h.controller.setLanguage('en');
        await h.controller.flush();
        expect(h.controller.storageError, isNull);
      },
    );
  });

  group('existing Drive backup format', () {
    late Harness h;
    late FakeAuth auth;
    late CloudBackupCoordinator cloud;
    setUp(() {
      h = Harness();
      auth = FakeAuth();
      cloud = CloudBackupCoordinator(controller: h.controller, auth: auth);
    });
    tearDown(() {
      cloud.dispose();
      h.controller.dispose();
    });

    test('each new backup includes language in settings and retains schema versions', () async {
      h.controller.increment();
      h.controller.setLanguage('bn');
      await cloud.connect();
      final wrapped = jsonDecode(utf8.decode(auth.drives['a']!.bytes!));
      expect(wrapped['schemaVersion'], 1);
      final payload = jsonDecode(utf8.decode(base64Decode(wrapped['payload'])));
      expect(payload['schemaVersion'], 1);
      expect(payload['data']['settings']['app_language'], 'bn');
      expect(
        payload['data']['state']['prayers']['fajr']['counts']['subhanallah'],
        1,
      );
      h.controller.setLanguage('en');
      await cloud.backupNow();
      expect(
        cloud.format.validate(auth.drives['a']!.bytes!).settings.language,
        'en',
      );
      final uploads = auth.drives['a']!.uploads;
      h.controller.setLanguage('en');
      await h.controller.flush();
      expect(auth.drives['a']!.uploads, uploads);
      expect(auth.choices, 1);
    });

    for (final value in [
      'bn',
      'en',
      'xx',
      '',
      null,
      10,
      {'unexpected': true},
    ]) {
      test('restore optional language value $value safely', () async {
        h.controller.setLanguage('bn');
        final root = jsonDecode(
          utf8.decode(
            cloud.format.serializer.export(
              h.controller.state,
              h.controller.settings,
              h.now,
            ),
          ),
        );
        root['data']['settings']['app_language'] = value;
        auth.drives['a']!.bytes = cloud.format.wrap(
          utf8.encode(jsonEncode(root)),
          h.now,
        );
        await cloud.connect();
        expect(h.controller.settings.language, value == 'bn' ? 'bn' : 'en');
        final (_, saved) = await h.repository.load(h.config, h.now);
        expect(saved.language, h.controller.settings.language);
      });
    }

    test(
      'legacy backup and legacy account switch preserve local language',
      () async {
        h.controller.increment();
        final root = jsonDecode(
          utf8.decode(
            cloud.format.serializer.export(
              h.controller.state,
              h.controller.settings,
              h.now,
            ),
          ),
        );
        (root['data']['settings'] as Map).remove('app_language');
        auth.drives['a']!.bytes = cloud.format.wrap(
          utf8.encode(jsonEncode(root)),
          h.now,
        );
        h.controller.setLanguage('bn');
        await cloud.connect();
        expect(h.controller.settings.language, 'bn');
        expect(h.controller.count, 1);
        auth.chosen = FakeAuth.b;
        auth.drives['b']!.bytes = auth.drives['a']!.bytes;
        await cloud.connect();
        expect(h.controller.settings.language, 'bn');
        expect(cloud.account!.id, 'b');
      },
    );

    test('failed restore leaves language and data unchanged', () async {
      h.controller.setLanguage('bn');
      h.controller.increment();
      await h.controller.flush();
      final before = jsonEncode(h.controller.state.toJson());
      final settings = AppSettings(language: 'en');
      final candidate = cloud.format.serializer.validate(
        cloud.format.serializer.export(h.controller.state, settings, h.now),
      );
      h.store.fail = true;
      await expectLater(h.controller.restore(candidate), throwsStateError);
      expect(h.controller.settings.language, 'bn');
      expect(jsonEncode(h.controller.state.toJson()), before);
    });

    test(
      'close backup includes changed language without extra sign-in prompts',
      () async {
        await cloud.connect();
        cloud.resume();
        h.controller.setLanguage('bn');
        h.controller.setLanguage('bn');
        cloud.suspend();
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(auth.drives['a']!.uploads, 2);
        expect(
          cloud.format.validate(auth.drives['a']!.bytes!).settings.language,
          'bn',
        );
        expect(auth.choices, 1);
      },
    );
  });

  group('live localized widgets and real bundled fonts', () {
    setUpAll(() async {
      for (final entry in {
        'Comfortaa': 'Comfortaa.ttf',
        'KohinoorBangla': 'KohinoorBangla.ttf',
        'Amiri': 'Amiri-Regular.ttf',
        'Tasbih Symbols': 'TasbihSymbols.ttf',
        'Tasbih Emoji': 'TasbihEmoji.ttf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
        await loader.load();
      }
    });

    Future<Harness> launch(
      WidgetTester tester, {
      String language = 'en',
      Size size = const Size(390, 844),
      double scale = 1,
    }) async {
      final h = Harness();
      final device = TestDevice();
      h.controller.settings.language = language;
      addTearDown(h.controller.dispose);
      addTearDown(device.dispose);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        TasbihApp(controller: h.controller, device: device),
      );
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets(
      'new install ignores Bangla device locale and uses English/Comfortaa',
      (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('bn');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        await launch(tester);
        expect(find.text('TASBIH COUNTER'), findsOneWidget);
        final context = tester.element(find.byKey(const Key('count-value')));
        expect(Localizations.localeOf(context), const Locale('en'));
        expect(DefaultTextStyle.of(context).style.fontFamily, 'Comfortaa');
      },
    );

    testWidgets('saved Bangla is shown on first UI frame with KohinoorBangla', (
      tester,
    ) async {
      await launch(tester, language: 'bn');
      expect(find.text('তাসবিহ কাউন্টার'), findsOneWidget);
      expect(find.text('TASBIH COUNTER'), findsNothing);
      final context = tester.element(find.byKey(const Key('count-value')));
      expect(Localizations.localeOf(context), const Locale('bn'));
      expect(DefaultTextStyle.of(context).style.fontFamily, 'KohinoorBangla');
    });

    testWidgets(
      'badges switch text/fonts immediately, preserve screen and selection',
      (tester) async {
        final h = await launch(tester);
        h.controller.increment();
        await tester.pumpAndSettle();
        final screen = tester.state(find.byType(CounterScreen));
        await tester.tap(find.byKey(const Key('settings-toggle')));
        await tester.pumpAndSettle();
        bool selected(String code) => tester
            .widget<Semantics>(find.byKey(Key('language-$code')))
            .properties
            .selected!;
        expect(selected('en'), isTrue);
        expect(selected('bn'), isFalse);
        expect(find.text('EN'), findsOneWidget);
        expect(find.text('বাং'), findsOneWidget);
        final badgeButton = tester.widget<OutlinedButton>(
          find.descendant(
            of: find.byKey(const Key('language-bn')),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(
          badgeButton.style!.textStyle!.resolve({})!.fontFamilyFallback,
          contains('KohinoorBangla'),
        );
        await tester.tap(find.byKey(const Key('language-bn')));
        await tester.pumpAndSettle();
        expect(find.text('সেটিংস'), findsOneWidget);
        expect(find.text('নামাজের মোড'), findsNothing);
        expect(find.text('নিজস্ব মোড'), findsOneWidget);
        expect(selected('en'), isFalse);
        expect(selected('bn'), isTrue);
        expect(
          tester
              .widget<Semantics>(find.byKey(const Key('language-bn')))
              .properties
              .onTap,
          isNotNull,
        );
        expect(tester.state(find.byType(CounterScreen)), same(screen));
        expect(h.controller.count, 1);
        final context = tester.element(find.byKey(const Key('count-value')));
        expect(DefaultTextStyle.of(context).style.fontFamily, 'KohinoorBangla');
        await tester.tap(find.byKey(const Key('language-en')));
        await tester.pumpAndSettle();
        expect(find.text('SETTINGS'), findsOneWidget);
        expect(selected('en'), isTrue);
        expect(DefaultTextStyle.of(context).style.fontFamily, 'Comfortaa');
        expect(tester.takeException(), isNull);
      },
    );

    for (final size in [
      const Size(280, 568),
      const Size(390, 844),
      const Size(844, 390),
      const Size(1440, 900),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Bangla has no overflow at $size, text scale $scale', (
          tester,
        ) async {
          final h = await launch(
            tester,
            language: 'bn',
            size: size,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('dua-selector')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tapAt(const Offset(2, 200));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('settings-toggle')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final enBadge = tester.getRect(find.byKey(const Key('language-en')));
          final bnBadge = tester.getRect(find.byKey(const Key('language-bn')));
          expect(enBadge.center.dy, bnBadge.center.dy);
          await tester.ensureVisible(find.byKey(const Key('reset-all')));
          await tester.tap(find.byKey(const Key('reset-all')));
          await tester.pumpAndSettle();
          expect(find.text('সব তথ্য রিসেট করবেন?'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('reset-cancel')));
          await tester.pumpAndSettle();
          expect(h.controller.settings.language, 'bn');
        });
      }
    }

    testWidgets(
      'active backup status retranslates without restarting a cloud operation',
      (tester) async {
        final h = Harness();
        final device = TestDevice();
        final auth = FakeAuth();
        final cloud = CloudBackupCoordinator(
          controller: h.controller,
          auth: auth,
        );
        addTearDown(cloud.dispose);
        addTearDown(h.controller.dispose);
        addTearDown(device.dispose);
        await cloud.connect();
        await tester.pumpWidget(
          TasbihApp(controller: h.controller, device: device, backup: cloud),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-toggle')));
        await tester.pumpAndSettle();
        h.controller.setLanguage('bn');
        await tester.pumpAndSettle();
        expect(
          find.text(bn.tr('backup_connected', {'email': 'a@example.com'})),
          findsOneWidget,
        );
        expect(auth.drives['a']!.uploads, 1);
        expect(auth.choices, 1);
        expect(find.byType(SettingsPanel), findsOneWidget);
      },
    );
  });
}
