import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/app.dart';
import 'package:sandfight/features/home/home_screen.dart';
import 'package:sandfight/features/match/match_screen.dart';
import 'package:sandfight/net/session.dart';
import 'package:sandfight/render/sand_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home shows find nearby and the last bury', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(onFind: () {}, lastWinner: 'P2'),
      ),
    );
    expect(find.text('Find nearby players'), findsOneWidget);
    expect(find.text('Hold the phone up.'), findsOneWidget);
    expect(find.text('Flick sand toward the other phone.'), findsOneWidget);
    expect(find.text('Empty your pile to bury them.'), findsOneWidget);
    expect(find.text('Last bury: P2'), findsOneWidget);
  });

  testWidgets('iPhone 11 is refused and iPhone 12 reaches home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SandfightApp(machine: 'iPhone12,1'));
    await tester.pump();
    expect(find.text('Sandfight needs an iPhone 12 or newer.'), findsOneWidget);

    await tester.pumpWidget(const SandfightApp(machine: 'iPhone13,2'));
    await tester.pump();
    expect(find.text('Find nearby players'), findsOneWidget);
  });

  testWidgets('a flick up the pile moves 12 mass', (tester) async {
    final drive = LocalDrive();
    await tester.pumpWidget(MaterialApp(home: _Harness(drive: drive)));
    await tester.fling(find.byType(SandField), const Offset(0, -700), 5000);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('my-mass'))).data, '88');
    expect(tester.widget<Text>(find.byKey(const Key('their-mass'))).data, '112');
    expect(drive.match.conserved, 200);
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.drive});

  final LocalDrive drive;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  void initState() {
    super.initState();
    widget.drive.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MatchScreen(
      match: widget.drive.match,
      seat: widget.drive.seat,
      onSwipe: (origin, local, speed) => widget.drive.swipe(origin: origin, local: local, speed: speed),
      onTruck: widget.drive.aimTruck,
      onLeave: () {},
    );
  }
}
