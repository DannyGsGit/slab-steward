import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../model/sidebar_section.dart';
import '../state/steward_state.dart';
import 'account_panel.dart';
import 'sidebar.dart';
import 'slab_theme.dart';

/// The phone-shaped window's navigation: the same panes as the rail's, under a
/// bar across the bottom instead of a column down the side.
///
/// A rail plus a pane is two vertical bands, and on a phone that leaves the
/// pane a strip too narrow to read a trail name in — the rail alone is a fifth
/// of the window. Laid out this way the pane gets the full width and the map
/// keeps a square of its own above it, which is the same trade the wide layout
/// makes, turned ninety degrees.
///
/// Three things move for this layout, and all three are about width:
///
///  * The brand mark goes. It is the one thing on the rail that isn't a
///    control, and a bar has no room for something that doesn't do anything.
///  * The Map pane leaves the bar for a button in the map's own top-right
///    corner — see [MapSettingsButton]. It is the one section that acts on the
///    map rather than on the rider's work, and that puts it a thumb away from
///    what it changes.
///  * Labels shorten to [SidebarSection.shortLabel].
///
/// The panes themselves are the wide layout's, unchanged: see [SectionPane].
class StewardBottomBar extends StatelessWidget {
  const StewardBottomBar({super.key, required this.state});

  final StewardState state;

  /// The bar's own height, before the phone's home indicator is added under
  /// it. Comfortably over the 48 a thumb needs, with room for a word.
  static const height = 58.0;

