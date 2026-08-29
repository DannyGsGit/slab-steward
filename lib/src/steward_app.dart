import 'package:flutter/material.dart';

import 'map/steward_map_view.dart';
import 'state/steward_state.dart';
import 'ui/account_button.dart';
import 'ui/legend.dart';
import 'ui/map_controls.dart';
import 'ui/selection_panel.dart';
import 'ui/slab_chrome.dart';
import 'ui/slab_theme.dart';
import 'ui/staged_changes.dart';
import 'ui/trail_list_panel.dart';
import 'ui/trail_panel.dart';

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
      // docs/SLAB Design System - Mockups v2.html. The chrome is dark on
      // purpose: the map is the bright thing on screen and the panels are
      // what surrounds it, exactly as the sister app treats its own map
      // screen.
      theme: slabTheme(),
      home: _HomePage(state: _state),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: StewardMapView(state: state)),
          // Everything above the map reacts to the same state object.
          Positioned.fill(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => _MapOverlays(state: state),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapOverlays extends StatelessWidget {
  const _MapOverlays({required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // The map underneath still needs to receive pans and clicks.
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            bottom: 16,
            // The staged-changes indicator and the trail list live under the
            // controls rather than opposite them: the right edge belongs to
            // the editor, and both of these have to stay visible while a trail
            // is selected.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SlabBrand(),
                const SizedBox(height: 12),
                MapControls(state: state),
                const SizedBox(height: 12),
                TrailListButton(state: state),
                if (state.hasStagedEdits) ...[
                  const SizedBox(height: 12),
                  StagedChangesButton(state: state),
                ],
                if (state.isTrailListOpen) ...[
                  const SizedBox(height: 12),
                  Flexible(child: TrailListPanel(state: state)),
                ],
              ],
            ),
          ),
          // The legend and the list both want the bottom-left corner, and the
          // list is the one someone is actively reading.
          if (!state.isTrailListOpen)
            Positioned(bottom: 16, left: 16, child: Legend(state: state)),
          Positioned(
            top: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Above the editor, and present whether or not anything is
                // selected: who you're about to write as is not a detail of
                // the current selection.
                AccountButton(state: state),
                if (state.hasSelection) ...[
                  const SizedBox(height: 12),
                  // One trail gets the detail view; several get the bulk
                  // editor, which applies one value across all of them.
                  Flexible(
                    child: state.hasMultiSelection
                        ? SelectionPanel(state: state)
                        : TrailPanel(state: state),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
