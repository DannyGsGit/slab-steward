import 'package:flutter/material.dart';

/// The SLAB design system, as Steward wears it.
///
/// Source: `docs/SLAB Design System - Mockups v2.html` — the sister app's
/// handoff doc. Its palette is the moody dark-forest / gold identity, and its
/// rule for a map screen is the one Steward needs: **the map is fixed, the
/// chrome around it is ours**. Basemap, trail line colours and the
/// OpenTrailMap vocabulary in `otm_conventions.dart` are untouched by
/// everything here; panels, cards, buttons, pickers and badges are not.
///
/// Tokens are plain constants rather than a [ThemeExtension] so a widget can
/// reach for one without a [BuildContext] — the map badges are built inside
/// marker callbacks, and the glyphs are painted from asset SVGs that carry
/// their own colours.

/// The palette, straight off the design doc's `:root` block.
abstract final class SlabColors {
  /// Page ground — behind everything, including the map while it loads.
  static const ink950 = Color(0xFF0B1512);

  /// Rail, tab bar, search chrome. In Steward: the recessed rows inside a
  /// panel, and the chips on the map.
  static const ink900 = Color(0xFF12211C);

  /// Panel surface — every floating card over the map.
  static const ink800 = Color(0xFF1B2C25);

  /// Cards, rows, inputs sitting *on* a panel.
  static const ink700 = Color(0xFF24382F);

  /// One step lighter again, for a hovered or pressed row.
  static const ink600 = Color(0xFF32493D);

  /// The hairline that separates anything from anything —
  /// `rgba(243,239,230,0.08)`.
  static const line = Color(0x14F3EFE6);

  /// Logo, CTA, active state, stars, favourites. In Steward it also carries
  /// "this is pending" — see [StatusBadge].
  static const gold = Color(0xFFC9A227);

  /// `rgba(201,162,39,0.16)` — the wash behind an active control.
  static const goldSoft = Color(0x29C9A227);

  /// Section labels and other text that is gold by role but must not shout.
  static const goldDim = Color(0xFF8C7220);

  /// Text and icons on top of [gold].
  static const onGold = Color(0xFF17251E);

  /// Primary text on dark.
  static const cream = Color(0xFFF3EFE6);

  /// Secondary text — echoes the map's hillshade.
  static const sage = Color(0xFF93A69A);

  /// Tertiary text: units, timestamps, the quiet half of a row.
  static const sageDim = Color(0xFF5C6E62);

  /// The one "live / destructive" accent. SLAB spends it on recording;
  /// Steward spends it on errors and on discarding work.
  static const rust = Color(0xFFB5453A);

  /// `rgba(181,69,58,0.18)`.
  static const rustSoft = Color(0x2EB5453A);

  /// A panel floating directly on the map, where the basemap has to stay
  /// faintly readable through it — `rgba(18,33,28,0.92)`.
  static const overlay = Color(0xEB12211C);

  /// The design doc's difficulty badge colours. Steward draws difficulty as
  /// the signage glyph (see `Difficulty.assetPath`), so these are only for
  /// text and tints that have to agree with the sister app's badges.
  static const diffEasy = Color(0xFF5E9C5B);
  static const diffIntermediate = Color(0xFF4C86AE);
  static const diffAdvanced = Color(0xFF7C8478);
  static const diffExpert = Color(0xFF8E3B34);
}

/// Corner radii, in the design doc's steps.
abstract final class SlabRadii {
  /// Cards and rows inside a panel.
  static const card = 14.0;

  /// A floating panel over the map.
  static const panel = 16.0;

  /// Inputs, chips on the map, the small square buttons.
  static const control = 10.0;

  /// Chips, tags, badges — anything that reads as a pill.
  static const pill = 999.0;
}

