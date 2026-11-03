import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/backup/backup_service.dart';
import '../../core/platform/backup_documents.dart';

import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../../app/theme/tasbih_theme.dart';
import '../../core/models/app_state.dart';
import '../../core/platform/device_services.dart';
import '../../core/widgets/panel_enter.dart';
import '../dhikr/dua_selector.dart';
import '../prayer/prayer_selector.dart';
import '../settings/settings_panel.dart';
import 'counter_controller.dart';
import 'counter_ring.dart';

class CounterScreen extends StatefulWidget {
  const CounterScreen({
    super.key,
    required this.controller,
    required this.device,
  });
  final CounterController controller;
  final DeviceServices device;
  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _duaOpen = false, _settingsOpen = false;
  bool _backupBusy = false;
  bool _backupPreview = false;
  StreamSubscription<dynamic>? _clockEvents;
  final _documents = BackupDocuments();
  final _duaLink = LayerLink();
  late final AnimationController _pulse;
  CounterController get c => widget.controller;
  int _lastCount = 0;
  String? _lastPrayerMessage;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _lastCount = c.count;
    c.addListener(_changed);
    widget.device.addListener(_deviceChanged);
    WidgetsBinding.instance.addObserver(this);
    c.startClock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (mounted &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        c.prayerTimes?.resume(_explainLocation);
      }
    });
    _clockEvents = widget.device.clockChanges.listen((_) {
      c.prayerTimes?.clockChanged();
      c.refresh();
    }, onError: (Object _) {});
  }

  void _changed() {
    if (!mounted) return;
    if (c.count != _lastCount &&
        c.done &&
        !MediaQuery.of(context).disableAnimations) {
      _pulse.forward(from: 0);
    }
    _lastCount = c.count;
    final message = c.prayerTimes?.message;
    if (message != null && message != _lastPrayerMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _message(message);
      });
    }
    _lastPrayerMessage = message;
    setState(() {});
  }

  Future<bool> _explainLocation() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Local prayer times'),
            content: const Text(
              'Tasbih uses your location while the app is open to get today’s prayer times from AlAdhan. Only the coordinates used for the latest schedule are saved. Your location is never tracked in the background. You can continue with configured prayer times without granting access.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Use configured times'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _deviceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.startClock();
      c.prayerTimes?.resume(_explainLocation);
    } else {
      c.stopClock();
      c.prayerTimes?.suspend();
      widget.device.cancelFeedback();
      unawaited(c.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.stopClock();
    c.prayerTimes?.suspend();
    unawaited(_clockEvents?.cancel());
    c.removeListener(_changed);
    widget.device.removeListener(_deviceChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _count() {
    if (c.increment()) {
      unawaited(
        widget.device.feedback(
          c.settings.vibrationIntensity,
          completed: c.done,
        ),
      );
    }
  }

  void _close() {
    setState(() {
      _duaOpen = false;
      _settingsOpen = false;
    });
  }

  Future<void> _backup({required bool importing}) async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      final serializer = BackupSerializer(c.config);
      if (importing) {
        final bytes = await _documents.open();
        if (bytes == null || !mounted) return;
        final backup = serializer.validate(bytes);
        final saved = backup.state(c.config);
        final settings = backup.settings;
        final prayerSummary = c.config.prayers
            .map((p) {
              final progress = saved.prayers[p.id]!;
              return '${p.label}: ${progress.counts.values.fold<int>(0, (a, b) => a + b)} counts, ${progress.completed.length} completed';
            })
            .join('\n');
        if (!mounted) return;
        setState(() => _backupPreview = true);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: hsl(220, 15, 14, .98),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.4),
              side: BorderSide(color: TasbihTheme.border),
            ),
            title: Text(
              'Restore backup?',
              style: TextStyle(fontFamily: 'Amiri', color: TasbihTheme.gold),
            ),
            content: SingleChildScrollView(
              child: Text(
                'Backup: ${backup.exportedAt.toLocal()}\n'
                'Prayer progress date: ${saved.date}\n$prayerSummary\n\n'
                'Streak: ${saved.streak} · Last successful day: ${saved.lastStreakDate ?? "None"}\n'
                'Custom Mode: ${saved.customCount} / ${saved.customTarget}\n'
                'Settings: ${settings.mode.name} mode, ${settings.style.name} counter, vibration ${settings.vibrationIntensity}ms.\n\n'
                'Older prayer progress stays attached to its original date. Today’s counters and streak follow daily reset rules.\n\n'
                'Restoring this backup will replace your current saved progress and settings.',
                style: TextStyle(
                  color: TasbihTheme.muted,
                  fontSize: 12.8,
                  height: 1.45,
                ),
              ),
            ),
            actions: [
              SettingsAction(
                key: const Key('import-cancel'),
                label: 'Cancel',
                onPressed: () => Navigator.pop(context, false),
              ),
              SettingsAction(
                key: const Key('import-confirm'),
                label: 'Restore',
                danger: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
        if (mounted) setState(() => _backupPreview = false);
        if (confirmed != true || !mounted) return;
        await c.restore(backup);
        _message('Backup restored successfully.');
      } else {
        c.refresh(autoSelect: false);
        final now = c.clock();
        String pad(int v) => v.toString().padLeft(2, '0');
        final filename =
            'tasbih-backup-${now.year}-${pad(now.month)}-${pad(now.day)}-${pad(now.hour)}-${pad(now.minute)}.json';
        final bytes = serializer.export(c.state, c.settings, now);
        final saved = await _documents.save(filename, bytes);
        if (saved) _message('Backup saved successfully.');
      }
    } on BackupException catch (e) {
      _message(e.message);
    } on PlatformException catch (e) {
      _message(
        e.message ?? 'Could not access this document. Please try again.',
      );
    } on MissingPluginException {
      _message('Backup file picking is available in the Android app.');
    } catch (e) {
      _message('Backup operation failed. $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetDialog() async {
    _close();
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss reset confirmation',
      barrierColor: hsl(220, 30, 5, .58),
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, animation, secondary, child) =>
          FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
      pageBuilder: (context, _, _) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: hsl(220, 15, 14, .98),
                      border: Border.all(color: TasbihTheme.border),
                      borderRadius: BorderRadius.circular(14.4),
                      boxShadow: [
                        BoxShadow(
                          color: hsl(220, 60, 2, .55),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Semantics(
                      namesRoute: true,
                      label: 'Reset all data?',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Reset all data?',
                            style: TextStyle(
                              fontFamily: 'Amiri',
                              fontSize: 21.6,
                              height: 1.2,
                              color: TasbihTheme.gold,
                            ),
                          ),
                          const SizedBox(height: 9.6),
                          Text(
                            'This will permanently remove saved progress, daily prayer counts, and streak data.',
                            style: TextStyle(
                              color: TasbihTheme.muted,
                              fontSize: 12.8,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SettingsAction(
                                  key: const Key('reset-cancel'),
                                  label: 'Cancel',
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SettingsAction(
                                  key: const Key('reset-confirm'),
                                  label: 'Delete',
                                  danger: true,
                                  onPressed: () => Navigator.pop(context, true),
                                ),
                              ),
                            ],
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
      ),
    );
    if (confirmed == true) {
      widget.device.cancelFeedback();
      await c.resetAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final narrow = media.size.width <= 440;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: AnimatedContainer(
            duration: media.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 550),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: TasbihTheme.gradients[c.state.selectedPrayer]!,
              ),
            ),
            child: SafeArea(
              child: PanelEnter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final selectorWidth = math.min(460.0, width - 16) - 32;
                    final badgeWidth = narrow ? 88.0 : 96.0;
                    final menuWidth = math.max(
                      80.0,
                      selectorWidth - badgeWidth - 8,
                    );
                    final textScale = media.textScaler.scale(12) / 12;
                    final minHeight = math.max(
                      540.0,
                      510.0 + math.max(0.0, textScale - 1) * 130.0,
                    );
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            excludeFromSemantics: true,
                            onTap: _count,
                            child: SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: SizedBox(
                                  height: math.max(
                                    constraints.maxHeight,
                                    minHeight,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      8,
                                      narrow ? 16 : 24,
                                      8,
                                      24,
                                    ),
                                    child: Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6.4,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'بِسْمِ اللَّهِ',
                                                textDirection:
                                                    TextDirection.rtl,
                                                style: TextStyle(
                                                  fontFamily: 'Amiri',
                                                  fontSize: 26.4,
                                                  height: 1.8,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: .528,
                                                  color: TasbihTheme.gold,
                                                ),
                                              ),
                                              const SizedBox(height: 3.2),
                                              Text(
                                                'TASBIH COUNTER',
                                                style: TextStyle(
                                                  fontSize: 10.24,
                                                  letterSpacing: 2.048,
                                                  color: TasbihTheme.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 460,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            child: IntrinsicHeight(
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Expanded(
                                                    child:
                                                        CompositedTransformTarget(
                                                          link: _duaLink,
                                                          child: DuaSelector(
                                                            controller: c,
                                                            open: _duaOpen,
                                                            onTap: () {
                                                              setState(() {
                                                                _duaOpen =
                                                                    !_duaOpen;
                                                                _settingsOpen =
                                                                    false;
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Semantics(
                                                    label:
                                                        'Streak: ${c.state.streak} days',
                                                    excludeSemantics: true,
                                                    child: Container(
                                                      width: badgeWidth,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 7.2,
                                                            vertical: 9.6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: TasbihTheme.gold
                                                            .withValues(
                                                              alpha: .15,
                                                            ),
                                                        border: Border.all(
                                                          color: TasbihTheme
                                                              .gold
                                                              .withValues(
                                                                alpha: .35,
                                                              ),
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              13.6,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          const Text(
                                                            '🔥',
                                                            style: TextStyle(
                                                              fontSize: 19.2,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 5.6,
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              '${c.state.streak}',
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color:
                                                                    TasbihTheme
                                                                        .gold,
                                                                fontSize: 17.6,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                height: 1,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4.8),
                                        Expanded(
                                          child: Center(
                                            child: LayoutBuilder(
                                              builder: (context, box) =>
                                                  _counter(
                                                    context,
                                                    width,
                                                    box.maxHeight,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            narrow ? 20.8 : 32,
                                            0,
                                            narrow ? 20.8 : 32,
                                            14.4,
                                          ),
                                          child: Text(
                                            '"${c.dua.meaning}"',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: TasbihTheme.muted,
                                              fontSize: 11.68,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                        if (!c.isCustom)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Text(
                                              c.activePrayer == null
                                                  ? 'Not available at this time'
                                                  : '${c.config.prayer(c.activePrayer!).label} · Available now',
                                              key: const Key('prayer-status'),
                                              style: TextStyle(
                                                fontSize: 10.4,
                                                color: c.activePrayer == null
                                                    ? TasbihTheme.muted
                                                    : TasbihTheme.gold,
                                              ),
                                            ),
                                          ),
                                        PrayerSelector(controller: c),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (c.storageError != null)
                          Positioned(
                            left: 24,
                            right: 64,
                            bottom: 100,
                            child: Material(
                              color: TasbihTheme.card,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  c.storageError!,
                                  style: TextStyle(
                                    color: TasbihTheme.danger,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_duaOpen || _settingsOpen)
                          Positioned.fill(
                            child: GestureDetector(
                              key: const Key('menu-barrier'),
                              excludeFromSemantics: true,
                              behavior: HitTestBehavior.opaque,
                              onTap: _close,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        if (_duaOpen)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: CompositedTransformFollower(
                              link: _duaLink,
                              showWhenUnlinked: false,
                              targetAnchor: Alignment.bottomLeft,
                              followerAnchor: Alignment.topLeft,
                              offset: const Offset(0, 5.6),
                              child: SizedBox(
                                width: menuWidth,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: math.min(
                                      260,
                                      constraints.maxHeight * .45,
                                    ),
                                  ),
                                  child: DuaMenu(
                                    controller: c,
                                    onSelected: _close,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: narrow ? 10.4 : 16,
                          bottom: narrow ? 16 : 22.4,
                          child: Semantics(
                            button: true,
                            expanded: _settingsOpen,
                            label: 'Open settings',
                            child: IconButton(
                              key: const Key('settings-toggle'),
                              onPressed: () {
                                setState(() {
                                  _settingsOpen = !_settingsOpen;
                                  _duaOpen = false;
                                });
                              },
                              tooltip: 'Settings',
                              style: IconButton.styleFrom(
                                backgroundColor: hsl(220, 15, 18, .82),
                                foregroundColor: TasbihTheme.muted,
                                side: BorderSide(color: TasbihTheme.border),
                                minimumSize: const Size(40, 40),
                                fixedSize: const Size(40, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        if (_settingsOpen)
                          Positioned(
                            right: narrow ? 10.4 : 16,
                            bottom: (narrow ? 16 : 22.4) + 50,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.min(245, width - 24),
                                maxHeight: math.min(
                                  620,
                                  constraints.maxHeight * .76,
                                ),
                              ),
                              child: SettingsPanel(
                                controller: c,
                                device: widget.device,
                                onReset: _resetDialog,
                                onExport: () => _backup(importing: false),
                                onImport: () => _backup(importing: true),
                                backupBusy: _backupBusy,
                                backupLoading: _backupBusy && !_backupPreview,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _counter(BuildContext context, double width, double availableHeight) {
    final ringSize = math.min(math.min(width * .88, 360.0), availableHeight);
    final centerSize = math.min(width * .38, 140.0);
    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: c.count.toDouble()),
            duration:
                c.settings.style == CounterStyle.modern &&
                    !MediaQuery.of(context).disableAnimations
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            builder: (context, count, _) => CustomPaint(
              size: Size.square(ringSize),
              painter: CounterRing(
                count: count,
                target: c.target,
                style: c.settings.style,
              ),
            ),
          ),
          if (c.done)
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      TasbihTheme.glows[c.state.selectedPrayer]!,
                      Colors.transparent,
                    ],
                    stops: const [0, .7],
                  ),
                ),
              ),
            ),
          Tooltip(
            message: c.counterHint,
            child: Semantics(
              button: true,
              liveRegion: true,
              label: 'Tasbih counter',
              enabled: c.canCount,
              customSemanticsActions: (c.isCustom || !c.done)
                  ? {
                      const CustomSemanticsAction(label: 'Reset counter'):
                          c.resetCounter,
                    }
                  : null,
              value: '${c.count} of ${c.target}',
              hint: c.counterHint,
              onTap: _count,
              child: FocusableActionDetector(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      _count();
                      return null;
                    },
                  ),
                },
                child: GestureDetector(
                  key: const Key('counter-center'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _count,
                  onDoubleTap: () {
                    widget.device.cancelFeedback();
                    c.resetCounter();
                  },
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) => Transform.scale(
                      scale: 1 + .08 * math.sin(_pulse.value * math.pi),
                      child: child,
                    ),
                    child: Container(
                      width: centerSize,
                      height: centerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: TasbihTheme.border, width: 2),
                        color: TasbihTheme.card,
                      ),
                      child: Center(
                        child: Text(
                          '${c.count}',
                          key: const Key('count-value'),
                          style: TextStyle(
                            fontFamily: 'Amiri',
                            color: c.isCustom || c.canCount || c.done
                                ? TasbihTheme.gold
                                : TasbihTheme.muted,
                            fontSize: (width * .11).clamp(41.6, 57.6),
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