  @override
  Widget build(BuildContext context) {
    // The map is a platform view the browser feeds directly on web, so a tap
    // that lands on the bar would otherwise also reach the map underneath.
    // See [StewardSidebar].
    return PointerInterceptor(
      child: Container(
        decoration: const BoxDecoration(
          color: SlabColors.ink900,
          border: Border(top: BorderSide(color: SlabColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (final section in SidebarSection.bottomBar)
                  Expanded(
                    child: _BarButton(
                      state: state,
                      section: section,
                      // Nothing to edit is not a pane worth opening, and a
                      // button that opens an empty panel teaches nothing.
                      enabled:
                          section != SidebarSection.selection ||
                          state.hasSelection,
                      badgeCount: switch (section) {
                        SidebarSection.staged => state.stagedEditCount,
                        SidebarSection.selection =>
                          state.selectionCount > 1 ? state.selectionCount : 0,
                        _ => 0,
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One slot in the bar: the section's glyph over its short name, gold while
/// its pane is the one open.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.state,
    required this.section,
    this.enabled = true,
    this.badgeCount = 0,
  });

  final StewardState state;
  final SidebarSection section;
  final bool enabled;

  /// Zero draws no badge.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final isActive = state.activeSection == section;
    final color = !enabled
        ? SlabColors.sageDim.withValues(alpha: 0.4)
        : isActive
        ? SlabColors.gold
        : SlabColors.sageDim;

    // The account slot wears the rider's initials here exactly as it does on
    // the rail: "whose account am I about to write under" is the question a
    // person-shaped glyph answers with "somebody's".
    final Widget glyph = section == SidebarSection.account
        ? ListenableBuilder(
            listenable: state.auth,
            builder: (context, _) => AccountAvatar(
              isSignedIn: state.auth.isSignedIn,
              isSigningIn: state.auth.isSigningIn,
              displayName: state.auth.identity?.displayName,
              size: 22,
            ),
          )
        : Icon(section.icon, size: 20, color: color);

    return Tooltip(
      message: section.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => state.toggleSection(section) : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The bar has no room for the rail's gold wash behind a button,
              // so the active slot is marked above it instead.
              Container(
                height: 2,
                width: 26,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isActive ? SlabColors.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              badgeCount > 0
                  ? Badge.count(count: badgeCount, child: glyph)
                  : glyph,
              const SizedBox(height: 3),
              Text(
                section.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The open pane on a phone: the full width of the window, above the bar.
class StewardMobilePane extends StatelessWidget {
  const StewardMobilePane({
    super.key,
    required this.state,
    required this.section,
    required this.height,
  });

  final StewardState state;
  final SidebarSection section;

  /// How tall the band is. Chosen by the shell from the window, because the
  /// pane's job here is the mirror of the wide layout's: take what it needs
  /// and leave the map a usable square. See [mobilePaneHeight].
  final double height;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: SlabColors.ink800,
          border: Border(top: BorderSide(color: SlabColors.line)),
        ),
        child: SectionPane(
          state: state,
          section: section,
          closeTooltip: 'Close this panel',
          compact: true,
        ),
      ),
    );
  }
}

/// How much of a phone-shaped window an open pane may take.
///
/// A little over half, which leaves the map a little under 40% once the bar
/// beneath has taken its own 58: enough to see the trail being edited and its
/// neighbours, which is all the map has to answer while a pane is open. The
/// floor keeps a pane usable on a short window held sideways, and the window
/// itself is the ceiling, so the band can never be taller than what it is
/// inside.
double mobilePaneHeight(double windowHeight) =>
    math.min(windowHeight, math.max(240, windowHeight * 0.52));

/// The Map pane's way in on a phone: a button in the map's top-right corner.
///
/// It sits on the map rather than in the bar because it is the one section
/// that changes what the map draws — access, trail kinds, the highlighting
/// lenses and the legend that reads them back. A rider ticking a lens is
/// watching the map for the answer, and the control belongs next to the thing
/// it answers about.
class MapSettingsButton extends StatelessWidget {
  const MapSettingsButton({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final isActive = state.activeSection == SidebarSection.map;
    return _MapCornerButton(
      alignment: Alignment.topRight,
      tooltip: SidebarSection.map.tooltip,
      active: isActive,
      onTap: () => state.toggleSection(SidebarSection.map),
      child: Icon(
        SidebarSection.map.icon,
        size: 19,
        color: isActive ? SlabColors.onGold : SlabColors.cream,
      ),
    );
  }
}

/// The way home on a phone: the brand mark in the map's top-left corner.
///
/// The wide layout puts this at the head of the rail; a bottom bar has no room
/// for something that isn't a pane, so it moves onto the map for the same
/// reason [MapSettingsButton] did — and to the opposite corner, so the two
/// floating controls never crowd each other.
class MapHomeButton extends StatelessWidget {
  const MapHomeButton({super.key, required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => _MapCornerButton(
    alignment: Alignment.topLeft,
    tooltip: 'SLAB Steward — back to the home page',
    onTap: onHome,
    // No padding around the mark: the artwork is a filled square with its own
    // margin, and the button clips it to the same radius the rail does.
    padding: EdgeInsets.zero,
    child: Image.asset(
      'assets/slab/logo.png',
      width: 38,
      height: 38,
      filterQuality: FilterQuality.medium,
    ),
  );
}

/// The chrome both floating map buttons wear: a 38-square, ink or gold,
/// shadowed enough to stay legible over snow, sand or a lake.
///
/// Shared so the two corners can't drift into two different buttons.
class _MapCornerButton extends StatelessWidget {
  const _MapCornerButton({
    required this.alignment,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.active = false,
    this.padding = const EdgeInsets.all(0),
  });

  final Alignment alignment;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool active;
  final EdgeInsets padding;

  static const _size = 38.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // The map underneath would otherwise swallow the tap on web.
          child: PointerInterceptor(
            child: Tooltip(
              message: tooltip,
              child: Material(
                color: active ? SlabColors.gold : SlabColors.ink900,
                borderRadius: BorderRadius.circular(SlabRadii.control),
                clipBehavior: Clip.antiAlias,
                elevation: 4,
                shadowColor: const Color(0xB3000000),
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: padding,
                    child: SizedBox.square(
                      dimension: _size,
                      child: Center(child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
