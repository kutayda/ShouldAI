import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// Bir rota üzerindeki konum + o noktadaki gidiş açısını taşır.
class InterpolationResult {
  final LatLng position;
  final double bearing;
  InterpolationResult(this.position, this.bearing);
}

/// İki nokta arası gidiş açısı (kuzeyden saat yönünde, 0-360 derece).
double calculateExactBearing(LatLng start, LatLng end) {
  double lat1 = start.latitude * math.pi / 180;
  double lng1 = start.longitude * math.pi / 180;
  double lat2 = end.latitude * math.pi / 180;
  double lng2 = end.longitude * math.pi / 180;
  double dLon = lng2 - lng1;
  double y = math.sin(dLon) * math.cos(lat2);
  double x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  double brng = math.atan2(y, x);
  return (brng * 180 / math.pi + 360) % 360;
}

/// Rota (points) üzerinde 0..1 arası kesirde konumu ve o anki açıyı hesaplar.
/// points boşsa [fallback] döner.
InterpolationResult getInterpolatedPositionAndBearing(
  List<LatLng> points,
  double fraction,
  LatLng fallback,
) {
  if (points.isEmpty) return InterpolationResult(fallback, 0);
  if (fraction <= 0) {
    double b = points.length > 1
        ? calculateExactBearing(points[0], points[1])
        : 0;
    return InterpolationResult(points.first, b);
  }
  if (fraction >= 1) {
    double b = points.length > 1
        ? calculateExactBearing(points[points.length - 2], points.last)
        : 0;
    return InterpolationResult(points.last, b);
  }

  double totalDist = 0;
  List<double> distances = [];
  for (int i = 0; i < points.length - 1; i++) {
    double d = Geolocator.distanceBetween(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );
    totalDist += d;
    distances.add(d);
  }

  if (totalDist == 0) return InterpolationResult(points.first, 0);

  double targetDist = totalDist * fraction;
  double currentDist = 0;

  for (int i = 0; i < points.length - 1; i++) {
    if (currentDist + distances[i] >= targetDist) {
      double segmentFraction = (distances[i] == 0)
          ? 0
          : (targetDist - currentDist) / distances[i];
      double lat =
          points[i].latitude +
          (points[i + 1].latitude - points[i].latitude) * segmentFraction;
      double lng =
          points[i].longitude +
          (points[i + 1].longitude - points[i].longitude) * segmentFraction;
      double bearing = calculateExactBearing(points[i], points[i + 1]);
      return InterpolationResult(LatLng(lat, lng), bearing);
    }
    currentDist += distances[i];
  }
  double finalBearing = points.length > 1
      ? calculateExactBearing(points[points.length - 2], points.last)
      : 0;
  return InterpolationResult(points.last, finalBearing);
}
