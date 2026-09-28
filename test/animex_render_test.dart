import 'dart:io';
import 'dart:ui' as ui;

import 'package:dailyanimelist/animex/animex_meta.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/screens/generalsearchscreen.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/widgets/home/animecard.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the real [AnimeGridCard] against the real bundled asset and writes
/// a PNG.
///
/// This exists because the accent bar, the airing label and the colour fallback
/// are visual properties. Compilation cannot check them and neither can a
/// headless unit test - the only honest way to know whether a grid of
/// 19,000-derived colours looks intentional or looks like a bag of sweets is to
/// rasterise it and look.
///
/// It deliberately does NOT use `matchesGoldenFile`. Golden comparison is
/// platform-sensitive (font rasterisation differs between the CI runner and any
/// other machine) and a cosmetic diff would break the build for no real gain.
/// Instead the assertion is "it rendered without throwing", and the PNG is
/// written out for a human or an AI to inspect.
void main() {
  setUpAll(() async {
    // Card internals read these two globals. `user` is a settable top-level
    // `late` in main.dart, and an empty JSON blob yields default preferences.
    user = User.fromJson({});
    await S.load(const Locale('en'));

    final file = File('assets/animex_meta.json');
    expect(file.existsSync(), isTrue,
        reason: 'assets/animex_meta.json missing - the feature is dead');
    AnimeXService.i.debugLoadFromString(file.readAsStringSync());
  });

  testWidgets('accent colours and airing label render on the real card',
      (tester) async {
    // Titles chosen to cover every branch that matters:
    //  - 9253 has a very pale dominant colour (#FFD6AE). A light accent is the
    //    case most likely to look broken against a dark card.
    //  - 21 has a real colour AND an airing schedule, so it shows the countdown
    //    label in the time bar.
    //  - 36055 has NO colour in the dataset, so it exercises the derived hue.
    //  - 1, 5114, 20583, 30240, 32928 are ordinary real-colour titles.
    const ids = [9253, 21, 36055, 1, 5114, 20583, 30240, 32928];

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cards = <Widget>[];
    for (final id in ids) {
      final meta = AnimeXService.i.metaOf(id);
      cards.add(
        AnimeGridCard(
          node: Node(id: id, title: '#$id ${meta?.status ?? ''}'.trim()),
          category: 'anime',
          displaySubType: DisplaySubType.cover_only_grid,
          // Only the airing title opts in, mirroring that no production call
          // site currently passes showTime: true.
          showTime: id == 21,
          borderRadius: 6,
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF151515),
        ),
        home: Scaffold(
          // Must be a RepaintBoundary, not a bare Container: toImage() needs a
          // RenderRepaintBoundary and a Container is a _RenderColoredBox.
          body: RepaintBoundary(
            key: const Key('shot'),
            child: ColoredBox(
              color: const Color(0xFF151515),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: GridView.count(
                  crossAxisCount: 4,
                  childAspectRatio: 0.68,
                  children: cards,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Images cannot load (no network in a test), but the accent bar and the
    // time bar are drawn locally and must still be in the tree.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AnimeGridCard), findsNWidgets(ids.length));
    expect(tester.takeException(), isNull,
        reason: 'rendering a card threw');

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(data, isNotNull);

    await tester.runAsync(() async {
      final out = File('test_output/animex_cards.png');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(data!.buffer.asUint8List());
      stdout.writeln('wrote ${out.path} '
          '(${out.lengthSync()} bytes)');
    });
  });

  test('every sampled id produces a visible, non-black accent', () {
    // Guards the "does it actually show anything" question numerically, so a
    // regression to a transparent or pure-black accent fails even if nobody
    // looks at the PNG.
    //
    // computeLuminance() is on a 0..1 scale. Note Color.r/g/b are ALSO 0..1
    // doubles in current Flutter, not 0..255 - a 0..255 weighting formula on
    // them returns ~0.86 for every colour and silently passes nothing.
    for (final id in [9253, 21, 36055, 1, 5114, 20583, 30240, 32928]) {
      final c = AnimeXService.i.accentOf(id);
      expect(c.a, 1.0, reason: 'id $id accent is not opaque');
      final luma = c.computeLuminance();
      expect(luma, greaterThan(0.03), reason: 'id $id accent is near-black');
      expect(luma, lessThan(0.97), reason: 'id $id accent is near-white');
    }
  });
}
