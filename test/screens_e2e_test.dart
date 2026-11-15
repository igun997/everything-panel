import 'package:everything_panel/ui/glass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

const phone = Size(412, 892);
const tablet = Size(1280, 800);

/// Opens a tab through whichever navigation the window shows (bar or rail).
Future<void> goTab(WidgetTester tester, String label) async {
  final nav = find.byWidgetPredicate((w) => w is GlassNavBar || w is GlassNavRail);
  final item = find.descendant(of: nav, matching: find.text(label));
  expect(item, findsOneWidget, reason: 'no "$label" tab');
  await tester.tap(item);
  await settle(tester, ms: 900);
}

/// Welcome, then the add-server form, through the real screens.
Future<Harness> connectedApp(WidgetTester tester, {Size size = phone}) async {
  final h = await pumpApp(tester, size: size);
  await tapText(tester, 'Continue without an account');
  await tapText(tester, 'Add a server');

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Production');
  await tester.enterText(fields.at(1), 'panel.example.com');
  await tester.enterText(fields.at(2), 'good-token');
  await tapText(tester, 'Connect');
  await settle(tester, ms: 2500);
  return h;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
  });

  group('first run and connecting', () {
    testWidgets('welcome offers Google (disabled without Firebase) and continues without an account', (tester) async {
      await pumpApp(tester);
      expect(find.text('Every server.\nOne glass panel.'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.textContaining('Firebase config'), findsOneWidget);

      await tapText(tester, 'Continue without an account');
      expect(find.text('No servers yet'), findsOneWidget);
    });

    testWidgets('a wrong token is rejected on the form and nothing is saved', (tester) async {
      final h = await pumpApp(tester);
      await tapText(tester, 'Continue without an account');
      await tapText(tester, 'Add a server');

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'panel.example.com');
      await tester.enterText(fields.at(2), 'bad');
      await tapText(tester, 'Connect');
      await settle(tester, ms: 800);

      expect(find.textContaining('Token rejected'), findsOneWidget);
      expect(h.app.sessions, isEmpty);
    });

    testWidgets('a good token connects and the server appears on the fleet with live counts', (tester) async {
      final h = await connectedApp(tester);

      expect(h.app.sessions, hasLength(1));
      expect(find.text('Production'), findsWidgets);
      expect(find.text('All systems running'), findsNothing); // api is stopped, so not all healthy
      expect(find.textContaining('running'), findsWidgets);
    });
  });

  group('services', () {
    testWidgets('groups fold and unfold, and search stays pinned while the list scrolls', (tester) async {
      await connectedApp(tester);
      await goTab(tester, 'Services');

      expect(find.text('web'), findsOneWidget);
      expect(find.text('pg'), findsOneWidget);

      // Fold the "shop" group: its services disappear, the other group stays.
      await tapText(tester, 'SHOP');
      expect(find.text('web'), findsNothing);
      expect(find.text('api'), findsNothing);
      expect(find.text('pg'), findsOneWidget);

      await tapText(tester, 'SHOP');
      expect(find.text('web'), findsOneWidget);

      // Search shows matches even from folded groups.
      await tapText(tester, 'Fold all');
      expect(find.text('pg'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'pg');
      await settle(tester, ms: 800);
      expect(find.text('web'), findsNothing);
      expect(find.text('pg'), findsWidgets); // the tile, and the text typed into the field

      // The search field is still on screen after scrolling the list.
      await tester.enterText(find.byType(TextField).first, '');
      await settle(tester, ms: 600);
      await tapText(tester, 'Unfold all');
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
      await settle(tester, ms: 600);
      final search = tester.getRect(find.byType(TextField).first);
      expect(search.top, lessThan(200), reason: 'search scrolled away instead of staying pinned');
    });

    testWidgets('stopping a service asks first, then tells the panel', (tester) async {
      final h = await connectedApp(tester);
      await goTab(tester, 'Services');

      await tapText(tester, 'web');
      expect(find.text('Logs and activity'), findsOneWidget);
      await tapText(tester, 'Stop');
      expect(find.text('Stop web?'), findsOneWidget);
      expect(h.backends.last.calls, isEmpty, reason: 'must not stop before confirming');

      await tapText(tester, 'Stop', index: 1);
      expect(h.backends.last.calls, ['stop shop/web']);
      await settle(tester, ms: 3500); // the follow-up refresh after an action
    });

    testWidgets('logs screen explains missing runtime logs and shows activity with its log', (tester) async {
      await connectedApp(tester);
      await goTab(tester, 'Services');
      await tapText(tester, 'web');
      await tapText(tester, 'Logs and activity');
      await settle(tester, ms: 1200);

      expect(find.text('Runtime logs are off'), findsOneWidget);

      await tapText(tester, 'Activity');
      expect(find.text('Deployed web'), findsOneWidget);
      await tapText(tester, 'Deployed web');
      expect(find.textContaining('build step two'), findsOneWidget);
    });
  });

  group('system', () {
    testWidgets('uptime and network sit on one line', (tester) async {
      await connectedApp(tester);
      await goTab(tester, 'System');

      expect(find.text('CPU'), findsOneWidget);
      final up = tester.getCenter(find.text('UPTIME')).dy;
      final netIn = tester.getCenter(find.text('NET IN')).dy;
      final netOut = tester.getCenter(find.text('NET OUT')).dy;
      expect(netIn, up);
      expect(netOut, up);
    });
  });

  group('phone and tablet', () {
    testWidgets('phones get the floating bottom bar', (tester) async {
      await connectedApp(tester, size: phone);
      expect(find.byType(GlassNavBar), findsOneWidget);
      expect(find.byType(GlassNavRail), findsNothing);
    });

    testWidgets('tablets get a side rail and every tab still works', (tester) async {
      await connectedApp(tester, size: tablet);
      expect(find.byType(GlassNavRail), findsOneWidget);
      expect(find.byType(GlassNavBar), findsNothing);

      for (final tab in ['Services', 'System', 'Settings', 'Fleet']) {
        await goTab(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab threw on a tablet');
      }
    });

    testWidgets('tablet content stays in a centred column instead of stretching', (tester) async {
      await connectedApp(tester, size: tablet);
      await goTab(tester, 'Services');
      final tile = tester.getRect(find.text('web'));
      expect(tile.right, lessThan(1100), reason: 'content stretched across the whole tablet');
    });

    testWidgets('tablet shows the welcome art beside the copy', (tester) async {
      await pumpApp(tester, size: tablet);
      final copy = tester.getTopLeft(find.text('EVERYTHING-PANEL')).dx;
      expect(copy, greaterThan(500), reason: 'copy should sit on the right half');
    });
  });
}
