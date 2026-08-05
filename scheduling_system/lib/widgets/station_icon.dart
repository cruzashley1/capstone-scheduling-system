// widgets/station_icon.dart
//
// The station logo image (assets/images/station_logo.png), used wherever
// the app previously showed the generic Icons.location_city material icon.
// Rendered raw (no chip/backing container): the PNG has transparent
// corners and an opaque white interior, so it reads on any surface.
import 'package:flutter/material.dart';

class StationIcon extends StatelessWidget {
  final double size;

  const StationIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/station_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
