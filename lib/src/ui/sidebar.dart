import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../model/sidebar_section.dart';
import '../state/steward_state.dart';
import 'account_panel.dart';
import 'fields.dart';
import 'map_controls.dart';
import 'selection_panel.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';
import 'staged_changes.dart';
import 'stats_panel.dart';
import 'trail_list_panel.dart';
import 'trail_panel.dart';

/// The rail and the pane beside it — everything in Steward that isn't the map.
///
/// This replaces four panels that used to float in the map's corners. They
/// worked, and they cost the map its two most useful corners even when nobody
/// was reading them; open two at once and there was more chrome than map. The
/// sister app's web layout answers this with a rail and a single pane — see
/// `docs/requirements/SLAB Design System - Mockups v2.html`, "Web — same six contexts" —
/// and one pane at a time is also the honest description of the work: you are
/// choosing what the map shows, or working a list, or editing what you picked,
/// or submitting. Not several of those at once.
///
/// The sidebar sits *beside* the map rather than over it, so a click in the
/// pane is not also a click on the map. See [PointerInterceptor] below for why
/// that alone isn't enough on the web.
class StewardSidebar extends StatelessWidget {
  const StewardSidebar({
    super.key,
    required this.state,
    required this.maxPaneWidth,
  });

  final StewardState state;

  /// How much of the window the pane may take. The map is the point of the
  /// app; on a narrow window the pane gives way rather than squeezing it to a
  /// strip.
  final double maxPaneWidth;

  @override
  Widget build(BuildContext context) {
    final active = state.activeSection;
    // On web the map is a platform view: an HTML element MapLibre GL JS
    // listens on directly. The browser hands that element every click, scroll
    // and drag that lands inside its box, whatever Flutter has painted on top
    // — so a wheel over the pane would zoom the map underneath, and a drag
    // would pan it. PointerInterceptor puts a real DOM element in front of
    // the map for the sidebar's whole footprint, which is what actually stops
    // them. It wraps the rail as well as the pane: the rail is narrow, but a
    // scroll that starts on it is no more meant for the map than one that
    // starts an inch to the right.
    return PointerInterceptor(
      child: Row(
        children: [
          _Rail(state: state),
          if (active != null)
            _Pane(state: state, section: active, maxWidth: maxPaneWidth),
        ],
      ),
    );
  }
}

/// The icon rail: the brand, one button per pane, and the account at the foot.
class _Rail extends StatelessWidget {
  const _Rail({required this.state});

  final StewardState state;

  /// The design doc's `.rail`.
  static const width = 64.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: SlabColors.ink900,
        border: Border(right: BorderSide(color: SlabColors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            Tooltip(
              message: 'SLAB Steward',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/slab/logo.png',
                  width: 34,
                  height: 34,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _RailButton(
              state: state,
              section: SidebarSection.map,
              icon: Icons.layers_outlined,
            ),
            _RailButton(
              state: state,
              section: SidebarSection.trails,
              icon: Icons.format_list_bulleted,
            ),
            _RailButton(
              state: state,
              section: SidebarSection.selection,
              icon: Icons.edit_location_alt_outlined,
              // Nothing to edit is not a pane worth opening, and a button
              // that opens an empty panel teaches nothing.
              enabled: state.hasSelection,
              badgeCount: state.selectionCount > 1 ? state.selectionCount : 0,
            ),
            _RailButton(
              state: state,
              section: SidebarSection.staged,
              // A checkmark: what waits behind this button is work to approve
              // and send, not more editing.
              icon: Icons.check_circle_outline,
              badgeCount: state.stagedEditCount,
            ),
            const Spacer(),
            _RailButton(
              state: state,
              section: SidebarSection.stats,
              icon: Icons.emoji_events_outlined,
            ),
            _RailButton(
              state: state,
              section: SidebarSection.account,
              // The account button wears the account: initials once there is
              // a name to take them from, which is the fastest way to answer
              // "whose account am I about to write under".
              child: ListenableBuilder(
                listenable: state.auth,
                builder: (context, _) => AccountAvatar(
                  isSignedIn: state.auth.isSignedIn,
                  isSigningIn: state.auth.isSigningIn,
                  displayName: state.auth.identity?.displayName,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// One rail button: 40 square, gold-washed while its pane is the one open.
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.state,
    required this.section,
    this.icon,
    this.child,
    this.enabled = true,
    this.badgeCount = 0,
  });

  final StewardState state;
  final SidebarSection section;

  /// Either an [icon] or a [child] — the account button draws an avatar.
  final IconData? icon;
  final Widget? child;

  final bool enabled;

  /// Zero draws no badge.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final isActive = state.activeSection == section;
    final content =
        child ??
        Icon(
          icon,
          size: 19,
          color: !enabled
              ? SlabColors.sageDim.withValues(alpha: 0.4)
              : isActive
              ? SlabColors.gold
              : SlabColors.sageDim,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: section.tooltip,
        child: Material(
          color: isActive ? SlabColors.goldSoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isActive ? SlabColors.gold : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => state.toggleSection(section) : null,
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: badgeCount > 0
                    ? Badge.count(count: badgeCount, child: content)
                    : content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The open pane: a heading, a close control, and whatever the section is for.
class _Pane extends StatelessWidget {
  const _Pane({
    required this.state,
    required this.section,
    required this.maxWidth,
  });

  final StewardState state;
  final SidebarSection section;
  final double maxWidth;

  /// What the heading says. Only the selection pane's title changes with the
  /// app's state — it names what is being edited, the way the floating panel
  /// it replaces did.
  String get _title => switch (section) {
    SidebarSection.selection when state.hasMultiSelection =>
      '${state.selectionCount} trails selected',
    SidebarSection.selection => state.selected?.name ?? 'Unnamed trail',
    _ => section.label,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: section.paneWidth.clamp(0.0, maxWidth),
      decoration: const BoxDecoration(
        color: SlabColors.ink800,
        border: Border(right: BorderSide(color: SlabColors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelHeader(
              title: _title,
              large: true,
              closeTooltip: 'Collapse the sidebar',
              onClose: state.closeSection,
              trailing:
                  section == SidebarSection.selection && state.hasSelection
                  ? IconAction(
                      icon: Icons.deselect,
                      tooltip: 'Clear selection',
                      onPressed: state.clearSelection,
                    )
                  : null,
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() => switch (section) {
    SidebarSection.map => MapControlsPanel(state: state),
    SidebarSection.trails => TrailListPanel(state: state),
    SidebarSection.selection => switch (state.selectionCount) {
      0 => const _NothingSelected(),
      // One trail gets the detail view; several get the bulk editor, which
      // applies one value across all of them.
      1 => TrailPanel(state: state),
      _ => SelectionPanel(state: state),
    },
    SidebarSection.staged => StagedChangesPanel(state: state),
    SidebarSection.stats => StatsPanel(state: state),
    SidebarSection.account => AccountPanel(state: state),
  };
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Click a trail on the map to rate it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '$multiSelectModifier-click a second trail — or '
            '$multiSelectModifier-drag a box across several — to edit them '
            'together.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
