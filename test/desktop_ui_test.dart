// The desktop window's look and feel (the UI audit's changes), on the real shell and screens with a pretend
// server and player (support/ui_rig.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
}
