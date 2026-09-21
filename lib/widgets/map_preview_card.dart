import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';

class MapPreviewCard extends StatefulWidget {
  const MapPreviewCard({
    this.latitude,
    this.longitude,
    this.locationText,
    super.key,
  });
  final double? latitude;
  final double? longitude;
  final String? locationText;

  @override
  State<MapPreviewCard> createState() => _MapPreviewCardState();
}

class _MapPreviewCardState extends State<MapPreviewCard> {
  bool _tileFailed = false;
  int _reload = 0;

  bool get _hasCoordinates =>
      widget.latitude != null &&
      widget.longitude != null &&
      widget.latitude!.isFinite &&
      widget.longitude!.isFinite &&
      widget.latitude!.abs() <= 90 &&
      widget.longitude!.abs() <= 180;

  @override
  void didUpdateWidget(MapPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _tileFailed = false;
    }
  }

  Future<void> _openMap() async {
    if (!_hasCoordinates) return;
    try {
      final opened = await launchUrl(
        Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': '${widget.latitude},${widget.longitude}',
        }),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      /* The platform can refuse an external activity launch. */
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open Maps. Check your browser or map app.'),
      ),
    );
  }

  Future<void> _openAttribution() async {
    try {
      if (await launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
      )) {
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open map attribution. Check your browser.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordinates = _hasCoordinates
        ? '${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}'
        : 'Location unavailable';
    return Container(
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: !_hasCoordinates
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: AppColors.textMuted,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.locationText ?? coordinates,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        key: ValueKey(
                          '${widget.latitude},${widget.longitude}:$_reload',
                        ),
                        options: MapOptions(
                          initialCenter: LatLng(
                            widget.latitude!,
                            widget.longitude!,
                          ),
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(
                            flags:
                                InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.suno_ai',
                            errorTileCallback: (_, _, _) {
                              if (_tileFailed) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _tileFailed = true);
                              });
                            },
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(
                                  widget.latitude!,
                                  widget.longitude!,
                                ),
                                width: 42,
                                height: 42,
                                child: const Icon(
                                  Icons.location_on,
                                  color: AppColors.emergency,
                                  size: 42,
                                ),
                              ),
                            ],
                          ),
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                                onTap: _openAttribution,
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_tileFailed)
                        Positioned(
                          top: 6,
                          left: 8,
                          right: 8,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text(
                                      'Map tiles unavailable. Coordinates are still usable.',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _tileFailed = false;
                                    _reload++;
                                  }),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.locationText ?? coordinates,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openMap,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('OPEN'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
