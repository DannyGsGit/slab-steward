import 'package:flutter/material.dart';

import 'map/steward_map_view.dart';
import 'state/steward_state.dart';
import 'ui/sidebar.dart';
import 'ui/slab_theme.dart';

class StewardApp extends StatefulWidget {
  const StewardApp({super.key});

  @override
  State<StewardApp> createState() => _StewardAppState();
}

class _StewardAppState extends State<StewardApp> {
  final _state = StewardState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLAB Steward',
      debugShowCheckedModeBanner: false,
      // SLAB's design system — dark forest and gold, from
      // docs/requirements/SLAB Design System - Mockups v2.html. The chrome is
      // dark on purpose: the map is the bright thing on screen and the rail
      // and pane are what surrounds it, exactly as the sister app treats its
      // own map screen.
      theme: slabTheme(),
      home: _HomePage(state: _state),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.state});

  final StewardState state;

  /// How much of a narrow window the pane may claim before it starts eating
  /// the map. Half: below that the map stops being a map.
  static const _maxPaneFraction = 0.5;

  @override
  Widget build(BuildContext context) {
    // A row, not a stack. Every panel Steward has used to float over the map,
    // which meant the map was always partly hidden and — on web, where the
    // map is a platform view the browser feeds directly — every click and
    // scroll over a panel had to be fended off before it reached the map.
    // Beside it, neither problem exists. See [StewardSidebar].
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            ListenableBuilder(
              listenable: state,
              builder: (context, _) => StewardSidebar(
                state: state,
                maxPaneWidth: constraints.maxWidth * _maxPaneFraction,
              ),
            ),
            // The map keeps whatever is left, and resizes as the pane opens
            // and closes rather than being covered by it.
            Expanded(child: StewardMapView(state: state)),
          ],
        ),
      ),
    );
  }
}
