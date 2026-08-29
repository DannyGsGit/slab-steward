import 'package:flutter/material.dart';

import '../model/lens.dart';
import '../state/steward_state.dart';

/// Travel mode and lens pickers — what's drawn, and what questions the colours
/// are answering. Both concepts are OpenTrailMap's.
///
/// Collapsible: the pickers are only useful while being adjusted, so they
/// give up screen real estate to the map the rest of the time.
class MapControls extends StatefulWidget {
  const MapControls({super.key, required this.state});

  final StewardState state;

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // "Unknown access" is meaningless without a travel mode to ask about.
    final lenses = Lens.values
        .where((l) => l != Lens.access || state.mode != TravelMode.all)
        .toList();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          16,
          10,
          8,
          0,
        ).add(EdgeInsets.only(bottom: _expanded ? 0 : 10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Label('Map controls'),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              const _Label('Show'),
              const SizedBox(height: 6),
              SegmentedButton<TravelMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final mode in TravelMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {state.mode},
                onSelectionChanged: (s) => state.setMode(s.first),
              ),
              const SizedBox(height: 16),
              const _Label('Highlight'),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, right: 8),
                child: _LensMenu(state: state, lenses: lenses),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The highlight rules, as a multi-select drop-down.
///
/// A menu rather than a row of chips because the rules stack: any combination
/// is legal, and a trail has to answer all of the ticked ones to count as
/// done. Ticking none of them is the plain OpenTrailMap map.
class _LensMenu extends StatelessWidget {
  const _LensMenu({required this.state, required this.lenses});

  final StewardState state;

  /// The rules on offer, already filtered to the ones the current travel mode
  /// can meaningfully ask.
  final List<Lens> lenses;

  @override
  Widget build(BuildContext context) {
    final selected = state.lenses.inOrder;

    return MenuAnchor(
      // Ticking a box has to leave the menu open, or picking two rules would
      // mean opening it twice.
      menuChildren: [
        for (final lens in lenses)
          CheckboxMenuButton(
            value: state.lenses.contains(lens),
            closeOnActivate: false,
            onChanged: (on) => state.setLensEnabled(lens, on ?? false),
            child: Text(lens.label),
          ),
        const Divider(height: 1),
        MenuItemButton(
          closeOnActivate: false,
          onPressed: selected.isEmpty ? null : () => state.setLenses(const {}),
          child: const Text('Clear all'),
        ),
      ],
      builder: (context, controller, _) => OutlinedButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: Theme.of(context).textTheme.bodyMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(_summary(selected), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Icon(
              controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// What the closed button says. One rule names itself; several would not fit
  /// on the button, and the legend below spells the combination out anyway.
  static String _summary(List<Lens> selected) => switch (selected.length) {
    0 => 'Nothing highlighted',
    1 => selected.single.label,
    final n => '$n rules',
  };
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8),
  );
}
