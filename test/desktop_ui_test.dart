// The desktop window's look and feel (the UI audit's changes), on the real shell and screens with a pretend
// server and player (support/ui_rig.dart).
import 'dart:math';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:encore/core/appearance.dart';
import 'package:encore/app.dart' show encoreTheme;
import 'package:encore/core/settings.dart';
import 'package:encore/desktop/focus_ring.dart';
import 'package:encore/desktop/sheets.dart' show MenuLayout;
import 'package:encore/desktop/shell.dart' show windowBackground;
import 'package:encore/ui/sheets.dart';
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

  group('Home\'s quick picks: a fixed height, more across on a wide window', () {
    for (final (width, count) in [(1280.0, 9), (1920.0, 8)]) {
      testWidgets('$width px', (t) async {
        await pumpDesktop(t, '/home', size: Size(width, 1000));
        final tiles = find.descendant(of: find.byType(GridView).first, matching: find.byType(InkWell));
        expect(tiles, findsNWidgets(count));
        expect(t.getSize(tiles.first).height, 72);
      });
    }
  });

  group('On this computer', () {
    testWidgets('the play and shuffle buttons of every song list, a compact filter', (t) async {
      await pumpDesktop(t, '/local');
      expect(find.byType(PlayButtons), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Shuffle'), findsNothing); // the phone's pill
      expect(t.getSize(find.byType(TextField).last).height, 40);
    });

    testWidgets('a song without an artist keeps its title in the middle of the row', (t) async {
      await pumpDesktop(t, '/local');
      final title = find.text('Local 1'); // the rig's odd songs have no artist
      final row = find.ancestor(of: title, matching: find.byType(SongTile));
      expect((t.getCenter(title).dy - t.getCenter(row).dy).abs(), lessThan(2));
    });
  });

  group('menus open where you click', () {
    testWidgets('right-click on a song: a compact menu at the pointer, not a bottom sheet', (t) async {
      await pumpDesktop(t, '/playlist/pl2');
      final row = find.byType(SongTile).at(2);
      final at = t.getCenter(row);
      await t.tap(row, buttons: kSecondaryButton);
      await settle(t);
      expect(find.byType(BottomSheet), findsNothing);
      final item = find.text('Play next');
      expect(item, findsOneWidget);
      final menu = t.getRect(find.ancestor(of: item, matching: find.byType(Material)).last);
      expect(menu.width, lessThanOrEqualTo(MenuLayout.width));
      expect(menu.left, closeTo(at.dx, 1)); // opens to the right of the pointer
      expect(menu.bottom, lessThanOrEqualTo(800)); // moved up to stay inside the window
      await t.tapAt(const Offset(5, 5)); // a click elsewhere closes it
      await settle(t);
      expect(find.text('Play next'), findsNothing);
    });

    test('a menu stays inside the window', () {
      const window = Size(1000, 700), menu = Size(300, 400);
      final l = MenuLayout(const Offset(900, 600));
      final p = l.getPositionForChild(window, menu);
      expect(p.dx, 600); // flipped to the pointer's left
      expect(p.dy, 700 - MenuLayout.margin - 400); // moved up
      expect(MenuLayout(null).getPositionForChild(window, menu), const Offset(350, 150)); // no pointer: the middle
    });

    testWidgets('the phone (nothing installed) keeps its bottom sheet', (t) async {
      final before = sheetOpener;
      sheetOpener = null;
      addTearDown(() => sheetOpener = before);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAppSheet(context: ctx, menu: true, builder: (_) => const Text('a menu')),
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('a menu'), findsOneWidget);
    });
  });

  group('the phone\'s other bottom sheets are dialogs', () {
    for (final (page, button, inside) in [
      ('/album/al2', 'Add to playlist', 'New playlist'),
      ('/home', 'Your devices (Ctrl+D)', 'Your devices'),
      ('/home', 'Sound', 'Volume'),
    ]) {
      testWidgets(button, (t) async {
        await pumpDesktop(t, page);
        await t.tap(find.byTooltip(button).first);
        await settle(t);
        expect(find.byType(BottomSheet), findsNothing);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        expect(find.descendant(of: dialog, matching: find.text(inside)), findsWidgets);
        final panel = find.descendant(of: dialog, matching: find.byType(Material)).first;
        expect(t.getSize(panel).width, lessThanOrEqualTo(520)); // a dialog, not a sheet across the window
      });
    }
  });

  group('one back button: the window\'s', () {
    for (final page in ['/album/al2', '/settings', '/liked', '/local', '/following']) {
      testWidgets(page, (t) async {
        await pumpDesktop(t, page);
        expect(find.byType(BackButton), findsNothing);
        expect(find.byTooltip('Back (Alt+←)'), findsOneWidget);
      });
    }

    testWidgets('titles start where Home\'s does, and the window\'s ‹ still goes back', (t) async {
      await pumpDesktop(t, '/settings');
      expect(t.getTopLeft(find.descendant(of: find.byType(AppBar), matching: find.text('Settings'))).dx, lessThan(300));
      await t.tap(find.byTooltip('Back (Alt+←)'));
      await settle(t);
      expect(find.byType(AppBar), findsNothing); // Home has none
      expect(find.textContaining('Good '), findsOneWidget);
    });
  });

  group('one search box', () {
    testWidgets('the Search page has none of its own; the window\'s box searches as you type', (t) async {
      final router = await pumpDesktop(t, '/home');
      expect(find.byType(TextField), findsOneWidget); // the window's
      router.go('/search');
      await settle(t);
      expect(find.byType(SearchBar), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await t.enterText(find.byType(TextField), 'harbour');
      await t.pump(const Duration(seconds: 1)); // the page waits for typing to pause
      await settle(t);
      expect(find.text('Artists'), findsOneWidget); // results came
      await t.tap(find.byTooltip('Clear'));
      await t.pump(const Duration(seconds: 1));
      await settle(t);
      expect(find.text('Artists'), findsNothing);
    });

    testWidgets('a search from another page lands in the same box', (t) async {
      final router = await pumpDesktop(t, '/home');
      await t.enterText(find.byType(TextField), 'harbour');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t);
      expect(router.state.uri.toString(), '/search?q=harbour');
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'harbour');
      expect(find.text('Songs'), findsWidgets);
    });
  });

  group('page buttons instead of floating ones', () {
    for (final (page, label) in [
      ('/library?tab=0', 'New playlist'),
      ('/library?tab=1', 'Add podcast'),
      ('/radio', 'Add station'),
    ]) {
      testWidgets(label, (t) async {
        await pumpDesktop(t, page);
        expect(find.byType(FloatingActionButton), findsNothing);
        final button = find.widgetWithText(AddButton, label);
        expect(button, findsOneWidget);
        expect(t.getTopLeft(button).dy, lessThan(220)); // at the top of the page
      });
    }
  });

  testWidgets('Library › Playlists: covers in a grid like Albums, each with its menu', (t) async {
    await pumpDesktop(t, '/library?tab=0', size: const Size(1280, 1200));
    final liked = t.getTopLeft(find.text('Liked songs').last);
    final first = t.getTopLeft(find.text('Morning Coffee').last);
    final second = t.getTopLeft(find.text('Deep Focus').last);
    expect(second.dy, first.dy); // side by side, not a list
    expect(second.dx, greaterThan(first.dx));
    expect(liked.dy, first.dy);
    await t.tap(find.text('Deep Focus').last, buttons: kSecondaryButton);
    await settle(t);
    expect(find.text('Shuffle'), findsOneWidget); // the playlist's menu
  });

  testWidgets('a ring round the keyboard focus, from the first Tab to the next click', (t) async {
    await t.pumpWidget(MaterialApp(
      home: FocusRing(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) Focus(child: Builder(builder: (_) => const SizedBox(width: 80, height: 40))),
          ],
        ),
      ),
    ));
    RenderObject ring() =>
        t.renderObject(find.descendant(of: find.byType(FocusRing), matching: find.byType(CustomPaint)).first);
    final accent = Theme.of(t.element(find.byType(FocusRing))).colorScheme.primary;
    expect(ring(), paintsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(ring(), paints..rrect(color: accent, style: PaintingStyle.stroke, strokeWidth: 2));
    await t.tapAt(const Offset(700, 500)); // a click: back to no ring
    await t.pump();
    expect(ring(), paintsNothing);
  });

  testWidgets('Settings: its sections listed beside it, a click goes to one', (t) async {
    await pumpDesktop(t, '/settings');
    await t.pump();
    // the index (left of the page column), in the page's order
    final small = Theme.of(t.element(find.byType(Scaffold).last)).textTheme.labelLarge?.fontSize;
    Finder entry(String name) =>
        find.byWidgetPredicate((w) => w is Text && w.data == name && w.style?.fontSize == small);
    for (final name in ['Server', 'Your devices', 'Desktop', 'Playback', 'About']) {
      expect(entry(name), findsOneWidget, reason: name);
    }
    expect(t.getTopLeft(entry('Server')).dy, lessThan(t.getTopLeft(entry('About')).dy));
    final about = find.descendant(
      of: find.byType(SectionTitle, skipOffstage: false),
      matching: find.text('About', skipOffstage: false),
      skipOffstage: false,
    );
    expect(t.getTopLeft(about).dy, greaterThan(800)); // far down the page
    await t.tap(entry('About'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(about).dy, lessThan(800)); // scrolled to it
  });
}
