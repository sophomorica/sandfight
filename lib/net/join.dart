import 'dart:async';

import '../telemetry/crash_reporting.dart';
import '../telemetry/game_watch.dart';
import 'ble_session.dart';
import 'pipe.dart';
import 'tcp_pipe.dart';
import 'uwb_pose.dart';

sealed class Join {
  const Join();
}

final class JoinAlone extends Join {
  const JoinAlone();
}

final class JoinHost extends Join {
  JoinHost(this.pipe);

  final BytePipe pipe;
}

final class JoinGuest extends Join {
  JoinGuest(this.pipe);

  final BytePipe pipe;
}

Future<Join?> openJoin({
  required bool Function() stillCurrent,
  required void Function(List<NearbyPeer> peers) onPeers,
  required void Function(String message) onError,
  void Function(void Function(String id) join)? bindJoin,
  void Function(Future<void> Function() cancel)? bindCancel,
  bool? fakeUwb,
}) async {
  final role = const String.fromEnvironment('ROLE').toLowerCase();
  final fake = fakeUwb ?? UwbPose.fake;
  if (fake && role.isEmpty) return const JoinAlone();
  if (fake && role == 'host') {
    final tcp = TcpHost();
    bindCancel?.call(tcp.cancel);
    try {
      final pipe = await tcp.waitForGuest();
      if (!stillCurrent()) {
        await pipe.close();
        return null;
      }
      return JoinHost(pipe);
    } catch (error, stack) {
      if (!stillCurrent()) return null;
      unawaited(
        CrashReportingService.instance.handled(
          error,
          stack,
          GameSignal.sessionError,
          {'code': 2},
        ),
      );
      onError('No guest sim joined. $error');
      return null;
    }
  }
  if (fake && role == 'guest') {
    try {
      final pipe = await TcpPipe.connect();
      if (!stillCurrent()) {
        await pipe.close();
        return null;
      }
      return JoinGuest(pipe);
    } catch (error, stack) {
      if (!stillCurrent()) return null;
      unawaited(
        CrashReportingService.instance.handled(
          error,
          stack,
          GameSignal.sessionError,
          {'code': 3},
        ),
      );
      onError('Start the host sim first. $error');
      return null;
    }
  }
  final ble = BleSession();
  final ready = Completer<Join?>();
  bindJoin?.call(ble.join);
  bindCancel?.call(() async {
    if (!ready.isCompleted) ready.complete(null);
    await ble.stop();
  });
  ble.onPeers = (peers) {
    if (!stillCurrent()) return;
    onPeers(peers);
  };
  ble.onError = (message) {
    if (!stillCurrent()) return;
    onError(message);
  };
  ble.onReady = (pipe) {
    if (!stillCurrent() || ready.isCompleted) return;
    ready.complete(ble.isGuest ? JoinGuest(pipe) : JoinHost(pipe));
  };
  try {
    await ble.start();
  } catch (error, stack) {
    if (!stillCurrent()) return null;
    unawaited(
      CrashReportingService.instance.handled(
        error,
        stack,
        GameSignal.sessionError,
        {'code': 4},
      ),
    );
    onError('Bluetooth did not start. $error');
    if (!ready.isCompleted) ready.complete(null);
    return null;
  }
  return ready.future;
}
