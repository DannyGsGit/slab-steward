import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../osm/osm_environment.dart';
import '../state/steward_state.dart';
import 'account_panel.dart' show AccountAvatar, PrivacyNote;
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// The landing page — what a rider sees before the map.
///
/// Steward used to open straight onto the editor, which is the right screen
/// for the second visit and the wrong one for the first: the map answers
/// "where" long before anything has answered "what is this, and what will it
/// do with my OpenStreetMap account". Those two questions have to be settled
/// *before* someone starts editing a public database under their own name,
/// and a panel inside the editor is too late to ask them.
///
/// Shaped after onX's own landing page — a full-bleed hero over a photograph,
/// then a column of sections that each make one claim — and painted in the
/// SLAB palette from [SlabColors] rather than onX's. Nothing here is a new
/// colour, a new radius or a new type size; it is the same design system the
/// panes wear, at landing-page scale.
///
/// The one thing this page has that no pane does is [_GettingStarted]: the
/// account requirement and the submit flow, written out in full, expandable so
/// the page still reads as a page for someone who already knows.
class StewardHomePage extends StatefulWidget {
  const StewardHomePage({
    super.key,
    required this.state,
    required this.onOpenMap,
  });

  /// Read, never written. The page asks it one question — is there staged work
  /// to come back to — so that a rider who clicked the brand mark by mistake
  /// is told their edits are still there rather than left to guess.
  final StewardState state;

  final VoidCallback onOpenMap;

  @override
  State<StewardHomePage> createState() => _StewardHomePageState();
}

/// The widest the text column ever gets. Past this a line of body copy stops
/// being readable, however much window there is.
const _maxContentWidth = 1120.0;

/// Below this the page is one column: the hero shortens, the feature cards
/// stack, and the footer's link groups wrap under the brand block.
const _wideAbove = 900.0;

/// The bar's height, which is also how much clear air the hero owes it.
const _topBarHeight = 72.0;

class _StewardHomePageState extends State<StewardHomePage> {
  final _scroll = ScrollController();

  /// Anchors "Getting started" in both the top bar and the hero.
  final _gettingStartedKey = GlobalKey();

  /// Whether the top bar has anything under it yet. Transparent over the hero
  /// photograph and filled once the page has scrolled — the same trick onX
  /// plays, and the reason the bar can sit *on* the hero rather than above it.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final scrolled = _scroll.offset > 8;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  Future<void> _toGettingStarted() async {
    final target = _gettingStartedKey.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      // Land the heading just below the top bar rather than under it.
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      alignment: 0.06,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SlabColors.ink950,
      body: Stack(
        children: [
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                children: [
                  _Hero(
                    state: widget.state,
                    onOpenMap: widget.onOpenMap,
                    onGettingStarted: _toGettingStarted,
                  ),
                  const _WhatItDoes(),
                  _GettingStarted(
                    key: _gettingStartedKey,
                    onOpenMap: widget.onOpenMap,
                  ),
                  _ClosingCta(onOpenMap: widget.onOpenMap),
                  _Footer(
                    onOpenMap: widget.onOpenMap,
                    onGettingStarted: _toGettingStarted,
                  ),
                ],
              ),
            ),
          ),
          _TopBar(
            filled: _scrolled,
            onOpenMap: widget.onOpenMap,
            onGettingStarted: _toGettingStarted,
          ),
        ],
      ),
    );
  }
}

/// Opens an external page. Every link on this page leaves the app — there is
/// nowhere else in Steward to send someone — so they all come through here.
Future<void> _open(String url) => launchUrl(Uri.parse(url));

/// The links this page hands out, named once.
abstract final class _Links {
  static const newAccount = 'https://www.openstreetmap.org/user/new';
  static const osm = osmWebHost;
  static const wiki = 'https://wiki.openstreetmap.org/wiki/Slab_Steward';
  static const organisedEditing =
      'https://wiki.openstreetmap.org/wiki/Organised_Editing_Guidelines';
  static const goodComments =
      'https://wiki.openstreetmap.org/wiki/Good_changeset_comments';
  static const copyright = 'https://www.openstreetmap.org/copyright';
  static const source = 'https://github.com/DannyGsGit/slab-steward';
}

