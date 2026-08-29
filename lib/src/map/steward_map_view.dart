import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre/maplibre.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../model/difficulty.dart';
import '../model/electric_bicycle.dart';
import '../state/steward_state.dart';
import '../ui/slab_theme.dart';
import 'otm_conventions.dart';
import 'steward_style.dart';

/// The map. Renders OSM US's trail tileset over the published OpenTrailMap
/// basemap, and turns a click into a trail selection.
class StewardMapView extends StatefulWidget {
  const StewardMapView({
    super.key,
    required this.state,
    this.initialCenter = const Geographic(lon: -121.9800, lat: 47.5800),
    this.initialZoom = 14.5,
  });

  final StewardState state;

  /// Defaults to Grand Ridge / Duthie Hill, east of Seattle — one of the
  /// densest clusters of `mtb:scale:imba` tagging in the region, and still
  /// patchy enough that the default lenses have something to say on load.
  final Geographic initialCenter;
  final double initialZoom;

  @override
  State<StewardMapView> createState() => _StewardMapViewState();
}

/// How far a press may travel and still count as the click MapLibre reports.
const _clickSlop = 8.0;

/// A `#rrggbb` from the OpenTrailMap conventions, as a Flutter colour.
Color _opaque(String hex) =>
    Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

class _StewardMapViewState extends State<StewardMapView> {
  MapController? _controller;
  StyleController? _style;

  /// The undecorated OpenTrailMap stylesheet, fetched once and re-spliced
  /// whenever the mode or lens selection changes.
  Map<String, Object?>? _baseStyle;
  String? _loadError;

  int _appliedStyleRevision = -1;
  int _appliedStagedRevision = -1;

  /// The way ids currently drawn in the selection source, so a rebuild that
  /// didn't change the working set doesn't re-encode it.
  String? _appliedHighlight;

  bool _appliedListOpen = false;

  /// The style handed to [MapLibreMap] at creation, kept so a rebuild for the
  /// staged badges doesn't re-encode the whole document. Later style changes
  /// go through [MapController.setStyle], not through this.
  String? _initialStyleJson;

  /// Where Flutter last saw a press land on the map itself.
  ///
  /// On web the map is an `HtmlElementView`, and MapLibre GL JS listens for
  /// clicks on that DOM element directly. The browser delivers those clicks
  /// even when a Flutter panel, dropdown or dialog is painted on top, so a tap
  /// on the trail panel would otherwise also read as a tap on empty map — and
  /// clear the very selection the panel is showing. Flutter's own hit test
  /// does stop at the overlay, so a press it never saw here wasn't the map's.
  Offset? _pressOnMap;

  /// Whether the modifier that means "add to the selection" was down when that
  /// press landed.
  ///
  /// Read at press time rather than at click time: MapLibre reports the click
  /// afterwards, by which point the key may already be up.
  bool _pressAddsToSelection = false;

  /// Where a modified press landed, for as long as it's down.
  ///
  /// Non-null is also what suspends the map's own drag gestures: the box is
  /// drawn in screen space, and a map that panned or rotated under it would
  /// hand back a different set of trails than the one the rider outlined.
  Offset? _boxAnchor;

  /// The opposite corner of that box, once the press has travelled far enough
  /// to be a drag rather than a click. Null while it hasn't.
  Offset? _boxCorner;

