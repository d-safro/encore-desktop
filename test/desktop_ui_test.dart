// The desktop window's look and feel (the UI audit's changes), on the real shell and screens with a pretend
// server and player (support/ui_rig.dart).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:encore/core/appearance.dart';
import 'package:encore/app.dart' show encoreTheme;
import 'package:encore/core/settings.dart';
import 'package:encore/desktop/shell.dart' show windowBackground;
import 'package:encore/ui/widgets.dart';

import 'support/fake_server.dart' show albumArtist, artistJson, songJson;
import 'support/ui_rig.dart';

void main() {
  setUpAll(setUpRig);

  Text textOf(WidgetTester t, String s) => t.widget<Text>(find.text(s).first);

  group('names are links', () {
    testWidgets('the album\'s artist underlines under the mouse, with no gray box', (t) async {
      await pumpDesktop(t, '/album/al2');
      final artist = artistJson(albumArtist(2))['name'] as String;
      final name = find.text(artist).first;
      expect(find.ancestor(of: name, matching: find.byType(NameLink)), findsOneWidget);
      expect(find.ancestor(of: name, matching: find.byType(Tappable)), findsNothing);
      expect(textOf(t, artist).style?.decoration, isNot(TextDecoration.underline));
      await hover(t, name);
      expect(textOf(t, artist).style?.decoration, TextDecoration.underline);
    });

    testWidgets('the full player\'s artist is a link too', (t) async {
      await pumpDesktop(t, '/player');
      final artist = songJson(0, 0)['artist'] as String;
      final names = find.text(artist);
      expect(names, findsWidgets);
      expect(find.ancestor(of: names, matching: find.byType(Tappable)), findsNothing);
    });
  });

  group('shelf arrows', () {
    Future<void> shelf(WidgetTester t, int cards) async {
      t.view.physicalSize = const Size(1000, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppLook.from(const Settings())]),
        home: Scaffold(
          body: Shelf(title: 'Albums', children: [for (var i = 0; i < cards; i++) const SizedBox(width: 150)]),
        ),
      ));
      await t.pump(); // the row's size is known after a frame
      await t.pump();
    }

    IconButton arrow(WidgetTester t, String tip) =>
        t.widget<IconButton>(find.ancestor(of: find.byTooltip(tip), matching: find.byType(IconButton)).first);

    testWidgets('none when the row fits', (t) async {
      await shelf(t, 3);
      expect(find.byTooltip('Scroll Albums back'), findsNothing);
      expect(find.byTooltip('Scroll Albums on'), findsNothing);
    });

    testWidgets('a row that overflows: only the way it can go', (t) async {
      await shelf(t, 20);
      expect(arrow(t, 'Scroll Albums back').onPressed, isNull); // at the start
      expect(arrow(t, 'Scroll Albums on').onPressed, isNotNull);
      await t.tap(find.byTooltip('Scroll Albums on'));
      await t.pumpAndSettle();
      expect(arrow(t, 'Scroll Albums back').onPressed, isNotNull);
      final list = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      list.jumpTo(list.maxScrollExtent);
      await t.pump();
      expect(arrow(t, 'Scroll Albums on').onPressed, isNull); // at the end
    });
  });

  testWidgets('the sidebar\'s Settings row is as wide as the rows above it', (t) async {
    await pumpDesktop(t, '/settings');
    Rect row(String label) {
      final text = find.text(label).evaluate().firstWhere((e) => t.getTopLeft(find.byWidget(e.widget)).dx < 260);
      return t.getRect(find.ancestor(of: find.byWidget(text.widget), matching: find.byType(Material)).first);
    }

    final home = row('Home'), settings = row('Settings');
    expect(settings.left, home.left);
    expect(settings.width, home.width);
  });

  group('tabs: compact pills on the left, under the title', () {
    for (final (page, first) in [('/following', 'Artists'), ('/library?tab=2', 'Playlists')]) {
      testWidgets(page, (t) async {
        await pumpDesktop(t, page);
        expect(t.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
        final tab = t.getRect(find.ancestor(of: find.text(first).last, matching: find.byType(Tab)));
        expect(tab.left, lessThan(300)); // the page starts at 264
        expect(tab.width, lessThan(160)); // not stretched across the page
      });
    }
  });

  group('side panels share Now playing\'s header', () {
    for (final (panel, close, title) in [
      ('queue', 'Hide the queue', 'Queue · 6 songs'),
      ('lyrics', 'Hide the lyrics', 'Lyrics'),
      ('nowPlaying', 'Hide Now playing', 'Now playing'),
    ]) {
      testWidgets(panel, (t) async {
        await pumpDesktop(t, '/home', extraPrefs: {'sidePanel': panel});
        final heading = t.widget<Text>(find.text(title).first);
        final style = DefaultTextStyle.of(t.element(find.text(title).first)).style.merge(heading.style);
        expect(style.fontSize, Theme.of(t.element(find.text(title).first)).textTheme.titleSmall!.fontSize);
        await t.tap(find.byTooltip(close));
        await settle(t);
        expect(find.byTooltip(close), findsNothing); // the panel closed
      });
    }
  });

  testWidgets('concerts: one heading per month', (t) async {
    await pumpDesktop(t, '/concerts', size: const Size(1280, 1400));
    expect(find.text('Dec'), findsOneWidget); // six December shows, one "Dec"
  });

  group('the window behind the panes', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (max(x, y) + 0.05) / (min(x, y) + 0.05);
    }

    for (final b in Brightness.values) {
      test('${b.name}: the player bar\'s gray text reads on it', () {
        final cs = encoreTheme(ColorScheme.fromSeed(seedColor: Color(const Settings().accentColor), brightness: b),
            const Settings()).colorScheme;
        final bg = windowBackground(cs);
        expect(contrast(cs.onSurfaceVariant, bg), greaterThanOrEqualTo(4.5));
        // a frame round the panes: a step from the surface, darker on dark, still light on light
        expect(bg, isNot(cs.surface));
        if (b == Brightness.light) expect(bg.computeLuminance(), greaterThan(0.7));
        if (b == Brightness.dark) expect(bg.computeLuminance(), lessThan(cs.surface.computeLuminance()));
      });
    }
  });

  testWidgets('light theme: "About the artist" in the theme\'s text colour', (t) async {
    await pumpDesktop(t, '/home', theme: 'light', size: const Size(1280, 1600), extraPrefs: {'sidePanel': 'nowPlaying'});
    final heading = find.text('About the artist');
    final cs = Theme.of(t.element(heading)).colorScheme;
    expect(t.widget<Text>(heading).style?.color, cs.onSurface);
  });

  group('a release you don\'t have: the round badge, not a ⬇ character', () {
    for (final page in ['/home', '/following?tab=1']) {
      testWidgets(page, (t) async {
        await pumpDesktop(t, page, size: const Size(1280, 2000));
        expect(find.text('⬇'), findsNothing);
        expect(find.byType(LookupBadge), findsNWidgets(3)); // the rig's three releases
      });
    }
  });
}
