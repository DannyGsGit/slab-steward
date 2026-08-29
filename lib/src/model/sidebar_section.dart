/// The panes the sidebar can be showing, one at a time.
///
/// The rail is the app's whole navigation: every panel that used to float over
/// the map — the controls, the in-view list, the editor, the staging area, the
/// account — is one of these, and at most one is open. That is what keeps the
/// map clean, and it is how the sister app's web layout works. See
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

  /// Who you are about to write to OpenStreetMap as.
  account('Account', 'Your OpenStreetMap account');

  const SidebarSection(this.label, this.tooltip);

  /// The pane's heading, and the rail button's name.
  final String label;

  /// What the rail button says on hover.
  final String tooltip;

  /// How wide the pane is when this section is open.
  ///
  /// Per-section rather than one width for all: the in-view list carries a
  /// name, its rating and a live picker on one line, and squeezing the other
  /// panes to match would waste a third of the window on the panes that don't.
  double get paneWidth => switch (this) {
    SidebarSection.trails => 430,
    _ => 360,
  };
}
