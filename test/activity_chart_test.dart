import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/steward_stats.dart';
import 'package:slab_steward/src/osm/osm_api.dart';
import 'package:slab_steward/src/ui/activity_chart.dart';
import 'package:slab_steward/src/ui/slab_theme.dart';

/// A changeset made at 9pm local on the day [daysAgo] days back, carried as
/// the UTC instant OSM would actually return. West of Greenwich that lands on
/// the *following* UTC date, which is the case every window here has to get
/// right.
OsmChangeset _eveningEdit(int daysAgo, {int trails = 2}) {
  final now = DateTime.now();
  final local = DateTime(now.year, now.month, now.day - daysAgo, 21, 0);
  return OsmChangeset(
    id: daysAgo,
    createdAt: local.toUtc(),
    changesCount: trails,
  );
}

Future<void> _pump(WidgetTester tester, StewardStats stats) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: slabTheme(),
      home: Scaffold(
        body: SingleChildScrollView(child: ActivitySection(stats: stats)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String range) async {
  await tester.tap(find.text(range));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an edit made this evening lands in every window that ends '
      'today, not just the week', (tester) async {
    // The reported bug: Week showed the edit but Month and All read empty,
    // because the day was bucketed on its UTC date.
    // Three changesets tonight, touching 30 trails between them — the plotted
    // value is trails, not the number of changesets.
    final stats = StewardStats.from([
      _eveningEdit(0, trails: 5),
      _eveningEdit(0, trails: 10),
      _eveningEdit(0, trails: 15),
    ]);
    await _pump(tester, stats);

    expect(find.text('30 trails touched in this window'), findsOne);
    expect(find.text('1 active day this week'), findsOne);

    await _select(tester, 'Month');
    expect(find.text('30 trails touched in this window'), findsOne);
    expect(find.text('1 active day in the last 30 days'), findsOne);

    await _select(tester, '1y');
    expect(find.text('30 trails touched in this window'), findsOne);
    expect(find.text('1 active month in the last 12 months'), findsOne);

    await _select(tester, 'All');
    expect(find.text('30 trails touched in this window'), findsOne);
    expect(find.text('1 active month overall', skipOffstage: false), findsOne);
  });

  testWidgets('a window with nothing in it says so rather than drawing a '
      'broken axis', (tester) async {
    // Edits old enough to be outside the week and month windows, but still
    // inside the year — each range should report its own window honestly.
    final stats = StewardStats.from([
      _eveningEdit(60, trails: 4),
      _eveningEdit(61, trails: 3),
    ]);
    await _pump(tester, stats);

    expect(find.text('0 trails touched in this window'), findsOne);
    expect(find.text('0 active days this week'), findsOne);

    await _select(tester, 'Month');
    expect(find.text('0 trails touched in this window'), findsOne);

    await _select(tester, '1y');
    expect(find.text('7 trails touched in this window'), findsOne);
  });

  testWidgets('the whole history fits on a chart even when it is one day old',
      (tester) async {
    // A single bucket used to paint nothing at all, so "All" came up blank
    // for anyone who had just started.
    final stats = StewardStats.from([_eveningEdit(0, trails: 1)]);
    await _pump(tester, stats);
    await _select(tester, 'All');

    expect(find.text('1 trail touched in this window'), findsOne);
    expect(find.byType(ActivitySection), findsOne);
  });
}
