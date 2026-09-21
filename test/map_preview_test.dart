import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suno_ai/widgets/map_preview_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> launches;
  bool failLaunch = false;
  setUp(() {
    launches = [];
    failLaunch = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            launches.add(call);
            if (failLaunch) throw PlatformException(code: 'unavailable');
            return true;
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  });
  Widget card(double? latitude, double? longitude) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: MapPreviewCard(latitude: latitude, longitude: longitude),
        ),
      ),
    ),
  );

  testWidgets(
    'missing and invalid coordinates never open an invented location',
    (tester) async {
      for (final latitude in [null, double.nan, 91.0]) {
        await tester.pumpWidget(card(latitude, 73));
        expect(find.text('Location unavailable'), findsOneWidget);
        expect(find.byType(FlutterMap), findsNothing);
        expect(find.text('OPEN'), findsNothing);
      }
      expect(launches, isEmpty);
    },
  );

  testWidgets(
    'map pans, recenters on new coordinates and opens the current snapshot',
    (tester) async {
      await tester.pumpWidget(card(33, 73));
      await tester.pump();
      final context = tester.element(find.byType(TileLayer));
      final center = MapCamera.of(context).center;
      await tester.drag(find.byType(FlutterMap), const Offset(60, 20));
      await tester.pump();
      expect(MapCamera.of(context).center, isNot(center));
      await tester.pumpWidget(card(34, 74));
      await tester.pump();
      final updated = MapCamera.of(tester.element(find.byType(TileLayer)))
          .center;
      expect(updated.latitude, 34);
      expect(updated.longitude, 74);
      await tester.tap(find.text('OPEN'));
      await tester.pump();
      expect(
        Uri.parse(launches.last.arguments['url'] as String)
            .queryParameters['query'],
        '34.0,74.0',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('external map failure stays on screen with a useful message', (
    tester,
  ) async {
    failLaunch = true;
    await tester.pumpWidget(card(33, 73));
    await tester.tap(find.text('OPEN'));
    await tester.pump();
    expect(
      find.text('Could not open Maps. Check your browser or map app.'),
      findsOneWidget,
    );
    expect(find.text('33.00000, 73.00000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