/// The brand mark and the wordmark beside it, as the page's own header uses
/// them. The mark alone is the rail's; here there is usually room to say the
/// name as well.
class _Wordmark extends StatelessWidget {
  const _Wordmark({this.markSize = 32, this.showName = true});

  final double markSize;

  /// The name is the first thing to go on a narrow window. Letter-spaced to
  /// three points it is wider than everything else in the top bar put
  /// together, and the mark on its own is still the mark — the same trade the
  /// bottom bar makes when it drops the brand from the rail.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.asset(
            'assets/slab/logo.png',
            width: markSize,
            height: markSize,
            filterQuality: FilterQuality.medium,
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 11),
          // Flexible and ellipsised as well as conditional: showName answers
          // the common case, and this makes the uncommon one degrade instead
          // of overflowing.
          const Flexible(
            child: Text(
              'SLAB STEWARD',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                // The design doc's logo treatment: gold, and spaced out far
                // enough to read as a mark rather than as a word in a
                // sentence.
                letterSpacing: 3.2,
                color: SlabColors.gold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The page's own navigation: the wordmark, and the two things there are to
/// do. Sits on the hero photograph and fills in once the page scrolls.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.filled,
    required this.onOpenMap,
    required this.onGettingStarted,
  });

  final bool filled;
  final VoidCallback onOpenMap;
  final VoidCallback onGettingStarted;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideAbove;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: _topBarHeight,
      decoration: BoxDecoration(
        color: filled ? SlabColors.overlay : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: filled ? SlabColors.line : Colors.transparent,
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Flexible(child: _Wordmark(showName: wide)),
                const Spacer(),
                // A narrow window keeps only the one control that matters.
                // "Getting started" is still a tap away in the hero.
                if (wide) ...[
                  TextButton(
                    onPressed: onGettingStarted,
                    child: const Text('Getting started'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: onOpenMap,
                  child: const Text('Open the map'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The photograph, the claim, and the way in.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.state,
    required this.onOpenMap,
    required this.onGettingStarted,
  });

  final StewardState state;
  final VoidCallback onOpenMap;
  final VoidCallback onGettingStarted;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= _wideAbove;
    // Tall enough to be a hero, never taller than the window — a landing page
    // whose first screen doesn't hint at a second one reads as the whole site.
    //
    // A *minimum*, not a height. A wide, short window (a laptop with the dock
    // and two toolbars, or a browser dragged into a letterbox) leaves less
    // room than the headline and its two paragraphs need, and a hero that
    // clips its own call to action is worse than one that runs a little past
    // the fold. The content is the Stack's only unpositioned child, so it
    // sizes the band and everything else fills whatever it decided.
    final minHeight = wide
        ? (size.height * 0.80).clamp(500.0, 680.0)
        : (size.height * 0.76).clamp(430.0, 600.0);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        // The content is the Stack's only unpositioned child, so this is what
        // centres it in the band when the band is taller than the text needs
        // — which is the usual case, and the whole reason for the minimum.
        alignment: Alignment.center,
        children: [
          // Placeholder artwork from the SLAB handoff folder — see the
          // README. Cover-cropped, so its aspect ratio never dictates the
          // hero's.
          Positioned.fill(
            child: Image.asset(
              'assets/slab/trail_hero.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              filterQuality: FilterQuality.medium,
            ),
          ),
          // Two scrims, doing two different jobs. The vertical one lands the
          // photograph on the page's own ground so the hero has no seam at its
          // foot; the horizontal one buys contrast for the text without
          // dimming the whole picture.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8C0B1420),
                    Color(0x1A0B1420),
                    Color(0xB30B1420),
                    SlabColors.ink950,
                  ],
                  // Dark at the top so the bar's own text clears, barely
                  // anything through the middle where the light in the
                  // photograph is, and solid at the very bottom so the band
                  // has no seam where it meets the page.
                  stops: [0, 0.42, 0.86, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xD90B1420), Color(0x000B1420)],
                  stops: [0.04, 0.62],
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  24,
                  _topBarHeight + 32,
                  24,
                  48,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AN OPENSTREETMAP TRAIL EDITOR',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: SlabColors.gold),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Trail rating\nfor everyone.',
                          style: TextStyle(
                            fontSize: wide ? 56 : 38,
                            height: 1.04,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                            color: SlabColors.cream,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'The SLAB project is built on a simple principle: Trail data should not be paywalled. '
                          'Steward is SLAB\'s guided editor for OSM trail data, making sure that every community contribution '
                          'is free & open forever. '
                          'Find a trail, tag it, and send the change to '
                          '$osmLabel under your own account, no need to learn'
                          'the ins & outs of tags.',
                          style: TextStyle(
                            fontSize: wide ? 16.5 : 15,
                            height: 1.6,
                            color: SlabColors.cream.withValues(alpha: 0.86),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Wrap rather than Row: at 380 logical pixels the two
                        // buttons don't fit on one line, and a clipped CTA is
                        // the one thing this page cannot afford.
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MapButton(state: state, onOpenMap: onOpenMap),
                            OutlinedButton(
                              onPressed: onGettingStarted,
                              child: const Text('Getting started'),
                            ),
                          ],
                        ),
                        // const SizedBox(height: 20),
                        // Text(
                        //   'Free, and there is no Steward account to make. '
                        //   'Your edits go out in your name.',
                        //   style: Theme.of(context).textTheme.bodySmall
                        //       ?.copyWith(color: SlabColors.sage),
                        // ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary call to action, which knows whether this is a first visit.
///
/// Someone who clicked the brand mark from the editor arrives here with staged
/// edits still in hand, and the thing they most need to know is that the work
/// survived. Saying it on the button is cheaper than a banner, and it is
/// exactly where they are already looking.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.state, required this.onOpenMap});

  final StewardState state;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final staged = state.stagedEditCount;
        return FilledButton.icon(
          onPressed: onOpenMap,
          icon: const Icon(Icons.map_outlined, size: 18),
          label: Text(
            staged == 0
                ? 'Open the map'
                : 'Back to the map · $staged staged '
                      '${staged == 1 ? 'edit' : 'edits'}',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 26),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

/// A band down the page: the gold eyebrow, the claim, and whatever the section
/// is actually showing.
///
/// Every section below is one of these, so they cannot drift into six
/// different rhythms.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.title,
    required this.child,
    this.blurb,
    this.background,
    this.topBorder = true,
  });

  final String label;
  final String title;
  final String? blurb;
  final Widget child;
  final Color? background;

  /// The hairline that separates this band from the one above it.
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideAbove;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        border: topBorder
            ? const Border(top: BorderSide(color: SlabColors.line))
            : null,
      ),
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: wide ? 78 : 52),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  fontSize: wide ? 34 : 26,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                  color: SlabColors.cream,
                ),
              ),
              if (blurb case final blurb?) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Text(
                    blurb,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.65,
                      color: SlabColors.sage,
                    ),
                  ),
                ),
              ],
              SizedBox(height: wide ? 44 : 32),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// onX's repeating feature card, in SLAB's ink: a glyph, a claim, and the
