import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_floor.dart';
import 'features/home/home_screen.dart';
import 'features/home/search_screen.dart';
import 'features/match/match_screen.dart';
import 'features/result/result_screen.dart';
import 'game/rules.dart';
import 'game/throw_ray.dart';
import 'haptic_player.dart';
import 'net/ble_session.dart';
import 'net/session.dart';
import 'net/tcp_pipe.dart';
import 'net/uwb_pose.dart';
import 'telemetry/aim_log.dart';
import 'telemetry/crash_reporting.dart';
import 'telemetry/game_watch.dart';
import 'theme/palette.dart';

const _roleName = String.fromEnvironment('ROLE');

enum _Screen { home, search, match, result }

class SandfightApp extends StatefulWidget {
  const SandfightApp({super.key, this.machine});

  final String? machine;

  @override
  State<SandfightApp> createState() => _SandfightAppState();
}

class _SandfightAppState extends State<SandfightApp> with SingleTickerProviderStateMixin {
  final _peers = <NearbyPeer>[];
  _Screen _screen = _Screen.home;
  String? _error;
  String? _lastWinner;
  Object? _drive;
  BleSession? _ble;
  TcpHost? _tcp;
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
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 1}));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gyro?.cancel();
    _driveClose();
    _ble?.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    final ms = dt.inMilliseconds.clamp(0, 250);
    if (ms == 0 || _screen != _Screen.match) return;
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
  }

  Pose? _livePose() {
    if (UwbPose.fake) return null;
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
    if (match == null) return;
    if (match.phase == Phase.ended && _screen == _Screen.match) {
      _screen = _Screen.result;
      _ticker.stop();
      final winner = match.winner;
      if (winner != null) {
        final name = winner == Seat.a ? 'P1' : 'P2';
        _lastWinner = name;
        SharedPreferences.getInstance().then((prefs) => prefs.setString('lastWinner', name));
      }
    }
  }

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

  Future<void> _find() async {
    final epoch = ++_epoch;
    setState(() {
      _screen = _Screen.search;
      _error = null;
      _peers.clear();
    });
    final role = _roleName.toLowerCase();
    if (UwbPose.fake && role.isEmpty) {
      _use(LocalDrive(aim: AimMode.uwb));
      _showMatch();
      return;
    }
    if (UwbPose.fake && role == 'host') {
      final tcp = TcpHost();
      _tcp = tcp;
      try {
        final pipe = await tcp.waitForGuest();
        if (_stale(epoch)) {
          await pipe.close();
          return;
        }
        _use(HostDrive(pipe, uwb: true));
        _showMatch();
      } catch (error, stack) {
        if (_stale(epoch)) return;
        unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 2}));
        setState(() => _error = 'No guest sim joined. $error');
      }
      return;
    }
    if (UwbPose.fake && role == 'guest') {
      try {
        final pipe = await TcpPipe.connect();
        if (_stale(epoch)) {
          await pipe.close();
          return;
        }
        _use(GuestDrive(pipe));
        _showMatch();
      } catch (error, stack) {
        if (_stale(epoch)) return;
        unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 3}));
        setState(() => _error = 'Start the host sim first. $error');
      }
      return;
    }
    final ble = BleSession();
    _ble = ble;
    ble.onPeers = (peers) {
      if (_stale(epoch)) return;
      _notePeers(peers.length);
      setState(() => _peers..clear()..addAll(peers));
    };
    ble.onError = (message) {
      if (_stale(epoch)) return;
      setState(() => _error = message);
    };
    ble.onReady = (pipe) {
      if (_stale(epoch)) return;
      final drive = ble.isGuest ? GuestDrive(pipe) : HostDrive(pipe, uwb: false);
      _use(drive);
      _listenGyro();
      _showMatch();
    };
    try {
      await ble.start();
    } catch (error, stack) {
      if (_stale(epoch)) return;
      unawaited(CrashReportingService.instance.handled(error, stack, GameSignal.sessionError, {'code': 4}));
      setState(() => _error = 'Bluetooth did not start. $error');
    }
  }

  VoidCallback? _onDrive;

  void _use(Object drive) {
    _detach();
    _drive = drive;
    if (drive is ChangeNotifier) {
      _onDrive = () {
        _advanceScreen();
        if (mounted) setState(() {});
      };
      drive.addListener(_onDrive!);
    }
  }

  void _detach() {
    final drive = _drive;
    final listener = _onDrive;
    if (drive is ChangeNotifier && listener != null) drive.removeListener(listener);
    _onDrive = null;
    _drive = null;
  }

  void _listenGyro() {
    _gyro?.cancel();
    _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((event) {
      final previous = _gyroAt;
      _gyroAt = event.timestamp;
      if (previous == null) return;
      final dt = event.timestamp.difference(previous).inMicroseconds / 1000000;
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
    setState(() => _screen = _Screen.match);
    _noteMatch();
  }

  Future<void> _leave() async {
    _finishRound(_match?.tMs ?? 0);
    _epoch++;
    await _tcp?.cancel();
    _tcp = null;
    await _driveClose();
    await _ble?.stop();
    _ble = null;
    await _gyro?.cancel();
    _gyro = null;
    _ticker.stop();
    _sample = null;
    _peerCount = 0;
    if (!mounted) return;
    setState(() {
      _screen = _Screen.home;
      _peers.clear();
      _error = null;
    });
  }

  Future<void> _driveClose() async {
    final drive = _drive;
    _detach();
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
        : switch (_screen) {
            _Screen.home => AppScreen.home,
            _Screen.search => AppScreen.search,
            _Screen.match => AppScreen.match,
            _Screen.result => AppScreen.result,
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
    final next = sampleMatch(match, players: _drive is LocalDrive ? 1 : 2, uwbSupported: UwbPose.supported ? 1 : 0);
    final crumbs = watchMatch(_sample, next);
    _sample = next;
    final report = CrashReportingService.instance;
    var roundEnded = false;
    var lengthMs = 0;
    for (final crumb in crumbs) {
      if (crumb.signal == GameSignal.roundEnd) {
        roundEnded = true;
        lengthMs = crumb.data['t_ms']?.toInt() ?? next.tMs;
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
                style: TextStyle(color: Palette.ink, fontSize: 28, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      );
    }
    final match = _match;
    final body = switch (_screen) {
      _Screen.home => HomeScreen(onFind: _find, lastWinner: _lastWinner),
      _Screen.search => SearchScreen(peers: List.of(_peers), error: _error, onJoin: (id) => _ble?.join(id), onLeave: _leave),
      _Screen.match when match != null => MatchScreen(
        match: match,
        seat: _seat,
        onSwipe: _swipe,
        onAim: _onAim,
        onTruck: _truck,
        onLeave: _leave,
      ),
      _Screen.result when match != null => ResultScreen(match: match, seat: _seat, onRematch: _rematch, onLeave: _leave),
      _ => HomeScreen(onFind: _find, lastWinner: _lastWinner),
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: observers,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Palette.pit),
      home: body,
    );
  }
}
