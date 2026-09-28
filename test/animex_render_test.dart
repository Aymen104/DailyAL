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

    // Two minutes, not the default ten. A pending image retry timer shows up as
    // a hang, and waiting ten minutes for it tells you nothing more than waiting
    // two does.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cards = <Widget>[];
    for (final id in ids) {
      final meta = AnimeXService.i.metaOf(id);
      cards.add(
        AnimeGridCard(
          node: Node(
            id: id,
            title: '#$id ${meta?.status ?? ''}'.trim(),
            // mainPicture is deliberately left null. The card then draws its
            // local "no image" placeholder instead of a CachedNetworkImage, and
            // that is the difference between a test that finishes and one that
            // hangs: the image widget schedules retry timers that never drain,
            // so the test framework sits waiting until it hits the 10 minute
            // timeout. The accent bar and the time bar are painted locally and
            // are unaffected - they are the only two things under test.
            mainPicture: null,
          ),
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

    // The card's no-image placeholder is an Image.asset, and asset resolution
    // is REAL file I/O. testWidgets runs the body inside a fake-async zone where
    // real I/O can never complete, so that future is still outstanding when the
    // body returns and the test then hangs until the timeout - with no
    // diagnostic, because nothing threw. runAsync is the one place inside a
    // widget test where the real event loop runs, so give it a window to land.
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 500)));
    await tester.pump();

    expect(find.byType(AnimeGridCard), findsNWidgets(ids.length));
    expect(tester.takeException(), isNull,
        reason: 'rendering a card threw');

    // "Did not throw" is a weak claim. Assert the two surfaces under test are
    // actually painted: one accent Container per card, each carrying the exact
    // colour accentOf returned, and the airing label on the one card that opted
    // into showTime.
    for (final id in ids) {
      expect(
        find.byWidgetPredicate((w) =>
            w is Container && w.color == AnimeXService.i.accentOf(id)),
        findsWidgets,
        reason: 'no accent bar painted for id $id '
            '(${AnimeXService.i.accentOf(id)})',
      );
    }
    expect(
      find.textContaining('EP'),
      findsAtLeastNWidgets(1),
      reason: 'the airing countdown never reached the time bar',
    );

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    // Dispose rather than dropping the reference: a live ui.Image holds a
    // handle that keeps the test's async guard open.
    image.dispose();
    expect(data, isNotNull);

    // Synchronous I/O on purpose. The bytes are already in memory, so there is
    // no reason to reach for runAsync - and a second runAsync is a good way to
    // leave the test's async guard open, which shows up as a hang after a body
    // that has plainly finished.
    final out = File('test_output/animex_cards.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(data!.buffer.asUint8List());
    stdout.writeln('wrote ${out.path} (${out.lengthSync()} bytes)');

    // Unmount before returning. A live tree holds scroll positions, image
    // handles and any ticker its widgets own; the framework will not complete
    // the test while those are still attached.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 2)));

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