/// The app-wide theme. Every Material widget Steward uses is dressed here, so
/// panels don't each carry their own colours.
ThemeData slabTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: SlabColors.gold,
    onPrimary: SlabColors.onGold,
    primaryContainer: SlabColors.goldSoft,
    onPrimaryContainer: SlabColors.gold,
    secondary: SlabColors.sage,
    onSecondary: SlabColors.ink950,
    secondaryContainer: SlabColors.ink700,
    onSecondaryContainer: SlabColors.cream,
    tertiary: SlabColors.sage,
    onTertiary: SlabColors.ink950,
    error: SlabColors.rust,
    onError: SlabColors.cream,
    errorContainer: SlabColors.rustSoft,
    onErrorContainer: SlabColors.rust,
    surface: SlabColors.ink800,
    onSurface: SlabColors.cream,
    surfaceContainerLowest: SlabColors.ink950,
    surfaceContainerLow: SlabColors.ink900,
    surfaceContainer: SlabColors.ink800,
    surfaceContainerHigh: SlabColors.ink700,
    surfaceContainerHighest: SlabColors.ink600,
    onSurfaceVariant: SlabColors.sage,
    outline: SlabColors.sageDim,
    outlineVariant: SlabColors.line,
    shadow: Color(0xFF000000),
    inverseSurface: SlabColors.cream,
    onInverseSurface: SlabColors.ink900,
  );

  const textTheme = TextTheme(
    // The pane heading — "Staged changes", "Trails in view".
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      color: SlabColors.cream,
      letterSpacing: -0.2,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: SlabColors.cream,
      letterSpacing: -0.1,
    ),
    titleSmall: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: SlabColors.cream,
    ),
    bodyLarge: TextStyle(fontSize: 14, color: SlabColors.cream),
    bodyMedium: TextStyle(fontSize: 13.5, color: SlabColors.cream),
    // Every explanatory line in the app. Sage, not dimmed cream: the doc
    // treats secondary text as its own colour rather than as faded primary.
    bodySmall: TextStyle(fontSize: 11.5, height: 1.45, color: SlabColors.sage),
    labelLarge: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    labelMedium: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
    // Field and section labels, which are always upper-cased by the caller.
    labelSmall: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
      color: SlabColors.goldDim,
    ),
  );

  const pill = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(SlabRadii.pill)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: SlabColors.ink950,
    // What `DropdownButton` paints its open menu with.
    canvasColor: SlabColors.ink800,
    dividerColor: SlabColors.line,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: const IconThemeData(color: SlabColors.sage, size: 20),
    dividerTheme: const DividerThemeData(
      color: SlabColors.line,
      thickness: 1,
      space: 1,
    ),
    // Panels float over a bright basemap, so they carry a real shadow as well
    // as the doc's hairline border — the border alone disappears against
    // snow, sand or a lake.
    cardTheme: const CardThemeData(
      color: SlabColors.ink800,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0xB3000000),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SlabRadii.panel)),
        side: BorderSide(color: SlabColors.line),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: SlabColors.ink800,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: SlabColors.cream,
      ),
      contentTextStyle: TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: SlabColors.sage,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: SlabColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SlabColors.ink700,
      hintStyle: const TextStyle(color: SlabColors.sageDim, fontSize: 13.5),
      labelStyle: const TextStyle(color: SlabColors.sage, fontSize: 13.5),
      floatingLabelStyle: const TextStyle(color: SlabColors.gold),
      helperStyle: textTheme.bodySmall,
      counterStyle: textTheme.bodySmall,
      border: _inputBorder(SlabColors.line),
      enabledBorder: _inputBorder(SlabColors.line),
      focusedBorder: _inputBorder(SlabColors.gold, width: 1.5),
      disabledBorder: _inputBorder(SlabColors.line),
      errorBorder: _inputBorder(SlabColors.rust),
      focusedErrorBorder: _inputBorder(SlabColors.rust, width: 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SlabColors.gold,
        foregroundColor: SlabColors.onGold,
        disabledBackgroundColor: SlabColors.ink700,
        disabledForegroundColor: SlabColors.sageDim,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: pill,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SlabColors.cream,
        backgroundColor: SlabColors.ink700,
        side: const BorderSide(color: SlabColors.line),
        minimumSize: const Size(0, 38),
        shape: pill,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SlabColors.gold,
        shape: pill,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: SlabColors.sage,
        hoverColor: SlabColors.goldSoft,
        highlightColor: SlabColors.goldSoft,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SlabColors.gold
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(SlabColors.onGold),
      side: const BorderSide(color: SlabColors.sageDim, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      visualDensity: VisualDensity.compact,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SlabColors.goldSoft
              : SlabColors.ink900,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SlabColors.gold
              : SlabColors.sage,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? SlabColors.gold
                : SlabColors.line,
          ),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        shape: const WidgetStatePropertyAll(pill),
        visualDensity: VisualDensity.compact,
      ),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(SlabColors.ink800),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(SlabRadii.card)),
            side: BorderSide(color: SlabColors.line),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        foregroundColor: SlabColors.cream,
        textStyle: const TextStyle(fontSize: 13.5),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: SlabColors.ink800,
      surfaceTintColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: SlabColors.ink900,
        borderRadius: BorderRadius.circular(SlabRadii.control),
        border: Border.all(color: SlabColors.line),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: SlabColors.cream),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SlabColors.ink900,
      contentTextStyle: const TextStyle(
        color: SlabColors.cream,
        fontSize: 13.5,
      ),
      actionTextColor: SlabColors.gold,
      closeIconColor: SlabColors.sage,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SlabRadii.card),
        side: const BorderSide(color: SlabColors.line),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SlabColors.gold,
      linearTrackColor: SlabColors.ink700,
      circularTrackColor: Colors.transparent,
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: SlabColors.gold,
      textColor: SlabColors.onGold,
      textStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: SlabColors.gold,
      selectionColor: SlabColors.goldSoft,
      selectionHandleColor: SlabColors.gold,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: const WidgetStatePropertyAll(SlabColors.ink600),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(SlabRadii.control),
      borderSide: BorderSide(color: color, width: width),
    );
