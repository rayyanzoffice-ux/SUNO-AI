import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';

class MapPreviewCard extends StatelessWidget {
  const MapPreviewCard({
    this.latitude,
    this.longitude,
    this.locationText,
    super.key,
  });

  final double? latitude;
  final double? longitude;
  final String? locationText;

  Future<void> _openExternalMap() async {
    if (latitude == null || longitude == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = latitude != null && longitude != null;
    return GestureDetector(
      onTap: hasCoords ? _openExternalMap : null,
      child: Container(
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3EC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: hasCoords
            ? _RealMap(
                latitude: latitude!,
                longitude: longitude!,
                locationText: locationText,
                onOpenExternal: _openExternalMap,
              )
            : _NoLocationPlaceholder(locationText: locationText),
      ),
    );
  }
}

class _RealMap extends StatelessWidget {
  const _RealMap({
    required this.latitude,
    required this.longitude,
    this.locationText,
    required this.onOpenExternal,
  });

  final double latitude;
  final double longitude;
  final String? locationText;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.suno_ai',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 42,
                  height: 42,
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.emergency,
                    size: 42,
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.near_me_rounded,
                    color: AppColors.purple, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    locationText ??
                        '${latitude.toStringAsFixed(4)}, '
                        '${longitude.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onOpenExternal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded,
                            color: AppColors.purple, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'OPEN',
                          style: TextStyle(
                            color: AppColors.purple,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoLocationPlaceholder extends StatelessWidget {
  const _NoLocationPlaceholder({this.locationText});
  final String? locationText;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded,
                color: AppColors.textMuted, size: 36),
            const SizedBox(height: 10),
            Text(
              locationText ?? 'Location unavailable',
              style: const TextStyle(
                  color: AppColors.textMuted, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
