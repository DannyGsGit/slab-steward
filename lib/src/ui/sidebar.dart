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
///
/// This is the wide-window layout. A phone-shaped window gets the same panes
/// under a bottom bar instead — see [StewardBottomBar] — and both draw the
/// open pane with the shared [SectionPane].
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
            _RailButton(state: state, section: SidebarSection.map),
            _RailButton(state: state, section: SidebarSection.trails),
            _RailButton(
              state: state,
              section: SidebarSection.selection,
              // Nothing to edit is not a pane worth opening, and a button
              // that opens an empty panel teaches nothing.
              enabled: state.hasSelection,
              badgeCount: state.selectionCount > 1 ? state.selectionCount : 0,
            ),
            _RailButton(
              state: state,
              section: SidebarSection.staged,
              badgeCount: state.stagedEditCount,
            ),
            const Spacer(),
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
    this.child,
    this.enabled = true,
    this.badgeCount = 0,
  });

  final StewardState state;
  final SidebarSection section;

  /// Drawn instead of the section's own glyph — the account button wears an
  /// avatar.
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
          section.icon,
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

/// The open pane, beside the rail: framed to its section's width.
class _Pane extends StatelessWidget {
  const _Pane({
    required this.state,
    required this.section,
    required this.maxWidth,
  });

  final StewardState state;
  final SidebarSection section;
  final double maxWidth;

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
        child: SectionPane(
          state: state,
          section: section,
          closeTooltip: 'Collapse the sidebar',
        ),
      ),
    );
  }
}

/// What an open pane holds: a heading, a close control, and the section's own
/// panel underneath.
///
/// Shared by both layouts. The rail frames it as a column beside the map and
/// the bottom bar frames it as a band above one, but a pane is the same pane
/// either way — anything that differed between them would be two products.
class SectionPane extends StatelessWidget {
  const SectionPane({
    super.key,
    required this.state,
    required this.section,
    required this.closeTooltip,
    this.compact = false,
  });

  final StewardState state;
  final SidebarSection section;

  /// What the close control says on hover — the two layouts collapse to
  /// different shapes, so they describe it differently.
  final String closeTooltip;

  /// Whether this is the phone layout's band rather than the rail's column.
  /// The panes are the same either way; the few lines of copy that describe
  /// how to work the map are not, because one of those windows is being
  /// pointed at and the other is being touched.
  final bool compact;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: _title,
          large: true,
          closeTooltip: closeTooltip,
          onClose: state.closeSection,
          trailing: section == SidebarSection.selection && state.hasSelection
              ? IconAction(
                  icon: Icons.deselect,
                  tooltip: 'Clear selection',
                  onPressed: state.clearSelection,
                )
              : null,
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() => switch (section) {
    SidebarSection.map => MapControlsPanel(state: state),
    SidebarSection.trails => TrailListPanel(state: state),
    SidebarSection.selection => switch (state.selectionCount) {
      0 => NothingSelectedNotice(compact: compact),
      // One trail gets the detail view; several get the bulk editor, which
      // applies one value across all of them.
      1 => TrailPanel(state: state),
      _ => SelectionPanel(state: state),
    },
    SidebarSection.staged => StagedChangesPanel(state: state),
    SidebarSection.account => AccountPanel(state: state),
  };
}

/// What the selection pane says before anything is picked.
class NothingSelectedNotice extends StatelessWidget {
  const NothingSelectedNotice({super.key, this.compact = false});

  /// On a touch-shaped window the second line goes: box-select is a modified
  /// drag, and there is no modifier key to hold. Telling a rider on a phone to
  /// ctrl-drag a box teaches them only that the app was not built for them.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            compact
                ? 'Tap a trail on the map to rate it.'
                : 'Click a trail on the map to rate it.',
            style: theme.textTheme.bodyMedium,
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              '$multiSelectModifier-click a second trail — or '
              '$multiSelectModifier-drag a box across several — to edit them '
              'together.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
