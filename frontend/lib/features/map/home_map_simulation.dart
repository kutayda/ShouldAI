part of 'home_map_screen.dart';

extension _HMSimulation on _HomeMapScreenState {
  Future<void> _fetchBackgroundRecommendations() async {
    if (_simCurrentPath.isEmpty) return;
    LatLng finalDest = _simCurrentPath.last;

    LatLng pos20 = getInterpolatedPositionAndBearing(
      _simCurrentPath,
      20.0 / 60.0,
      _center,
    ).position;
    LatLng pos40 = getInterpolatedPositionAndBearing(
      _simCurrentPath,
      40.0 / 60.0,
      _center,
    ).position;

    double recRadius = _totalRouteDistanceKm < 5.0 ? 3.0 : 5.0;

    http
        .post(
          Uri.parse('$baseUrl/api/single_recommendation'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "preference": "Kafe",
            "radius_km": recRadius,
            "current_lat": pos20.latitude,
            "current_lng": pos20.longitude,
            "dest_lat": finalDest.latitude,
            "dest_lng": finalDest.longitude,
            "liked_cuisines": _likedCuisines,
            "disliked_cuisines": _dislikedCuisines,
            "mode": _recommendationMode,
          }),
        )
        .then((res) {
          if (res.statusCode == 200) {
            final d = jsonDecode(utf8.decode(res.bodyBytes));
            if (d['status'] == 'success') _prefetchedCafe = d;
          }
        })
        .catchError((_) {});

