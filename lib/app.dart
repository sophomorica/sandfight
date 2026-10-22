import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_floor.dart';
import 'draw/race.dart';
import 'features/home/home_screen.dart';
import 'features/home/search_screen.dart';
import 'features/match/match_screen.dart';
import 'features/race/race_screen.dart';
import 'features/result/result_screen.dart';
import 'features/zen/carve_screen.dart';
import 'game/rules.dart';
import 'game/throw_ray.dart';
import 'haptic_player.dart';
import 'net/ble_session.dart';
import 'net/join.dart';
import 'net/pipe.dart';
import 'net/session.dart';
import 'net/uwb_pose.dart';
import 'telemetry/aim_log.dart';
import 'telemetry/crash_reporting.dart';
import 'telemetry/device_log.dart';
import 'telemetry/game_watch.dart';
import 'theme/palette.dart';

enum SeekFor { bury, race }

sealed class Activity {
  const Activity();
}

final class AtHome extends Activity {
  const AtHome();
}

final class Seeking extends Activity {
  const Seeking(this.goal);

  final SeekFor goal;
}

final class Burying extends Activity {
  Burying(this.drive);

  final Object drive;
}

final class Buried extends Activity {
  Buried(this.drive);

  final Object drive;
}

final class Carving extends Activity {
  const Carving();
}

final class Drawing extends Activity {
  Drawing(this.seat, this.port);

  final RaceSeat seat;
  final RacePort? port;
}

class SandfightApp extends StatefulWidget {
  const SandfightApp({super.key, this.machine, this.fakeUwb});

  final String? machine;

  /// Null uses the compile-time UWB stand-in. Tests pass true to open a solo race.
  final bool? fakeUwb;

  @override
  State<SandfightApp> createState() => _SandfightAppState();
}

