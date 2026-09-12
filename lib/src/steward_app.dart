import 'package:flutter/material.dart';

import 'analytics/steward_events.dart';
import 'state/steward_state.dart';
import 'ui/home_page.dart';
import 'ui/map_screen.dart';
import 'ui/slab_theme.dart';

/// The two screens, and the way between them.
///
/// Steward opened straight onto the map until the landing page arrived. It no
/// longer does, and the reason is not marketing: this tool writes to a public
/// database under the rider's own name, and the account requirement, the
/// verifiability standard and what a changeset actually is all have to be
/// answerable *before* the first edit. A pane inside the editor is too late to
/// ask them. See [StewardHomePage].
class StewardApp extends StatefulWidget {
  const StewardApp({super.key});

  @override
  State<StewardApp> createState() => _StewardAppState();
}

/// The two named routes.
///
/// Named rather than a flag in this widget's state so the browser's own
/// history works: Flutter web's default hash strategy puts the map at
/// `#/map`, and Back goes home. A rider who lands on the map and presses Back
/// expecting the home page is right, and a flag would have taken them out of
/// the app instead.
///
/// This does not disturb OAuth. The redirect URI is always `Uri.base.origin`
/// with no path (see `osm_auth.dart`), and the callback is detected from the
/// query string rather than the fragment (see `oauth_callback_web.dart`), so
/// neither one can see a route.
abstract final class StewardRoutes {
  static const home = '/';
  static const map = '/map';
}

class _StewardAppState extends State<StewardApp> {
  /// Owned here rather than by either screen, which is what makes the brand
  /// mark safe to press: staged edits, the selection and the OSM sign-in all
  /// outlive a trip to the landing page and back.
  final _state = StewardState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  /// Back to the landing page.
  ///
  /// A pop where there is something to pop, so the history stays one entry
  /// deep however many times the rider goes back and forth. The replacement is
  /// for the case the pop can't cover: someone who opened `#/map` directly, or
  /// arrived on a link, has no home page underneath to return to.
  void _goHome(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(StewardRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLAB Steward',
      debugShowCheckedModeBanner: false,
      // SLAB's design system — deep navy and gold, from
      // docs/requirements/SLAB Design System - Mockups v2.html. The chrome is
      // dark on purpose: the map is the bright thing on screen and the rail
      // and pane are what surrounds it, exactly as the sister app treats its
      // own map screen. The landing page is the same palette at page scale.
      theme: slabTheme(),
      initialRoute: StewardRoutes.home,
      routes: {
        StewardRoutes.home: (context) => StewardHomePage(
          state: _state,
          onOpenMap: () => Navigator.of(context).pushNamed(StewardRoutes.map),
        ),
        StewardRoutes.map: (context) =>
            _MapRoute(state: _state, onHome: () => _goHome(context)),
      },
    );
  }
}

/// [StewardMapScreen] plus the one event that has to fire when it opens.
///
/// A wrapper rather than a call inside the route builder: a `WidgetBuilder`
/// may be invoked more than once for a single route, and `map_opened` counted
/// twice would quietly overstate the step the whole landing page exists to
/// move. `initState` runs once per route, which is exactly the question the
/// event is asking.
class _MapRoute extends StatefulWidget {
  const _MapRoute({required this.state, required this.onHome});

  final StewardState state;
  final VoidCallback onHome;

  @override
  State<_MapRoute> createState() => _MapRouteState();
}

class _MapRouteState extends State<_MapRoute> {
  @override
  void initState() {
    super.initState();
    trackMapOpened();
  }

  @override
  Widget build(BuildContext context) =>
      StewardMapScreen(state: widget.state, onHome: widget.onHome);
}