    http
        .post(
          Uri.parse('$baseUrl/api/single_recommendation'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "preference": "Restoran",
            "radius_km": recRadius,
            "current_lat": pos40.latitude,
            "current_lng": pos40.longitude,
            "dest_lat": finalDest.latitude,
            "dest_lng": finalDest.longitude,
            "liked_cuisines": _likedCuisines,
            "disliked_cuisines": _dislikedCuisines,
            "mode": _recommendationMode,
          }),
        )
        .then((res) {
          if (res.statusCode == 200) {
            final d = jsonDecode(utf8.decode(res.bodyBytes));
            if (d['status'] == 'success') _prefetchedRest = d;
          }
        })
        .catchError((_) {});
  }

  void _startTimer() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isSimulating) return;

      rebuild(() {
        _simSegmentElapsed += 0.1;
        if (!_travelingToStop) _activeDrivingTime += 0.1;

        double fraction = _simSegmentElapsed / _simSegmentDuration;
        if (fraction > 1.0) fraction = 1.0;

        InterpolationResult result = getInterpolatedPositionAndBearing(
          _simCurrentPath,
          fraction,
          _center,
        );
        _simCurrentPos = result.position;
        _currentBearing = result.bearing;

        // İşaretin açısını gidiş yönüne göre güncelle (ikon döndürülerek)
        _ensureArrowForBearing(_currentBearing);
        _guncelleMarker(_simCurrentPos!, _navArrowIcon, 0);

        // Harita kuzeye sabit; yön bilgisi ok ikonunun kendisinde.
        mapController?.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _simCurrentPos!,
              zoom: 17.0,
              tilt: 45.0,
              bearing: 0.0,
            ),
          ),
        );

        double remaining = _simSegmentDuration - _simSegmentElapsed;
        if (remaining < 0) remaining = 0;
        _sureText = "${remaining.toStringAsFixed(0)} sn";
        _mesafeText = "${(remaining * 0.08).toStringAsFixed(1)} km";

        if (!_travelingToStop) {
          if (_activeDrivingTime >= 20.0 &&
              _activeDrivingTime < 21.0 &&
              !_simCafePrompted) {
            _simCafePrompted = true;
            _triggerInstantPrompt(
              "Kafe",
              "Yorulmuşa benziyorsun, molaya ne dersin?",
              _prefetchedCafe,
            );
            return;
          }
          if (_activeDrivingTime >= 40.0 &&
              _activeDrivingTime < 41.0 &&
              !_simRestPrompted) {
            _simRestPrompted = true;
            _triggerInstantPrompt(
              "Restoran",
              "Acıkmış olabilirsin, bir şeyler yemeye ne dersin?",
              _prefetchedRest,
            );
            return;
          }

          if (fraction >= 1.0) {
            _simTimer?.cancel();
            _finishSimulation();
          }
        } else {
          if (fraction >= 1.0) {
            _simTimer?.cancel();
            _showStopReachedDialog();
          }
        }
      });
    });
  }

  void _startSimulation() {
    if (_simCurrentPath.isEmpty) return;

    rebuild(() {
      _isSimulating = true;
      _secilenHedef = null;
      _navigasyonPanelAcik = true;
      _activeDrivingTime = 0.0;
      _simSegmentElapsed = 0.0;
      _simSegmentDuration = 60.0;
      _simCafePrompted = false;
      _simRestPrompted = false;
      _travelingToStop = false;
      _simCurrentPos = LatLng(_myLat!, _myLng!);
    });

    _prefetchedCafe = null;
    _prefetchedRest = null;
    _fetchBackgroundRecommendations();
    _startTimer();
  }

  void _showStopReachedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Icon(
          Icons.place_rounded,
          color: Colors.blueAccent,
          size: 50,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              "Durak noktasına ulaştınız!",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              "Ana hedefinize devam etmek için basınız:",
              style: TextStyle(fontSize: 14, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _resumeJourneyAfterStop();
                },
                child: const Text(
                  "Devam Et",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resumeJourneyAfterStop() {
    rebuild(() {
      _travelingToStop = false;
      _simCurrentPath = _savedMainRemainingPath;
      _simSegmentElapsed = 0.0;
      _simSegmentDuration = _savedMainRemainingDuration;
      _currentTargetName = _hedefAdresi;
      _isSimulating = true;
    });
    _startTimer();
  }

  Future<void> _triggerInstantPrompt(
    String type,
    String message,
    Map<String, dynamic>? preloadedData,
  ) async {
    _isSimulating = false;
    LatLng currentSimLock = _simCurrentPos!;
    Map<String, dynamic>? data = preloadedData;

    if (data == null || data['status'] != 'success') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Bu bölgede uygun mola yeri bulunamadı, yolculuğa devam ediliyor.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      _isSimulating = true;
      return;
    }

    final LatLng mekanPos = LatLng(
      double.parse(data['lat'].toString()),
      double.parse(data['lng'].toString()),
    );

    bool? accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 25),
              Icon(
                type == "Kafe"
                    ? Icons.local_cafe
                    : type == "Benzinlik"
                    ? Icons.local_gas_station
                    : Icons.restaurant,
                color: Colors.blueAccent,
                size: 45,
              ),
              const SizedBox(height: 15),
              const Text(
                "Akıllı Öneri",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              if ((data['fallback_note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  data['fallback_note'].toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.blueGrey,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 12,
                ),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      "⭐ ${data['puan']}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${data['mekan_adi']}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 5,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    "Durak Ekle",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx, false);
                    _isSimulating =
                        true; // sim modunu koru ki yeniden sim yoluna gitsin
                    final lat = _simCurrentPos?.latitude ?? _myLat ?? 39.92077;
                    final lng = _simCurrentPos?.longitude ?? _myLng ?? 32.85411;
                    _yapayZekaOnerisiCek(
                      _lastOneriArama,
                      _lastOneriMesafe,
                      lat,
                      lng,
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    "Tekrar Dene",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              GestureDetector(
                onTap: () => Navigator.pop(ctx, false),
                child: const Text(
                  "Kalsın, teşekkürler",
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (accepted == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );

      LatLng finalDest = _simCurrentPath.last;
      List<LatLng>? routeToStop = await _fetchRoutePointsOnly(
        currentSimLock,
        mekanPos,
      );
      List<LatLng>? routeToFinal = await _fetchRoutePointsOnly(
        mekanPos,
        finalDest,
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (routeToStop != null && routeToFinal != null) {
        rebuild(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: PolylineId('stop_green_$type'),
              points: routeToStop,
              color: Colors.greenAccent,
              width: 6,
            ),
          );
          _polylines.add(
            Polyline(
              polylineId: PolylineId('final_blue_$type'),
              points: routeToFinal,
              color: Colors.blueAccent,
              width: 6,
            ),
          );

          _markers.add(
            Marker(
              markerId: MarkerId('stop_marker_$type'),
              position: mekanPos,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );

          _savedMainRemainingPath = routeToFinal;
          _savedMainRemainingDuration = 60.0 - _activeDrivingTime;
          _simCurrentPath = routeToStop;
          _simSegmentElapsed = 0.0;
          _simSegmentDuration = 10.0;
          _travelingToStop = true;
          _currentTargetName = "⭐ ${data['mekan_adi']}";
        });
      }
    }
    _isSimulating = true;
  }

  void _finishSimulation() {
    rebuild(() {
      _isSimulating = false;
      _haritaKilitli = true;
      // 🚨 ÇÖZÜM: '?' kullanılarak güvenli çağrı yapıldı
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _center, zoom: 12.0, tilt: 0, bearing: 0),
        ),
      );
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Icon(Icons.check_circle, color: Colors.green, size: 70),
        content: const Text(
          "Varış noktasına ulaştınız!",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          Center(
            child: SizedBox(
              width: 150,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  rebuild(() {
                    _haritaKilitli = false;
                    _isSimulationMode = false;
                    _navigasyonPanelAcik = false;
                    _polylines.clear();
                    _markers.removeWhere(
                      (m) => m.markerId.value != 'my_location',
                    );
                    _suankiKonumaGit();
                  });
                },
                child: const Text(
                  "Bitir",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
