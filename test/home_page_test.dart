import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/staged_edit.dart';
import 'package:slab_steward/src/model/trail.dart';
import 'package:slab_steward/src/state/steward_state.dart';
import 'package:slab_steward/src/ui/account_panel.dart';
import 'package:slab_steward/src/ui/home_page.dart';
import 'package:slab_steward/src/ui/slab_theme.dart';

/// The landing page is the first thing a rider sees and the only place the
/// account requirement is explained before they start editing a public
/// database. What's tested here is that the page keeps its two promises — the
/// way to the map, and the instructions — not how it looks.

Future<StewardState> pumpHome(
  WidgetTester tester, {
  StewardState? state,
  VoidCallback? onOpenMap,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Only dispose what this helper made: a caller that brought its own state
  // has already registered a teardown for it, and disposing twice throws.
  final s = state ?? StewardState();
  if (state == null) addTearDown(s.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: slabTheme(),
      home: StewardHomePage(state: s, onOpenMap: onOpenMap ?? () {}),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

/// A staged edit, so the page has something to notice.
StagedEdit _staged() => StagedEdit.difficulty(
  const Trail(
    osmWayId: 42,
    tags: {'highway': 'path', 'name': 'Gravy Train'},
    isAuthoritative: true,
  ),
  Difficulty.medium,
);

void main() {
  testWidgets('the page says what Steward does and offers the map', (
    tester,
  ) async {
    var opened = 0;
    await pumpHome(tester, onOpenMap: () => opened++);

    // The summary, in the hero.
    expect(find.textContaining('guided editor'), findsOneWidget);
    expect(find.textContaining('under your own account'), findsOneWidget);

    // Three ways to the map — the top bar, the hero and the closing band —
    // because the page is long enough that any one of them is off screen most
    // of the time.
    final toMap = find.widgetWithText(FilledButton, 'Open the map');
    expect(toMap, findsNWidgets(3));

    await tester.tap(toMap.first);
    await tester.pumpAndSettle();
    expect(opened, 1, reason: 'the CTA opens the map');
  });

  testWidgets('the map button says the staged work survived', (tester) async {
    final state = StewardState();
    addTearDown(state.dispose);
    await pumpHome(tester, state: state);

    // Nothing staged: the plain invitation.
    expect(find.textContaining('Back to the map'), findsNothing);

    // A rider who pressed the brand mark mid-edit lands here, and the button
    // is where they'll be looking for reassurance that the work is still
    // there.
    state.stageEdit(_staged());
    await tester.pumpAndSettle();
    expect(find.text('Back to the map · 1 staged edit'), findsOneWidget);
  });

  group('Getting started', () {
    testWidgets('leads with the account requirement, already open', (
      tester,
    ) async {
      await pumpHome(tester);

      // The heading states it, and the first step is expanded on load: this
      // is the one thing that is not optional.
      expect(
        find.textContaining('You will need an\nOpenStreetMap account.'),
        findsOneWidget,
      );
      expect(find.text('Get an OpenStreetMap account'), findsOneWidget);
      expect(
        find.textContaining('it signs in as you rather than on your behalf'),
        findsOneWidget,
        reason: 'step 1 is open without being asked',
      );
      expect(
        find.text('Create an account on openstreetmap.org'),
        findsOneWidget,
      );
    });

    testWidgets('the other steps open on a tap, and stay open together', (
      tester,
    ) async {
      await pumpHome(tester);

      const submitBody = 'a changeset comment saying what you changed';
      const signInBody = 'You type your password on their site';
      expect(find.textContaining(submitBody), findsNothing);

      Future<void> openStep(String title) async {
        final step = find.text(title);
        await tester.ensureVisible(step);
        await tester.pumpAndSettle();
        // The top bar floats over the page, so a row that ensureVisible
        // parked flush with the top of the viewport would be tapped through
        // it. Nudge it clear first.
        final dy = tester.getCenter(step).dy;
        if (dy < 140) {
          await tester.drag(
            find.byType(SingleChildScrollView),
            Offset(0, 140 - dy),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(step);
        await tester.pumpAndSettle();
      }

      await openStep('Review, then submit');
      expect(find.textContaining(submitBody), findsOneWidget);

      // Instructions are followed side by side, so opening one must not close
      // another — these are steps, not an accordion.
      await openStep('Sign in to Steward');
      expect(find.textContaining(signInBody), findsOneWidget);
      expect(find.textContaining(submitBody), findsOneWidget);

      // And a second tap closes the one that was tapped.
      await openStep('Review, then submit');
      expect(find.textContaining(submitBody), findsNothing);
      expect(find.textContaining(signInBody), findsOneWidget);
    });

    testWidgets('it explains submitting, not just signing up', (tester) async {
      await pumpHome(tester);

      // Collapsed, every step still names itself — the summaries are the
      // contents page for someone who only needs one of them.
      for (final step in [
        'Sign in to Steward',
        'Find a trail you know',
        'Rate only what you actually know',
        'Review, then submit',
        'After it goes out',
      ]) {
        expect(find.text(step), findsOneWidget, reason: '"$step" is listed');
      }
    });
  });

  group('the footer', () {
    testWidgets('carries the name, the licence and the OSM attribution', (
      tester,
    ) async {
      await pumpHome(tester);

      // The brand mark and wordmark appear twice: top bar and footer.
      expect(find.text('SLAB STEWARD'), findsNWidgets(2));
      expect(find.text('© 2026 SLAB Steward · MIT licensed'), findsOneWidget);
      // Not decoration — ODbL requires visible credit wherever the data is
      // shown, and this page is part of what is showing it.
      expect(
        find.textContaining('Trail data © OpenStreetMap contributors, ODbL'),
        findsOneWidget,
      );
    });

    testWidgets('the privacy link shows the statement the app already makes', (
      tester,
    ) async {
      await pumpHome(tester);

      final privacy = find.text('Privacy');
      await tester.ensureVisible(privacy);
      await tester.pumpAndSettle();
      await tester.tap(privacy);
      await tester.pumpAndSettle();

      // The same widget the Account pane ends with, so the two can't drift
      // into saying different things.
      expect(find.byType(PrivacyNote), findsOneWidget);
      expect(
        find.textContaining("It doesn't record your screen"),
        findsOneWidget,
      );
    });
  });

  testWidgets('the whole page survives a phone-shaped window', (tester) async {
    await pumpHome(tester, size: const Size(390, 844));

    expect(tester.takeException(), isNull, reason: 'nothing overflowed');
    // The narrow top bar drops the text link and keeps the one control that
    // matters, so there is still exactly one way to the map above the fold.
    expect(find.widgetWithText(FilledButton, 'Open the map'), findsWidgets);
    expect(find.text('Get an OpenStreetMap account'), findsOneWidget);
  });
}
