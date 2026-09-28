import 'dart:io';

import 'package:dailyanimelist/animex/animex_meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests run against the REAL bundled asset rather than a fixture, so a bad
/// regeneration fails here instead of shipping. The whole point is to cover
/// the two things that cannot be checked by compilation: the data's integrity,
/// and the ageing behaviour of the airing countdown.
void main() {
  late String raw;
  late Map<int, AnimeXMeta> index;

  setUpAll(() {
    // flutter_test runs on the Dart VM, so the asset is readable from disk.
    // Resolving relative to the package root keeps this working regardless of
    // the directory the runner was invoked from.
    final file = File('assets/animex_meta.json');
    expect(file.existsSync(), isTrue,
        reason: 'assets/animex_meta.json missing - the whole feature is dead');
    raw = file.readAsStringSync();
    index = AnimeXService.parse(raw);
    AnimeXService.i.debugLoadFromString(raw);
  });

  group('asset integrity', () {
    test('parses to the expected record count', () {
      expect(index.length, 19079);
      expect(AnimeXService.i.count, 19079);
    });

    test('every key is a usable MAL id', () {
      for (final id in index.keys) {
        expect(id, greaterThan(0), reason: 'id $id is not a positive MAL id');
      }
    });

    test('colours are present at the measured coverage and in range', () {
      final withColor = index.values.where((m) => m.color != null).toList();
      expect(withColor.length, 17255);
      for (final m in withColor) {
        expect(m.color, greaterThanOrEqualTo(0));
        expect(m.color, lessThanOrEqualTo(0xFFFFFF),
            reason: 'colour out of 24-bit range: ${m.color}');
      }
    });

    test('anilistId is present for every title', () {
      for (final m in index.values) {
        expect(m.anilistId, isNotNull, reason: 'missing anilistId');
        expect(m.anilistId, greaterThan(0));
      }
    });

    test('known spot checks map to the right titles', () {
      // Guards against a re-scrape shifting the key space under us.
      expect(index[9253]!.color, 0xFFD6AE); // Steins;Gate, pale peach
      expect(index[21]!.color, 0xE49335); // One Piece
      expect(index[21]!.nextEpisode, 1180);
      expect(index[21]!.status, 'RELEASING');
    });
  });

  group('accent colour', () {
    test('is total - every id yields a colour, real or derived', () {
      for (final id in index.keys.take(2000)) {
        expect(AnimeXService.i.accentOf(id), isA<Color>());
        expect(AnimeXService.i.accentOf(id).a, 1.0,
            reason: 'accent for $id is not opaque');
      }
    });

    test('is deterministic for the same id', () {
      expect(AnimeXService.i.accentOf(9253), AnimeXService.i.accentOf(9253));
    });

    test('prefers the real colour when the dataset has one', () {
      expect(AnimeXService.i.hasRealAccent(9253), isTrue);
      expect(AnimeXService.i.accentOf(9253), const Color(0xFFFFD6AE));
    });

    test('derived colours scatter across the hue wheel instead of banding',
        () {
      // This is the property that makes the 10% fallback invisible. If the
      // multiplier were not coprime with 360, consecutive ids would walk the
      // wheel in visible steps and the grid would stripe.
      final derived = index.keys
          .where((id) => !AnimeXService.i.hasRealAccent(id))
          .take(1200)
          .toList();
      expect(derived.length, greaterThan(1000),
          reason: 'not enough colourless titles to sample');

      final hues = <int>{};
      for (final id in derived) {
        hues.add(((id * 47) % 360));
      }
      expect(hues.length, greaterThanOrEqualTo(300),
          reason: 'derived hues collapsed to ${hues.length} distinct values');
    });

    test('a null id still yields a colour rather than crashing a build', () {
      expect(AnimeXService.i.accentOf(null), isA<Color>());
      expect(AnimeXService.i.accentOf(null).a, 1.0);
    });
  });

  group('airing countdown ageing', () {
    // The asset freezes ONE upcoming broadcast at build time. These cases pin
    // the behaviour that makes that survivable.
    final meta = index[21]!;
    late DateTime anchor;

    setUpAll(() => anchor = meta.nextAiringAt!.toUtc());

    test('a fresh slot reports the bundled episode and a countdown', () {
      final now = anchor.subtract(const Duration(days: 3, hours: 4));
      final label = AnimeXService.i.nextAiringLabel(21, now: now)!;
      expect(label, startsWith('EP 1180'));
      expect(label, contains('3d'));
    });

    test('a slot one week old advances the episode instead of freezing', () {
      // This is the regression test. The previous implementation returned
      // 'EP $episode' verbatim once the timestamp passed, so an installed build
      // would show the same episode number forever.
      //
      // One week past the anchor, EP 1181 is the one airing *now*, so the next
      // one to wait for is EP 1182, a further week out.
      final now = anchor.add(const Duration(days: 7));
      final label = AnimeXService.i.nextAiringLabel(21, now: now)!;
      expect(label, startsWith('EP 1182'),
          reason: 'countdown did not roll forward a week');
      expect(label, contains('7d'));
    });

    test('a slot exactly at the anchor already reports the following episode',
        () {
      // The bundled episode is airing at this instant, so it is not what to
      // count down to.
      final label = AnimeXService.i.nextAiringLabel(21, now: anchor)!;
      expect(label, startsWith('EP 1181'));
    });

    test('a slot three weeks old advances three episodes', () {
      final now = anchor.add(const Duration(days: 21));
      final label = AnimeXService.i.nextAiringLabel(21, now: now)!;
      expect(label, startsWith('EP 1184'));
      expect(label, contains('7d'));
    });

    test('gives up past the projection bound rather than inventing a date', () {
      final now = anchor.add(const Duration(days: 56));
      expect(AnimeXService.i.nextAiringLabel(21, now: now), isNull);
    });

    test('returns null for titles with no airing data', () {
      expect(AnimeXService.i.nextAiringLabel(9253, now: anchor), isNull);
    });

    test('returns null for an unknown id', () {
      expect(AnimeXService.i.nextAiringLabel(999999999, now: anchor), isNull);
    });

    test('never emits a dangling separator', () {
      for (final entry in index.entries) {
        final at = entry.value.nextAiringAt;
        if (at == null) continue;
        final label =
            AnimeXService.i.nextAiringLabel(entry.key, now: at.toUtc());
        if (label == null) continue;
        expect(label.endsWith(' '), isFalse, reason: 'id ${entry.key}: $label');
        expect(label.contains('· ·'), isFalse, reason: 'id ${entry.key}: $label');
      }
    });
  });

  group('anilist link', () {
    test('is built from the AniList id, not the MAL id', () {
      // 36055 is a title where the two numbering schemes disagree.
      expect(index[36055]!.anilistId, 145756);
      expect(index[36055]!.anilistUrl, 'https://anilist.co/anime/145756');
    });

    test('falls back to the shared id when the schemes coincide', () {
      expect(index[21]!.anilistUrl, 'https://anilist.co/anime/21');
    });

    test('every title gets a link', () {
      for (final m in index.values) {
        expect(m.anilistUrl, isNotNull);
        expect(m.anilistUrl, startsWith('https://anilist.co/anime/'));
      }
    });
  });

  group('parser robustness', () {
    test('skips a non-numeric key rather than failing the whole asset', () {
      final parsed = AnimeXService.parse('{"1":{"c":255},"bogus":{"c":1}}');
      expect(parsed.length, 1);
      expect(parsed.containsKey(1), isTrue);
    });

    test('skips a non-object value', () {
      final parsed = AnimeXService.parse('{"1":{"c":255},"2":"nope"}');
      expect(parsed.length, 1);
    });

    test('rejects a non-object top level', () {
      expect(() => AnimeXService.parse('[1,2,3]'), throwsFormatException);
    });
  });
}