  /// The box being dragged right now, if one is.
  Rect? get _selectionBox => switch ((_boxAnchor, _boxCorner)) {
    (final anchor?, final corner?) => Rect.fromPoints(anchor, corner),
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _loadBaseStyle();
    _pruneStaleOverrides();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  /// Drops overrides the tileset has caught up with.
  ///
  /// The TileJSON publishes the timestamp of the planet build it was cut
  /// from, which is exactly the question an override needs answered: anything
  /// Steward observed before that build is now in the tiles themselves, and
  /// keeping it would just be a second copy going stale in its own right.
  ///
  Future<void> _pruneStaleOverrides() async {
    final builtAt = await fetchTilesetBuiltAt();
    if (!mounted || builtAt == null) return;
    widget.state.overrides.pruneObservedBefore(builtAt);
  }

  Future<void> _loadBaseStyle() async {
    try {
      final response = await http.get(Uri.parse(openTrailMapStyleUrl));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _baseStyle = jsonDecode(response.body) as Map<String, Object?>;
        _appliedStyleRevision = widget.state.styleRevision;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the base map style: $e');
    }
  }

  /// A fresh style document for the current mode and lens selection.
  ///
  /// [buildStewardStyle] mutates what it's given, so this re-decodes the cached
  /// base each time rather than handing over the same map twice.
  String _currentStyleJson() {
    final base = jsonDecode(jsonEncode(_baseStyle)) as Map<String, Object?>;
    final overrides = widget.state.overrides;
    return jsonEncode(
      buildStewardStyle(
        base,
        mode: widget.state.mode,
        lenses: widget.state.lenses,
        tags: overrides.isEmpty
            ? const TagSource.tiles()
            : TagSource.overriding(overrides.byTileId),
      ),
    );
  }

  void _onStateChanged() {
    final state = widget.state;

    if (state.styleRevision != _appliedStyleRevision && _baseStyle != null) {
      _appliedStyleRevision = state.styleRevision;
      _controller?.setStyle(_currentStyleJson());
      // setStyle resets every source, so the highlight and the glow have to be
      // re-pushed once the new style reports in via onStyleLoaded.
      _appliedHighlight = null;
      _appliedStagedRevision = -1;
    }

    _syncHighlight();
    _syncStagedGlow();

    // Opening the list is a question about the current viewport, so it gets
    // answered the moment it's asked rather than at the next camera idle.
    if (state.isTrailListOpen != _appliedListOpen) {
      _appliedListOpen = state.isTrailListOpen;
      if (state.isTrailListOpen) _refreshVisibleTrails();
    }
  }

  /// Reports every trail the map is currently drawing to [StewardState], for
  /// the in-view list to render.
  ///
  /// Only while that list is open: this queries the whole viewport against the
  /// pointer-target layer, which at low zoom is a lot of features to hand back
  /// on every idle for nobody to look at.
  void _refreshVisibleTrails() {
    if (!widget.state.isTrailListOpen) return;
    final controller = _controller;
    // This can land from a MapLibre callback mid-frame, before the map has a
    // size to query against.
    final box = context.findRenderObject();
    if (controller == null || box is! RenderBox || !box.hasSize) return;

    final hits = controller.featuresInRect(
      Offset.zero & box.size,
      layerIds: [pointerTargetLayerId],
    );
    widget.state.setVisibleTrails([for (final hit in hits) hit.properties]);
  }

  /// Pushes the geometry of every trail with a pending edit into the glow
  /// source, and rebuilds so the badges move with it.
  void _syncStagedGlow() {
    if (widget.state.stagedRevision == _appliedStagedRevision) return;
    _appliedStagedRevision = widget.state.stagedRevision;

    _style?.updateGeoJsonSource(
      id: stagedSourceId,
      data: jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final trail in widget.state.stagedTrails)
            ?trail.toGeoJsonFeature(),
        ],
      }),
    );
    // Deferred because this also runs from onStyleLoaded, which can land
    // mid-frame — the badges only need to be right by the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Pushes the geometry of every selected trail into the highlight source.
  ///
  /// Geometry only exists once the OSM API responds, so a freshly clicked trail
  /// is a no-op on the first notification and does the real work on the second.
  /// Trails ticked in bulk from the list have no geometry until something asks
  /// for it — the list itself is their feedback, and the map picks them up as
  /// they resolve.
  void _syncHighlight() {
    final style = _style;
    if (style == null) return;

    final drawable = [
      for (final trail in widget.state.selectedTrails)
        if (trail.geometry != null) trail,
    ];
    final signature = drawable.map((t) => t.osmWayId).join(',');
    if (signature == _appliedHighlight) return;
    _appliedHighlight = signature;

    style.updateGeoJsonSource(
      id: selectionSourceId,
      data: jsonEncode({
        'type': 'FeatureCollection',
        'features': [for (final trail in drawable) trail.toGeoJsonFeature()],
      }),
    );
  }

  /// Turns the box just dragged into a selection: every trail with any part
  /// of it under the box joins the working set.
  ///
  /// MapLibre suppresses its own click after a drag, so the click path never
  /// sees this gesture — and a modified press that never became a drag falls
  /// through to it untouched.
  void _finishBox() {
    final box = _selectionBox;
    _clearBox();
    if (box == null) return;

    final hits = _controller?.featuresInRect(
      box,
      layerIds: [pointerTargetLayerId],
    );
    // A box that caught nothing is a miss, not "clear everything" — the same
    // reading a modified click on empty map gets.
    if (hits == null || hits.isEmpty) return;
    widget.state.addFromTiles([for (final hit in hits) hit.properties]);
  }

  /// Drops the box and gives the map its gestures back.
  void _clearBox() {
    if (_boxAnchor == null && _boxCorner == null) return;
    setState(() {
      _boxAnchor = null;
      _boxCorner = null;
    });
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle || event is MapEventIdle) {
      _refreshVisibleTrails();
      return;
    }
    if (event is! MapEventClick) return;
    final controller = _controller;
    if (controller == null) return;

    // Only act on a click whose press Flutter routed to the map. A press
    // consumed by the chrome above never reaches [_pressOnMap], and a stale
    // one is spent here so it can't authorise a later click.
    final press = _pressOnMap;
    final addsToSelection = _pressAddsToSelection;
    _pressOnMap = null;
    _pressAddsToSelection = false;
    if (press == null || (press - event.screenPoint).distance > _clickSlop) {
      return;
    }

    final hits = controller.featuresAtPoint(
      event.screenPoint,
      layerIds: [pointerTargetLayerId],
    );
    if (hits.isEmpty) {
      // A modified click on empty map is a miss, not "clear everything" — the
      // rider is part-way through assembling a set and just missed the line.
      if (!addsToSelection) widget.state.clearSelection();
      return;
    }
    if (addsToSelection) {
      widget.state.toggleFromTile(hits.first.properties);
    } else {
      widget.state.selectFromTile(hits.first.properties);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    if (_baseStyle == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _pressOnMap = event.localPosition;
        // Ctrl on Windows and Linux, Cmd on macOS — where ctrl-click is a
        // right-click and never reaches us as a click at all.
        final keyboard = HardwareKeyboard.instance;
        _pressAddsToSelection =
            keyboard.isControlPressed || keyboard.isMetaPressed;
        // The map stops responding to drags for the whole of a modified
        // press, not just once one turns into a box: MapLibre pans — and
        // under ctrl rotates — off the browser's own listeners, so a rebuild
        // that only landed after the first move would have let the map slide
        // out from under the first few pixels of the box.
        if (_pressAddsToSelection) {
          setState(() => _boxAnchor = event.localPosition);
        }
      },
      // A pan is not a click. MapLibre suppresses its own click after a drag
      // anyway; this keeps a stale press from outliving one that didn't.
      onPointerMove: (event) {
        if (_pressOnMap case final press?
            when (event.localPosition - press).distance > _clickSlop) {
          _pressOnMap = null;
        }
        // A modified press only becomes a box once it has travelled further
        // than the click it would otherwise have been.
        if (_boxAnchor case final anchor?) {
          if (_boxCorner == null &&
              (event.localPosition - anchor).distance <= _clickSlop) {
            return;
          }
          setState(() => _boxCorner = event.localPosition);
        }
      },
      onPointerUp: (_) => _finishBox(),
      onPointerCancel: (_) {
        _pressOnMap = null;
        _pressAddsToSelection = false;
        _clearBox();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildMap(),
          if (_selectionBox case final box?)
            Positioned.fromRect(
              rect: box,
              // The press this is tracking belongs to the [Listener] above.
              child: const IgnorePointer(child: _SelectionBox()),
            ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return MapLibreMap(
      options: MapOptions(
        initStyle: _initialStyleJson ??= _currentStyleJson(),
        initCenter: widget.initialCenter,
        initZoom: widget.initialZoom,
        // No trails render below the overlay's minzoom, but the basemap
        // itself is happy at continent scale, so let users zoom out that far.
        minZoom: 2,
        maxZoom: 20,
        // Panning, rotating and tilting are all the same drag the selection
        // box is made of, so they stand down while one is being drawn. See
        // [_boxAnchor].
        gestures: _boxAnchor == null
            ? const MapGestures.all()
            : const MapGestures.all(pan: false, rotate: false, pitch: false),
      ),
      onMapCreated: (controller) => _controller = controller,
      onStyleLoaded: (style) {
        _style = style;
        _appliedHighlight = null;
        _appliedStagedRevision = -1;
        _syncHighlight();
        _syncStagedGlow();
        // A new style means new filters, and the list only ever shows what the
        // map is actually drawing.
        _refreshVisibleTrails();
      },
      onEvent: _onEvent,
      children: [
        // The staged difficulty and e-bike permission, drawn halfway along
        // each glowing trail. A widget layer rather than a symbol layer: the
        // glyph vocabulary is already a [DifficultyIcon] and an [EbikeIcon],
        // and the basemap sprite has no way to learn a green circle, a double
        // black diamond, or a struck-through e-bike.
        WidgetLayer(markers: _stagedBadges()),
        // OSM data and OSM US's tiles both have to be credited on screen.
        const SourceAttribution(alignment: Alignment.bottomRight),
        const _ZoomButtons(),
      ],
    );
  }

  /// One badge per trail whose pending edits have something to show. A trail
  /// can have both a difficulty and an e-bike permission pending, and they
  /// share the one chip rather than fighting over the same midpoint.
  List<Marker> _stagedBadges() => [
    for (final trail in widget.state.stagedTrails)
      if (trail.difficulty != null || trail.electricBicycle != null)
        if (trail.badgePoint case final point?)
          Marker(
            point: Geographic(lon: point[0], lat: point[1]),
            size: _StagedBadge.sizeFor(
              trail.difficulty,
              trail.electricBicycle,
            ),
            child: _StagedBadge(trail.difficulty, trail.electricBicycle),
          ),
  ];
}

/// The pending edits as they read on the map: the same signage glyph and
/// e-bike glyph the panel shows, on a chip ringed in the glow's blue so
/// they're legible against whatever the trail is crossing.
///
/// Ink rather than white — this is chrome, and SLAB's chrome is dark whatever
/// the basemap under it is doing. The signage chips carry their own gold
/// outline, so they read against it the way they read on a trail sign.
class _StagedBadge extends StatelessWidget {
  const _StagedBadge(this.difficulty, this.electricBicycle);

  /// Null when that attribute has nothing pending — at least one of the two
  /// is always set, or the badge wouldn't have been built.
  final Difficulty? difficulty;
  final EbikeAccess? electricBicycle;

  static const _glyphSize = 13.0;
  static const _padding = 4.0;

  /// The e-bike glyph is a square icon, so it's as wide as it is tall.
  static const _ebikeSize = 14.0;

  /// Between the two glyphs when a trail has both pending.
  static const _gap = 4.0;

  static Size sizeFor(Difficulty? difficulty, EbikeAccess? electricBicycle) {
    var width = 0.0;
    if (difficulty != null) width += _glyphSize;
    if (electricBicycle != null) {
      width += (width > 0 ? _gap : 0) + _ebikeSize;
    }
    return Size(
      width + _padding * 2 + 3,
      math.max(_glyphSize, _ebikeSize) + _padding * 2 + 3,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(_padding),
        decoration: BoxDecoration(
          color: SlabColors.ink900,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _glowColor, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (difficulty case final difficulty?)
              DifficultyIcon(difficulty, size: _glyphSize),
            if (difficulty != null && electricBicycle != null)
              const SizedBox(width: _gap),
            if (electricBicycle case final access?)
              EbikeIcon(access, size: _ebikeSize),
          ],
        ),
      ),
    );
  }

  static final Color _glowColor = _opaque(stagedEditColor);
}