/// sentence that backs it up.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SlabSurface(
      color: SlabColors.ink800,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SlabColors.goldSoft,
              borderRadius: BorderRadius.circular(SlabRadii.control),
            ),
            child: Icon(icon, size: 21, color: SlabColors.gold),
          ),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.62,
              color: SlabColors.sage,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the tool is, in four claims.
class _WhatItDoes extends StatelessWidget {
  const _WhatItDoes();

  static const _cards = [
    (
      icon: Icons.travel_explore,
      title: 'Find the trail',
      body:
          "The map draws OpenStreetMap's trails to OpenTrailMap's conventions "
          'and highlights them according to missing metadata.',
    ),
    (
      icon: Icons.signpost_outlined,
      title: 'Tag, simply',
      body:
          'Difficulty is the circle, square and diamond scale off the '
          'trailhead sign. E-bike access is set according to regional terms.',
    ),
    (
      icon: Icons.select_all,
      title: 'Rate a whole network',
      body:
          'Drag a box around a group of similar trails to edit in bulk.',
    ),
    (
      icon: Icons.cloud_upload_outlined,
      title: 'Submit to OSM',
      body:
          'When you\'re ready, your edits pass a validation check '
          'and go to $osmLabel one changeset.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _Section(
      label: 'WHAT STEWARD DOES',
      title: 'The trail data is only as good\nas the riders who fix it.',
      blurb:
          'Editing $osmLabel metadata correctly and consistently has a learning curve. '
          'Steward hides the complexity to make it easy and efficient for anyone to '
          'enrich this open source database of trail data. ',
      topBorder: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four across on a desktop, two on a tablet, one on a phone — worked
          // out from the width rather than from a breakpoint, because the
          // number that matters is how wide a card ends up.
          final columns = switch (constraints.maxWidth) {
            >= 1000 => 4,
            >= 620 => 2,
            _ => 1,
          };
          const gap = 18.0;
          // Rows of Expandeds inside an IntrinsicHeight rather than a Wrap.
          // A Wrap lets every card shrink-wrap its own paragraph, and four
          // cards of four different heights read as four unrelated things
          // rather than as one set — which is the whole point of a card row.
          return Column(
            children: [
              for (var start = 0; start < _cards.length; start += columns) ...[
                if (start > 0) const SizedBox(height: gap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = start; i < start + columns; i++) ...[
                        if (i > start) const SizedBox(width: gap),
                        Expanded(
                          // A last row that doesn't fill keeps its empty
                          // slots, so the cards stay the width of the ones
                          // above rather than stretching to fill the gap.
                          child: i < _cards.length
                              ? _FeatureCard(
                                  icon: _cards[i].icon,
                                  title: _cards[i].title,
                                  body: _cards[i].body,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A caption beside a glyph, sized to sit next to it rather than under it.
const _captionStyle = TextStyle(fontSize: 13, color: SlabColors.sage);

/// A static echo of the sidebar's Staged rail button, badge and all — so this
/// page can show what "staged" looks like rather than only describe it.
class _StagedGlyph extends StatelessWidget {
  const _StagedGlyph({this.count = 0});

  final int count;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(
      Icons.check_circle_outline,
      size: 19,
      color: SlabColors.sageDim,
    );
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SlabColors.line, width: 1.5),
      ),
      child: count > 0 ? Badge.count(count: count, child: icon) : icon,
    );
  }
}

/// A quiet aside under a block — the thing worth knowing but not worth a
/// heading.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Icon(Icons.info_outline, size: 15, color: SlabColors.goldDim),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: SlabColors.sageDim,
          ),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Getting started
// ---------------------------------------------------------------------------

/// The onboarding, written out on the page rather than hidden behind a link.
///
/// Expandable because it has two readers and they want opposite things. A
/// mapper who already has an $osmLabel account needs to know only that Steward
/// uses it and where the sign-in is; someone who has never edited the map
/// needs the account, the OAuth popup, the verifiability standard and what
/// happens after submitting — and burying any of that behind a "docs" link
/// would be asking them to write to a public database on trust. Collapsed, it
/// is a six-line contents page; open, it is the whole thing.
///
/// The first step is expanded on load because it is the one that is not
/// optional: **there is no Steward account, and there cannot be an edit
/// without an OpenStreetMap one.**
class _GettingStarted extends StatefulWidget {
  const _GettingStarted({super.key, required this.onOpenMap});

  final VoidCallback onOpenMap;

  @override
  State<_GettingStarted> createState() => _GettingStartedState();
}

class _GettingStartedState extends State<_GettingStarted> {
  /// Which steps are open. A set rather than a single index: these are
  /// instructions to follow side by side, and an accordion that closes step 3
  /// when you open step 4 is actively unhelpful to someone working through
  /// them.
  final _open = <int>{0};

  void _toggle(int index) => setState(() {
    if (!_open.remove(index)) _open.add(index);
  });

  @override
  Widget build(BuildContext context) {
    final steps = _steps(context, widget.onOpenMap);
    return _Section(
      label: 'GETTING STARTED',
      title: 'You will need an\nOpenStreetMap account.',
      blurb:
          'Steward has no accounts of its own and never will. Every edit it '
          'sends is yours: your name on the changeset, in the public record, '
          'permanently.',
      background: SlabColors.ink900,
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: _LinkButton(
              label: 'Slab Steward on the OSM wiki',
              url: _Links.wiki,
            ),
          ),
          const SizedBox(height: 18),
          for (final (index, step) in steps.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            _ExpandableStep(
              number: index + 1,
              title: step.title,
              summary: step.summary,
              expanded: _open.contains(index),
              onToggle: () => _toggle(index),
              body: step.body,
            ),
          ],
        ],
      ),
    );
  }
}

typedef _Step = ({String title, String summary, List<Widget> body});

List<_Step> _steps(BuildContext context, VoidCallback onOpenMap) => [
  (
    title: 'Get an OpenStreetMap account',
    summary: 'Free, and the only account Steward uses.',
    body: [
      const _Para(
        'Making one takes about a minute and costs nothing. If you already '
        'edit OpenStreetMap, use the account you already have.',
      ),
      const _Bullet(
        'A display name, which is public and appears on every edit.',
      ),
      const _Bullet('An email address, which is not public.'),
      const _Bullet(
        'A confirmation link, which has to be clicked before the account can '
        'edit anything.',
      ),
      const SizedBox(height: 14),
      const _LinkButton(
        label: 'Create an account on openstreetmap.org',
        url: _Links.newAccount,
        primary: true,
      ),
    ],
  ),
  (
    title: 'Sign in to Steward',
    summary: 'One popup on openstreetmap.org.',
    body: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AccountAvatar(
            isSignedIn: false,
            isSigningIn: false,
            displayName: null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _Para(
              'Open the map, then look for this icon and '
              'press "Sign in to $osmLabel".'
              'A popup opens on $osmShortLabel and asks whether Steward may act for you.',
            ),
          ),
        ],
      ),
      const _Note(
        'If pressing the button appears to do nothing, your browser blocked '
        'the popup. Allow popups for this site and try again.',
      ),
    ],
  ),
  (
    title: 'Find a trail you know',
    summary: 'Pan, filter, and click. The map colours what is missing.',
    body: [
      const _Para(
        'The Map pane\'s filters decide what is drawn, in three groups:',
      ),
      const _Bullet('Access — which travel modes a trail must allow.'),
      const _Bullet('Include — which trail types are shown at all.'),
      const _Bullet(
        'Highlight — which gaps to flag; tick none for a plain map.',
      ),
      const SizedBox(height: 4),
      const _Para(
        'Colour tells you what a trail is missing rather than what it is: the '
        'default lenses are difficulty and e-bike access, so anything still '
        'unanswered stands out. "Trails in view" lists everything on screen '
        'with its gaps named, which is usually the faster way to work a '
        'network.',
      ),
    ],
  ),
  (
    title: 'Rate only what you actually know',
    summary: 'Difficulty and e-bike access, for one trail or fifty at once.',
    body: [
      const _Para(
        'Pick the difficulty from the signage scale and, if you know it, '
        'whether e-bikes may ride there. Answer "allowed" and a second picker '
        'asks up to which class, in the vocabulary used where the trail is.',
      ),
      const _Para(
        'To do a network at once, ctrl-click (cmd-click on a Mac) several '
        'trails, or hold the same key and drag a box across the map.',
      ),
      const _Warn(
        'Rate what you have ridden or seen signed. OpenStreetMap\'s standard '
        'is verifiability: a rating someone else could check by going there. '
        'A guess is worse than leaving it blank, because a blank is honest '
        'and a wrong rating is not.',
      ),
      const SizedBox(height: 12),
    ],
  ),
  (
    title: 'Review, then submit',
    summary: 'A comment, a checklist, and one changeset.',
    body: [
      const Row(
        children: [
          _StagedGlyph(),
          SizedBox(width: 10),
          Text('nothing staged', style: _captionStyle),
          SizedBox(width: 24),
          _StagedGlyph(count: 3),
          SizedBox(width: 10),
          Text('3 staged', style: _captionStyle),
        ],
      ),
      const SizedBox(height: 14),
      const _Para(
        'Open Staged changes, write a short comment, and submit. Steward '
        'checks for conflicts first and never overwrites silently. If '
        'someone else edited the same field, you choose which answer wins.',
      ),
      const SizedBox(height: 4),
      const _LinkButton(
        label: 'What makes a good changeset comment',
        url: _Links.goodComments,
      ),
    ],
  ),
  (
    title: 'After it goes out',
    summary: 'Live immediately, and yours to correct.',
    body: [
      const _Para(
        'The Account pane keeps the receipts: every changeset Steward has sent '
        'for you, alongside a count of what you have contributed.',
      ),
      const _Para(
        'Got one wrong? Fix it the same way you made it. Select the trail '
        'again, give the right answer, and submit. ',
      ),
    ],
  ),
];

