import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Mavi konum noktası ikonu (aura + beyaz çerçeve + çekirdek).
Future<BitmapDescriptor> buildBlueDot() async {
  const double size = 60;
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);
  const Offset center = Offset(size / 2, size / 2);
  final Paint auraPaint = Paint()
    ..color = Colors.blueAccent.withValues(alpha: 0.15);
  canvas.drawCircle(center, size / 2, auraPaint);
  final Paint borderPaint = Paint()..color = Colors.white;
  canvas.drawCircle(center, 12, borderPaint);
  final Paint corePaint = Paint()..color = Colors.blueAccent;
  canvas.drawCircle(center, 8, corePaint);
  final ui.Image image = await pictureRecorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
}

/// Belirtilen yöne (derece, kuzeyden saat yönünde) döndürülmüş ok ikonu üretir.
/// Web'de marker.rotation bitmap ikonlarda çalışmadığı için dönüşü doğrudan
/// ikonun kendisine çiziyoruz — böylece işaretin açısı her platformda değişir.
Future<BitmapDescriptor> buildRotatedArrow(double bearingDeg) async {
  const double size = 50;
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);

  // Merkez etrafında döndür
  canvas.translate(size / 2, size / 2);
  canvas.rotate(bearingDeg * math.pi / 180.0);
  canvas.translate(-size / 2, -size / 2);

  final Paint shadowPaint = Paint()
    ..color = Colors.black38
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final Paint paint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  final Paint borderPaint = Paint()
    ..color = Colors.grey.shade400
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint centerLinePaint = Paint()
    ..color = Colors.grey.shade300
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;

  final Path path = Path();
  path.moveTo(size / 2, 5);
  path.lineTo(size - 10, size - 10);
  path.lineTo(size / 2, size - 20);
  path.lineTo(10, size - 10);
  path.close();

  canvas.drawPath(path.shift(const Offset(0, 3)), shadowPaint);
  canvas.drawPath(path, paint);
  canvas.drawPath(path, borderPaint);
  canvas.drawLine(
    Offset(size / 2, 10),
    Offset(size / 2, size - 30),
    centerLinePaint,
  );

  final ui.Image image = await pictureRecorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
}