/// The rubber band a ctrl/cmd-drag draws across the map.
///
/// In the same yellow the map highlights a selected trail with, so the box and
/// what it will leave behind read as one gesture. Filled rather than outlined
/// alone: the fill is what says the trails under it are what's being named.
class _SelectionBox extends StatelessWidget {
  const _SelectionBox();

  static final Color _color = _opaque(selectionColor);

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _color.withValues(alpha: 0.18),
      border: Border.all(color: _color, width: 1.5),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// Zoom in and out, in SLAB's own hand.
///
/// The plugin's [MapControlButtons] is a pair of full-size floating action
/// buttons, which the package itself suggests copying and adjusting rather
/// than fighting. Steward wants them half that size and wearing the gold the
/// rest of the chrome spends on "press this" — the map is the thing on
/// screen, and its controls shouldn't outweigh a panel.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons();

  /// Half of a [FloatingActionButton]'s 56.
  static const _size = 28.0;

  @override
  Widget build(BuildContext context) {
    final controller = MapController.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    void zoomBy(double delta) => controller.animateCamera(
      zoom: controller.getCamera().zoom + delta,
      nativeDuration: const Duration(milliseconds: 200),
    );

    return SafeArea(
      child: Container(
        alignment: Alignment.bottomRight,
        padding: const EdgeInsets.only(right: 12, bottom: 44),
        // The map underneath would otherwise swallow the taps on web.
        child: PointerInterceptor(
          child: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: () => zoomBy(1),
              ),
              _ZoomButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: () => zoomBy(-1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SlabColors.gold,
        borderRadius: BorderRadius.circular(SlabRadii.control),
        clipBehavior: Clip.antiAlias,
        elevation: 4,
        shadowColor: const Color(0xB3000000),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: _ZoomButtons._size,
            child: Icon(icon, size: 16, color: SlabColors.onGold),
          ),
        ),
      ),
    );
  }
}
