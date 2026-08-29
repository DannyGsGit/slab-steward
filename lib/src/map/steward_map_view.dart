import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre/maplibre.dart';

import '../model/difficulty.dart';
import '../state/steward_state.dart';
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
      },
      // A pan is not a click. MapLibre suppresses its own click after a drag
      // anyway; this keeps a stale press from outliving one that didn't.
      onPointerMove: (event) {
        if (_pressOnMap case final press?
            when (event.localPosition - press).distance > _clickSlop) {
          _pressOnMap = null;
        }
      },
      onPointerCancel: (_) {
        _pressOnMap = null;
        _pressAddsToSelection = false;
      },
      child: _buildMap(),
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
        // The staged difficulty, drawn halfway along each glowing trail. A
        // widget layer rather than a symbol layer: the glyph vocabulary is
        // already a [DifficultyIcon], and the basemap sprite has no way to
        // learn a green circle or a double black diamond.
        WidgetLayer(markers: _stagedBadges()),
        // OSM data and OSM US's tiles both have to be credited on screen.
        const SourceAttribution(alignment: Alignment.bottomRight),
        const MapControlButtons(
          alignment: Alignment.bottomRight,
          padding: EdgeInsets.only(right: 12, bottom: 44),
        ),
      ],
    );
  }

  /// One badge per trail whose pending edit has a difficulty to show.
  List<Marker> _stagedBadges() => [
    for (final trail in widget.state.stagedTrails)
      if (trail.difficulty case final difficulty?)
        if (trail.badgePoint case final point?)
          Marker(
            point: Geographic(lon: point[0], lat: point[1]),
            size: _StagedBadge.sizeFor(difficulty),
            child: _StagedBadge(difficulty),
          ),
  ];
}

/// The pending difficulty as it reads on the map: the same signage glyph the
/// panel shows, on a chip ringed in the glow's blue so it's legible against
/// whatever the trail is crossing.
class _StagedBadge extends StatelessWidget {
  const _StagedBadge(this.difficulty);

  final Difficulty difficulty;

  static const _glyphSize = 13.0;
  static const _padding = 4.0;

  static Size sizeFor(Difficulty difficulty) => Size(
    DifficultyIcon.widthFor(difficulty, _glyphSize) + _padding * 2 + 3,
    _glyphSize + _padding * 2 + 3,
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(_padding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _glowColor, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: DifficultyIcon(difficulty, size: _glyphSize),
      ),
    );
  }

  static final Color _glowColor = Color(
    int.parse(stagedEditColor.substring(1), radix: 16) | 0xFF000000,
  );
}