/// One numbered step: always its title and a one-line summary, and its body
/// when it is open.
class _ExpandableStep extends StatelessWidget {
  const _ExpandableStep({
    required this.number,
    required this.title,
    required this.summary,
    required this.body,
    required this.expanded,
    required this.onToggle,
  });

  final int number;
  final String title;
  final String summary;
  final List<Widget> body;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: SlabColors.ink800,
      clipBehavior: Clip.antiAlias,
      // The border is the open/closed tell, so this is a shape rather than a
      // plain borderRadius — Material takes one or the other, never both.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SlabRadii.card),
        side: BorderSide(
          color: expanded ? SlabColors.goldSoft : SlabColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The step number, gold once you are reading it.
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: expanded ? SlabColors.gold : SlabColors.ink700,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: expanded ? SlabColors.gold : SlabColors.line,
                      ),
                    ),
                    child: Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: expanded ? SlabColors.onGold : SlabColors.sage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 3),
                        Text(summary, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 22,
                      color: SlabColors.sage,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // AnimatedSize over a conditional child rather than AnimatedCrossFade
          // with a collapsed placeholder: there is nothing to cross-fade to,
          // and the body must not be laid out at all while closed — several of
          // these are long.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    // Indented to the title, so the body reads as belonging to
                    // the step rather than to the card.
                    padding: const EdgeInsets.fromLTRB(58, 0, 22, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        // The card is as wide as the page; a paragraph must
                        // not be. Left where the heading starts rather than
                        // centred in the card, so the body reads as hanging
                        // off the step number.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 700),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: body,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A paragraph inside a step.
class _Para extends StatelessWidget {
  const _Para(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13.5,
        height: 1.7,
        color: SlabColors.sage,
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, right: 12),
          child: SizedBox(
            width: 5,
            height: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SlabColors.goldDim,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.7,
              color: SlabColors.sage,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The one thing in the instructions that is an obligation rather than a step.
/// Rust, because getting this wrong puts bad data on a public map.
class _Warn extends StatelessWidget {
  const _Warn(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SlabSurface(
    color: SlabColors.rustSoft,
    borderColor: SlabColors.rustSoft,
    padding: const EdgeInsets.all(14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.report_outlined, size: 16, color: SlabColors.rust),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.65,
              color: SlabColors.cream,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A link out of the app, as a button. Always says where it goes.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.url,
    this.primary = false,
  });

  final String label;
  final String url;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.open_in_new, size: 15);
    final text = Text(label);
    return primary
        ? FilledButton.icon(
            onPressed: () => _open(url),
            icon: icon,
            label: text,
          )
        : OutlinedButton.icon(
            onPressed: () => _open(url),
            icon: icon,
            label: text,
          );
  }
}

// ---------------------------------------------------------------------------
// Closing call to action, and the footer
// ---------------------------------------------------------------------------

/// The last thing before the footer: the same invitation as the hero, for
/// someone who has read all the way down and is now nowhere near the top.
class _ClosingCta extends StatelessWidget {
  const _ClosingCta({required this.onOpenMap});

  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideAbove;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SlabColors.line)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: wide ? 84 : 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              Text(
                'Pick one trail you know cold.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: wide ? 36 : 27,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                  color: SlabColors.cream,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Take Steward for a spin, complete the trail.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.6,
                  color: SlabColors.sage,
                ),
              ),
              const SizedBox(height: 30),
              FilledButton.icon(
                onPressed: onOpenMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open the map'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything a page is obliged to carry: who made this, what it is licensed
/// under, whose data is on the map, and where the privacy statement is.
///
/// The attribution line is not decoration. OpenStreetMap's licence requires
/// visible credit wherever its data is shown, and this page is part of the
/// thing showing it — the map screen carries its own copy in the MapLibre
/// attribution control, and this is the landing page's.
class _Footer extends StatelessWidget {
  const _Footer({required this.onOpenMap, required this.onGettingStarted});

  final VoidCallback onOpenMap;
  final VoidCallback onGettingStarted;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideAbove;

    final brand = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Wordmark(markSize: 30),
          const SizedBox(height: 16),
          const Text(
            'An OpenStreetMap metadata editor for the people who ride the '
            'trails. Made by SLAB.',
            style: TextStyle(
              fontSize: 13,
              height: 1.65,
              color: SlabColors.sage,
            ),
          ),
        ],
      ),
    );

    final columns = [
      _FooterColumn(
        heading: 'STEWARD',
        links: [
          (label: 'Open the map', onTap: onOpenMap),
          (label: 'Getting started', onTap: onGettingStarted),
          (label: 'Privacy', onTap: () => _showPrivacy(context)),
          (label: 'Source on GitHub', onTap: () => _open(_Links.source)),
        ],
      ),
      _FooterColumn(
        heading: 'OPENSTREETMAP',
        links: [
          (label: 'Create an account', onTap: () => _open(_Links.newAccount)),
          (label: osmShortLabel, onTap: () => _open(_Links.osm)),
          (label: 'Steward on the OSM wiki', onTap: () => _open(_Links.wiki)),
          (
            label: 'Organised Editing Guidelines',
            onTap: () => _open(_Links.organisedEditing),
          ),
        ],
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: SlabColors.ink900,
        border: Border(top: BorderSide(color: SlabColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: brand),
                    for (final column in columns) ...[
                      const SizedBox(width: 48),
                      SizedBox(width: 220, child: column),
                    ],
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    brand,
                    const SizedBox(height: 36),
                    Wrap(spacing: 48, runSpacing: 32, children: columns),
                  ],
                ),
              const SizedBox(height: 44),
              const Divider(height: 1),
              const SizedBox(height: 20),
              // The legal foot. A Wrap so the three notices sit on one line on
              // a desktop and stack on a phone, rather than being ellipsised
              // — none of them is optional enough to truncate.
              Wrap(
                spacing: 26,
                runSpacing: 10,
                children: [
                  const _FinePrint('© 2026 SLAB Steward · MIT licensed'),
                  // Links to the licence it is citing, which is what
                  // OpenStreetMap's own attribution guidance asks for.
                  _FinePrint(
                    'Trail data © OpenStreetMap contributors, ODbL · '
                    'tiles by OpenStreetMap US',
                    onTap: () => _open(_Links.copyright),
                  ),
                ],
              ),
              // Only on a build that cannot actually write. Nothing else on
              // this page would tell a rider that their submission is going to
              // stop one call short of OpenStreetMap, and finding that out
              // after doing the work is the wrong order.
              if (!osmEnvironment.writesToOsm) ...[
                const SizedBox(height: 14),
                const _FinePrint(
                  'This build is in dry-run: submissions run the whole gate '
                  'and then stop without writing to OpenStreetMap.',
                  color: SlabColors.gold,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The privacy statement, shown as a dialog over the page.
///
/// The same widget the Account pane ends with, rather than a second copy of
/// the words. A privacy statement that exists twice is a privacy statement
/// that will eventually say two different things.
void _showPrivacy(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Privacy'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: const SingleChildScrollView(
        child: PrivacyNote(showHeading: false),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);

typedef _FooterLink = ({String label, VoidCallback onTap});

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.heading, required this.links});

  final String heading;
  final List<_FooterLink> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(heading, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 14),
        for (final link in links)
          InkWell(
            onTap: link.onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                link.label,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: SlabColors.cream,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FinePrint extends StatelessWidget {
  const _FinePrint(this.text, {this.color = SlabColors.sageDim, this.onTap});

  final String text;
  final Color color;

  /// Where this line goes, for the ones that cite something.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(fontSize: 11.5, height: 1.5, color: color),
    );
    if (onTap == null) return label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: label,
    );
  }
}