class _SandfightAppState extends State<SandfightApp>
    with SingleTickerProviderStateMixin {
  final _peers = <NearbyPeer>[];
  Activity _activity = const AtHome();
  String? _error;
  String? _lastWinner;
  var _epoch = 0;
  StreamSubscription<GyroscopeEvent>? _gyro;
  DateTime? _gyroAt;
  double _yaw = 0;
  bool _allowed = true;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  MatchSample? _sample;
  var _peerCount = 0;
  AppScreen? _seenScreen;
  int? _capability;
  final _aimRound = AimRound();
  final _watch = Stopwatch()..start();
  BytePipe? _racePipe;
  void Function(String id)? _joinPeer;
  Future<void> Function()? _cancelSeek;
  VoidCallback? _onDrive;

  bool get _fake => widget.fakeUwb ?? UwbPose.fake;

  @override
  void initState() {
    super.initState();
    _loadWinner();
    if (widget.machine != null) {
      _allowed = meetsIphone12(widget.machine!);
      _noteCapability();
    } else {
      _checkFloor();
    }
  }

  @override
  void didUpdateWidget(covariant SandfightApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.machine != oldWidget.machine && widget.machine != null) {
      _allowed = meetsIphone12(widget.machine!);
      _noteCapability();
    }
  }

  Future<void> _checkFloor() async {
    final machine = widget.machine ?? await HapticPlayer.machine();
    if (!mounted) return;
    setState(() => _allowed = meetsIphone12(machine));
    _noteCapability();
  }

  Future<void> _loadWinner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _lastWinner = prefs.getString('lastWinner'));
    } catch (error, stack) {
      unawaited(
        CrashReportingService.instance.handled(
          error,
          stack,
          GameSignal.sessionError,
          {'code': 1},
        ),
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gyro?.cancel();
    final activity = _activity;
    if (activity is Drawing) {
      activity.port?.close();
      _racePipe?.close();
    }
    final cancel = _cancelSeek;
    if (cancel != null) unawaited(cancel());
    unawaited(_closeDrive(_heldDrive(activity)));
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final ms = dt.inMilliseconds.clamp(0, 250);
    if (ms == 0) return;
    switch (_activity) {
      case Burying():
        final drive = _drive;
        final pose = _livePose();
        if (drive is LocalDrive) {
          drive.tick(ms);
        } else if (drive is HostDrive) {
          if (pose != null) drive.loop.match.setPose(Seat.a, pose);
          drive.tick(ms);
        } else if (drive is GuestDrive) {
          drive.tick(ms, pose: pose, uwb: UwbPose.supported);
        }
        _advanceScreen();
        _noteMatch();
        if (mounted) setState(() {});
      case Drawing():
        _turn(const ClockTick());
      case AtHome() || Seeking() || Buried() || Carving():
        break;
    }
  }

  Pose? _livePose() {
    if (_fake) return null;
    final drive = _drive;
    final seat = switch (drive) {
      LocalDrive() => drive.seat,
      HostDrive() => drive.seat,
      GuestDrive() => drive.seat,
      _ => null,
    };
    if (seat == null) return null;
    final base = UwbPose.forSeat(seat);
    return Pose(base.xy, base.hdg + _yaw);
  }

  void _advanceScreen() {
    final match = _match;
    final activity = _activity;
    if (match == null || activity is! Burying) return;
    if (match.phase != Phase.ended) return;
    _activity = Buried(activity.drive);
    _ticker.stop();
    final winner = match.winner;
    if (winner == null) return;
    final name = winner == Seat.a ? 'P1' : 'P2';
    _lastWinner = name;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString('lastWinner', name),
    );
  }

  Object? get _drive => _heldDrive(_activity);

  Object? _heldDrive(Activity activity) => switch (activity) {
    Burying(:final drive) || Buried(:final drive) => drive,
    _ => null,
  };

  Match? get _match => switch (_drive) {
    LocalDrive(:final match) => match,
    HostDrive(:final match) => match,
    GuestDrive(:final match) => match,
    _ => null,
  };

  Seat get _seat => switch (_drive) {
    LocalDrive(:final seat) => seat,
    HostDrive(:final seat) => seat,
    GuestDrive(:final seat) => seat,
    _ => Seat.a,
  };

  bool _stale(int epoch) => !mounted || epoch != _epoch;

  void _seek(SeekFor goal) {
    final epoch = ++_epoch;
    final cancel = _cancelSeek;
    _cancelSeek = null;
    _joinPeer = null;
    if (cancel != null) unawaited(cancel());
    setState(() {
      _activity = Seeking(goal);
      _error = null;
      _peers.clear();
    });
    unawaited(_open(epoch, goal));
  }

  Future<void> _open(int epoch, SeekFor goal) async {
    final join = await openJoin(
      stillCurrent: () => !_stale(epoch),
      onPeers: (peers) {
        if (_stale(epoch)) return;
        _notePeers(peers.length);
        setState(
          () => _peers
            ..clear()
            ..addAll(peers),
        );
      },
      onError: (message) {
        if (_stale(epoch)) return;
        setState(() => _error = message);
      },
      bindJoin: (join) => _joinPeer = join,
      bindCancel: (cancel) => _cancelSeek = cancel,
      fakeUwb: widget.fakeUwb,
    );
    if (_stale(epoch) || join == null) {
      await _dropJoin(join);
      return;
    }
    switch (goal) {
      case SeekFor.bury:
        _startBury(join);
      case SeekFor.race:
        _startRace(join);
    }
  }

  void _startBury(Join join) {
    switch (join) {
      case JoinAlone():
        _use(LocalDrive(aim: AimMode.uwb));
      case JoinHost(:final pipe):
        _use(HostDrive(pipe, uwb: _fake));
        if (!_fake) _listenGyro();
      case JoinGuest(:final pipe):
        _use(GuestDrive(pipe));
        if (!_fake) _listenGyro();
    }
    _showMatch();
  }

  void _startRace(Join join) {
    int now() => _watch.elapsedMilliseconds;
    switch (join) {
      case JoinAlone():
        _racePipe = null;
        setState(
          () => _activity = Drawing(
            RaceCaller.openSolo(round: 0, now: now),
            null,
          ),
        );
      case JoinHost(:final pipe):
        _openPaired(
          pipe,
          (port) => RaceCaller.openHost(round: 0, now: now, port: port),
        );
      case JoinGuest(:final pipe):
        _openPaired(
          pipe,
          (port) => RaceDrawer.open(round: 0, now: now, port: port),
        );
    }
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _openPaired(BytePipe pipe, RaceSeat Function(RacePort port) open) {
    _racePipe = pipe;
    final port = RacePort(send: pipe.send, inbound: pipe.inbound);
    final seat = open(port);
    _activity = Drawing(seat, port);
    port.listen(_turn);
    setState(() {});
  }

  void _turn(RaceInput input) {
    final drawing = _activity;
    if (drawing is! Drawing) return;
    final next = drawing.seat.turn(input);
    if (!mounted) return;
    setState(() => _activity = Drawing(next, drawing.port));
    if (next.clock is Locked && _ticker.isActive) _ticker.stop();
  }

  Future<void> _dropJoin(Join? join) async {
    switch (join) {
      case JoinHost(:final pipe) || JoinGuest(:final pipe):
        await pipe.close();
      case JoinAlone() || null:
        break;
    }
  }

  void _use(Object drive) {
    _detach();
    if (drive is ChangeNotifier) {
      _onDrive = () {
        _advanceScreen();
        if (mounted) setState(() {});
      };
      drive.addListener(_onDrive!);
    }
    _activity = Burying(drive);
  }

  void _detach() {
    final drive = _drive;
    final listener = _onDrive;
    if (drive is ChangeNotifier && listener != null)
      drive.removeListener(listener);
    _onDrive = null;
  }

  void _listenGyro() {
    _gyro?.cancel();
    _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
        .listen((event) {
          final previous = _gyroAt;
          _gyroAt = event.timestamp;
          if (previous == null) return;
          final dt =
              event.timestamp.difference(previous).inMicroseconds / 1000000;
          if (dt <= 0 || dt > 0.2) return;
          _yaw += event.y * dt;
        });
  }

  void _swipe(Vec2 origin, Vec2 local, double speed) {
    final drive = _drive;
    if (drive is LocalDrive) {
      drive.swipe(origin: origin, local: local, speed: speed);
    } else if (drive is HostDrive) {
      drive.swipe(origin: origin, local: local, speed: speed);
    } else if (drive is GuestDrive) {
      drive.swipe(origin: origin, local: local, speed: speed);
    }
    _advanceScreen();
    setState(() {});
  }

  void _truck(Vec2 local) {
    final drive = _drive;
    if (drive is LocalDrive) {
      drive.aimTruck(local);
    } else if (drive is HostDrive) {
      drive.aimTruck(local);
    } else if (drive is GuestDrive) {
      drive.aimTruck(local);
    }
    _advanceScreen();
    setState(() {});
  }

  void _rematch() {
    final drive = _drive;
    if (drive is LocalDrive) {
      drive.rematch();
    } else if (drive is HostDrive) {
      drive.rematch();
    } else if (drive is GuestDrive) {
      drive.rematch();
    }
    _showMatch();
  }

  void _showMatch() {
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    final drive = _drive;
    setState(() {
      if (drive != null) _activity = Burying(drive);
    });
    _noteMatch();
  }

  Future<void> _leave() async {
    _finishRound(_match?.tMs ?? 0);
    _epoch++;
    final activity = _activity;
    _activity = const AtHome();
    if (activity is Drawing) {
      await activity.port?.close();
      await _racePipe?.close();
      _racePipe = null;
    }
    final cancel = _cancelSeek;
    _cancelSeek = null;
    _joinPeer = null;
    if (cancel != null) await cancel();
    await _closeDrive(_heldDrive(activity));
    await _gyro?.cancel();
    _gyro = null;
    _ticker.stop();
    _sample = null;
    _peerCount = 0;
    if (!mounted) return;
    setState(() {
      _peers.clear();
      _error = null;
    });
  }

  Future<void> _closeDrive(Object? drive) async {
    final listener = _onDrive;
    if (drive is ChangeNotifier && listener != null)
      drive.removeListener(listener);
    _onDrive = null;
    if (drive is LocalDrive) await drive.close();
    if (drive is HostDrive) await drive.close();
    if (drive is GuestDrive) await drive.close();
  }

  void _noteCapability() {
    final allowed = _allowed ? 1 : 0;
    if (_capability == allowed) return;
    _capability = allowed;
    CrashReportingService.instance.capability(allowed);
  }

  void _markScreen() {
    final next = !_allowed
        ? AppScreen.blocked
        : switch (_activity) {
            AtHome() => AppScreen.home,
            Seeking() => AppScreen.search,
            Burying() => AppScreen.match,
            Buried() => AppScreen.result,
            Carving() => AppScreen.carve,
            Drawing() => AppScreen.race,
          };
    if (_seenScreen == next) return;
    _seenScreen = next;
    CrashReportingService.instance.screen(next);
  }

  void _notePeers(int count) {
    final crumbs = watchPeers(_peerCount, count);
    _peerCount = count;
    final report = CrashReportingService.instance;
    for (final crumb in crumbs) {
      if (crumb.signal == GameSignal.peerLost && crumb.data['count'] == 0) {
        unawaited(report.failure(crumb.signal, crumb.data));
      } else {
        report.game(crumb.signal, crumb.data);
      }
    }
  }

  void _noteMatch() {
    final match = _match;
    if (match == null) return;
    final next = sampleMatch(
      match,
      players: _drive is LocalDrive ? 1 : 2,
      uwbSupported: UwbPose.supported ? 1 : 0,
    );
    final crumbs = watchMatch(_sample, next);
    _sample = next;
    final report = CrashReportingService.instance;
    var roundEnded = false;
    var lengthMs = 0;
    for (final crumb in crumbs) {
      if (crumb.signal == GameSignal.roundStart)
        unawaited(DeviceLog.instance.roundStarted());
      if (crumb.signal == GameSignal.roundEnd) {
        roundEnded = true;
        lengthMs = crumb.data['t_ms']?.toInt() ?? next.tMs;
        unawaited(DeviceLog.instance.roundFinished());
      }
      if (crumb.signal == GameSignal.peerLost) {
        unawaited(report.failure(crumb.signal, crumb.data));
      } else {
        report.game(crumb.signal, crumb.data);
      }
    }
    if (roundEnded) _finishRound(lengthMs);
  }

  void _onAim(AimThrow throwAim) {
    _aimRound.add(throwAim);
    CrashReportingService.instance.aim(throwAim);
  }

  void _finishRound(int lengthMs) {
    if (_aimRound.throws == 0) return;
    final data = _aimRound.summary(lengthMs);
    _aimRound.reset();
    unawaited(CrashReportingService.instance.roundSummary(data));
  }

  @override
  Widget build(BuildContext context) {
    _markScreen();
    final observers = CrashReportingService.instance.navigatorObservers;
    if (!_allowed) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: observers,
        home: const Scaffold(
          backgroundColor: Palette.pit,
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Sandfight needs an iPhone 12 or newer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Palette.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final match = _match;
    final home = HomeScreen(
      onFind: () => _seek(SeekFor.bury),
      onCarve: () => setState(() => _activity = const Carving()),
      onRace: () => _seek(SeekFor.race),
      lastWinner: _lastWinner,
    );
    final body = switch (_activity) {
      AtHome() => home,
      Seeking() => SearchScreen(
        peers: List.of(_peers),
        error: _error,
        onJoin: (id) => _joinPeer?.call(id),
        onLeave: _leave,
      ),
      Burying() when match != null => MatchScreen(
        match: match,
        seat: _seat,
        onSwipe: _swipe,
        onAim: _onAim,
        onTruck: _truck,
        onLeave: _leave,
      ),
      Buried() when match != null => ResultScreen(
        match: match,
        seat: _seat,
        onRematch: _rematch,
        onLeave: _leave,
      ),
      Carving() => CarveScreen(onLeave: _leave),
      Drawing(:final seat) => RaceScreen(
        glyph: seat.glyph,
        clock: seat.clock,
        place: seat.showing,
        onStroke: (stroke) => _turn(StrokeUp(stroke)),
        onLeave: _leave,
      ),
      Burying() || Buried() => home,
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: observers,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.pit,
      ),
      home: body,
    );
  }
}
