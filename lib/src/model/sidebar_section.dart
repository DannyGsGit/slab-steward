import 'package:flutter/material.dart';

/// The panes the sidebar can be showing, one at a time.
///
/// The rail — or, on a phone, the bottom bar — is the app's whole navigation:
/// every panel that used to float over the map (the controls, the in-view
/// list, the editor, the staging area, the account) is one of these, and at
/// most one is open. That is what keeps the map clean, and it is how the
/// sister app's web layout works. See
/// `docs/requirements/SLAB Design System - Mockups v2.html`, "Web — same six contexts".
enum SidebarSection {
  /// What the map draws and what the colours mean, plus the legend that
  /// explains the answer.
  map('Map', 'Trail display and highlighting'),

  /// Every trail in the viewport, as a working list.
  trails('Trails in view', 'List the trails on screen'),

  /// The guided editor for whatever is selected — one trail, or a batch.
  selection('Selection', 'Edit the selected trails'),

  /// Edits waiting to go out as one changeset.
  staged('Staged changes', 'Review and submit your changes'),

  /// Who you are about to write to OpenStreetMap as, what you have done
  /// through Steward, and the changesets it went out in.
  account('Account', 'Your account, stats and submitted changes');

  const SidebarSection(this.label, this.tooltip);

  /// The pane's heading, and the rail button's name.
  final String label;

  /// What the rail button says on hover.
  final String tooltip;

  /// What the mobile bottom bar writes under the glyph: a thumb-wide slot has
  /// room for a word, not for the phrase a pane heading can afford.
  String get shortLabel => switch (this) {
    SidebarSection.trails => 'Trails',
    SidebarSection.staged => 'Staged',
    _ => label,
  };

  /// The glyph both layouts wear for this section.
  ///
  /// On the enum rather than at each button so the rail and the bottom bar
  /// cannot drift into naming the same pane two different things. The account
  /// is the exception both layouts make: its button wears the rider's initials
  /// instead — see `AccountAvatar`.
  IconData get icon => switch (this) {
    SidebarSection.map => Icons.layers_outlined,
    SidebarSection.trails => Icons.format_list_bulleted,
    SidebarSection.selection => Icons.edit_location_alt_outlined,
    // A checkmark: what waits behind this button is work to approve and send,
    // not more editing.
    SidebarSection.staged => Icons.check_circle_outline,
    SidebarSection.account => Icons.person_outline,
  };

  /// How wide the pane is when this section is open.
  ///
  /// Per-section rather than one width for all: the in-view list carries a
  /// name, its rating and a live picker on one line, and squeezing the other
  /// panes to match would waste a third of the window on the panes that don't.
  double get paneWidth => switch (this) {
    SidebarSection.trails => 430,
    _ => 360,
  };

  /// The sections the mobile bottom bar carries, in order.
  ///
  /// [map] is missing on purpose: a phone has four or five thumb-width slots
  /// across the bottom, and the one section that is about the map itself is
  /// better reached from the map — see the settings button in the map's
  /// top-right corner. The other four are the work.
  static const bottomBar = [trails, selection, staged, account];
}
