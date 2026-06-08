import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../groups/mutual_choice/mutual_choice_screen.dart';
import 'widgets/smart_search_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../groups/group_panel.dart';
import '../groups/group_service.dart';
import '../groups/chat_service.dart';
import 'nav_utils.dart';
import 'map_icons.dart';
import 'widgets/app_drawer.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  // 🚨 ÇÖZÜM: 'late' kaldırıldı, Nullable yapıldı. Böylece yarış durumu (race condition) engellendi.
  GoogleMapController? mapController;

  LatLng _center = const LatLng(39.92077, 32.85411);
  double? _myLat;
  double? _myLng;

  final String baseUrl = "http://localhost:8000";

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  BitmapDescriptor _locationIcon = BitmapDescriptor.defaultMarker;
  BitmapDescriptor _navArrowIcon = BitmapDescriptor.defaultMarker;
  // Her yön (6°'lik kovalar) için döndürülmüş ok ikonu önbelleği
  final Map<int, BitmapDescriptor> _arrowCache = {};
  String? _currentGroupId;

  // Kullanıcı profil tercihleri (onboarding'den)
  List<String> _likedCuisines = [];
  List<String> _dislikedCuisines = [];

  // Öneri Al panelinde seçili kategori + benzinlik marka hafızası
  String _oneriKategori = 'kafe';
  String _benzinlikMarkasi = '';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _navigasyonPanelAcik = false;
  String _mesafeText = "0 km";
  String _sureText = "0 dk";
  String _hedefAdresi = "Adres yükleniyor...";
  LatLng? _secilenHedef;
  bool _haritaKilitli = false;

  final List<double> _radiusValues = [2.0, 5.0, 10.0, 15.0, 20.0, 50.0];
  final List<String> _radiusLabels = [
    "2 km",
    "5 km",
    "10 km",
    "15 km",
    "20 km",
    "∞",
  ];

  bool _isSimulationMode = false;
  bool _isSimulating = false;
  Timer? _simTimer;
  double _activeDrivingTime = 0.0;
  double _simSegmentElapsed = 0.0;
  double _simSegmentDuration = 60.0;
  double _savedMainRemainingDuration = 0.0;
  double _currentBearing = 0.0;
  double _totalRouteDistanceKm = 0.0;

  List<LatLng> _simCurrentPath = [];
  LatLng? _simCurrentPos;
  bool _simCafePrompted = false;
  bool _simRestPrompted = false;

  String _currentTargetName = "";
  bool _travelingToStop = false;
  List<LatLng> _savedMainRemainingPath = [];

  Map<String, dynamic>? _prefetchedCafe;
  Map<String, dynamic>? _prefetchedRest;

  @override
  void initState() {
    super.initState();
    _baslangicAyarlariniYap();
    _refreshCurrentGroup();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _baslangicAyarlariniYap() async {
    await _ozelMaviNoktaCiz();
    await _navigasyonOkuCiz();
    await _suankiKonumaGit();
    _profilTercihleriniYukle();
  }

  void _profilTercihleriniYukle() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('liked_cuisines, disliked_cuisines')
          .eq('id', uid)
          .single();
      if (mounted) {
        setState(() {
          _likedCuisines = List<String>.from(row['liked_cuisines'] ?? []);
          _dislikedCuisines = List<String>.from(row['disliked_cuisines'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _ozelMaviNoktaCiz() async {
    final icon = await buildBlueDot();
    if (mounted) {
      setState(() {
        _locationIcon = icon;
      });
    }
  }

  // Başlangıç (kuzeye bakan) ok ikonunu hazırlar ve önbelleğe alır.
  Future<void> _navigasyonOkuCiz() async {
    final icon = await buildRotatedArrow(0);
    _arrowCache[0] = icon;
    if (mounted) {
      setState(() {
        _navArrowIcon = icon;
      });
    }
  }

  // Verilen yöne en yakın 6°'lik ok ikonunu seçer. Önbellekte varsa anında kullanır,
  // yoksa üretip önbelleğe alır (bir sonraki karede devreye girer).
  void _ensureArrowForBearing(double bearing) {
    int bucket = ((bearing / 6).round() * 6) % 360;
    if (bucket < 0) bucket += 360;

    final cached = _arrowCache[bucket];
    if (cached != null) {
      _navArrowIcon = cached;
      return;
    }
    buildRotatedArrow(bucket.toDouble()).then((icon) {
      _arrowCache[bucket] = icon;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  Future<void> _suankiKonumaGit() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      setState(() {
        _myLat = position.latitude;
        _myLng = position.longitude;
        _center = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      setState(() {
        _myLat = 39.92077;
        _myLng = 32.85411;
        _center = const LatLng(39.92077, 32.85411);
      });
    }

    _guncelleMarker(_center, _locationIcon, 0.0);
    // 🚨 ÇÖZÜM: '?' kullanılarak güvenli çağrı yapıldı
    mapController?.animateCamera(CameraUpdate.newLatLngZoom(_center, 14.0));
  }

  void _guncelleMarker(LatLng pos, BitmapDescriptor icon, double bearing) {
    setState(() {
      _markers.removeWhere(
        (m) =>
            m.markerId.value == 'my_location' || m.markerId.value == 'sim_car',
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('sim_car'),
          position: pos,
          icon: icon,
          // Ok ikonu zaten gidiş yönüne döndürülmüş olarak çiziliyor
          // (_buildRotatedArrow). marker.rotation web'de bitmap'lerde çalışmaz,
          // bu yüzden 0 bırakıyoruz; billboard ikon açısını olduğu gibi gösterir.
          rotation: 0.0,
          anchor: const Offset(0.5, 0.5),
          flat: false,
          zIndexInt: 20,
        ),
      );
    });
  }

  Future<List<LatLng>?> _fetchRoutePointsOnly(LatLng start, LatLng end) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/api/get_route?origin_lat=${start.latitude}&origin_lng=${start.longitude}&dest_lat=${end.latitude}&dest_lng=${end.longitude}',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['points'] != null) {
          final List pts = data['points'];
          return pts
              .map(
                (p) => LatLng(
                  double.parse(p[0].toString()),
                  double.parse(p[1].toString()),
                ),
              )
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Rota çekim hatası: $e");
    }
    return null;
  }

  Future<void> _hedefSec(
    LatLng secilenKonum, {
    double pinHue = BitmapDescriptor.hueAzure,
    String? customTitle,
    bool showPanel = true,
  }) async {
    if (_navigasyonPanelAcik || _haritaKilitli || _isSimulating) return;

    setState(() {
      _secilenHedef = showPanel ? secilenKonum : null;
      _hedefAdresi = customTitle ?? "Rota ve adres hesaplanıyor...";
      _mesafeText = "...";
      _sureText = "...";
      _polylines.clear();
      _simCurrentPath.clear();
      _totalRouteDistanceKm = 0.0;
      _markers.removeWhere((m) => m.markerId.value == 'hedef_pin');
      _markers.add(
        Marker(
          markerId: const MarkerId('hedef_pin'),
          position: secilenKonum,
          icon: BitmapDescriptor.defaultMarkerWithHue(pinHue),
        ),
      );
    });

    if (_myLat == null || _myLng == null) return;

    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/api/get_route?origin_lat=$_myLat&origin_lng=$_myLng&dest_lat=${secilenKonum.latitude}&dest_lng=${secilenKonum.longitude}',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _mesafeText = data['distance'] ?? "0 km";
          _sureText = data['duration'] ?? "0 dk";

          _currentTargetName =
              customTitle ?? data['address'] ?? "Seçilen Konum";
          if (customTitle == null)
            _hedefAdresi = data['address'] ?? "Adres bulunamadı";

          if (data['points'] != null) {
            final List pts = data['points'];
            _simCurrentPath = pts
                .map(
                  (p) => LatLng(
                    double.parse(p[0].toString()),
                    double.parse(p[1].toString()),
                  ),
                )
                .toList();

            double totalDist = 0;
            for (int i = 0; i < _simCurrentPath.length - 1; i++) {
              totalDist += Geolocator.distanceBetween(
                _simCurrentPath[i].latitude,
                _simCurrentPath[i].longitude,
                _simCurrentPath[i + 1].latitude,
                _simCurrentPath[i + 1].longitude,
              );
            }
            _totalRouteDistanceKm = totalDist / 1000.0;

            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: _simCurrentPath,
                color: Colors.blueAccent,
                width: 6,
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Rota Bağlantı Hatası: $e");
    }
  }

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

      setState(() {
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

    setState(() {
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
    setState(() {
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
                type == "Kafe" ? Icons.local_cafe : Icons.restaurant,
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
        setState(() {
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
    setState(() {
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
                  setState(() {
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

  void _modernOneriPaneliniAc() {
    setState(() => _haritaKilitli = true);
    String localKategori = _oneriKategori;
    TextEditingController tercihCtrl = TextEditingController(
      text: _oneriKategori == 'benzinlik' ? _benzinlikMarkasi : '',
    );
    double localSliderIndex = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      barrierColor: Colors.black.withValues(alpha: 0.78),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) => PointerInterceptor(
        child: StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              top: 20,
              left: 25,
              right: 25,
              bottom: MediaQuery.of(context).viewInsets.bottom + 30,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                const Text(
                  "Yapay Zeka Önerisi",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "Canlı Google harita verileriyle en iyi konumu bulalım.",
                  style: TextStyle(fontSize: 14, color: Colors.white60),
                ),
                const SizedBox(height: 20),

                // Kategori seçici — Kafe / Restoran / Benzinlik
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: ['kafe', 'restoran', 'benzinlik'].map((k) {
                        final isSelected = localKategori == k;
                        return GestureDetector(
                          onTap: () {
                            if (localKategori == 'benzinlik') {
                              setState(
                                () => _benzinlikMarkasi = tercihCtrl.text,
                              );
                            }
                            if (k == 'benzinlik') {
                              tercihCtrl.text = _benzinlikMarkasi;
                            } else {
                              tercihCtrl.clear();
                            }
                            setState(() => _oneriKategori = k);
                            setSheetState(() => localKategori = k);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blueAccent
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Text(
                              {
                                'kafe': 'Kafe',
                                'restoran': 'Restoran',
                                'benzinlik': 'Benzinlik',
                              }[k]!,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: tercihCtrl,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    labelText: localKategori == 'kafe'
                        ? 'Marka veya içecek türü (ör. Starbucks, çay)'
                        : localKategori == 'restoran'
                        ? 'Yemek türü veya mutfak (ör. tavuk, Türk)'
                        : 'Marka tercihi (ör. Shell, BP, Opet)',
                    labelStyle: const TextStyle(color: Colors.blueAccent),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.blueAccent,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: Colors.blueAccent,
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Mesafe Sınırı",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _radiusLabels[localSliderIndex.toInt()],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: Colors.blueAccent,
                    inactiveTrackColor: Colors.grey[200],
                    thumbColor: Colors.blueAccent,
                  ),
                  child: Slider(
                    value: localSliderIndex,
                    min: 0,
                    max: 5,
                    divisions: 5,
                    label: _radiusLabels[localSliderIndex.toInt()],
                    onChanged: (val) =>
                        setSheetState(() => localSliderIndex = val),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Material Slider'da track, overlay yarıçapı (24) kadar içeriden başlar
                    const double inset = 24.0;
                    final double trackW = constraints.maxWidth - 2 * inset;
                    final int count = _radiusLabels.length;
                    return SizedBox(
                      height: 20,
                      child: Stack(
                        children: List.generate(count, (i) {
                          final double cx = inset + (i / (count - 1)) * trackW;
                          return Positioned(
                            left: cx - 18,
                            width: 36,
                            child: Center(
                              child: Text(
                                _radiusLabels[i].replaceAll(" km", ""),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: i == localSliderIndex.toInt()
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: i == localSliderIndex.toInt()
                                      ? Colors.blueAccent
                                      : Colors.grey[400],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 35),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 3,
                    ),
                    onPressed: () {
                      String input = tercihCtrl.text;
                      // Benzinlik markasını hafızada tut
                      if (localKategori == 'benzinlik') {
                        setState(() => _benzinlikMarkasi = input);
                      }
                      // Aramayı oluştur: kategori + kullanıcı detayı
                      final aramaMetni = localKategori == 'kafe'
                          ? (input.isNotEmpty ? input : 'kafe')
                          : localKategori == 'benzinlik'
                          ? (input.isNotEmpty
                                ? '$input benzinlik'
                                : 'benzinlik')
                          : (input.isNotEmpty ? '$input restoran' : 'restoran');
                      double secilenMesafe =
                          _radiusValues[localSliderIndex.toInt()];
                      Navigator.pop(context);
                      double rLat = (_isSimulating && _simCurrentPos != null)
                          ? _simCurrentPos!.latitude
                          : (_myLat ?? 39.92077);
                      double rLng = (_isSimulating && _simCurrentPos != null)
                          ? _simCurrentPos!.longitude
                          : (_myLng ?? 32.85411);
                      _yapayZekaOnerisiCek(
                        aramaMetni,
                        secilenMesafe,
                        rLat,
                        rLng,
                      );
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 20),
                        SizedBox(width: 10),
                        Text(
                          "Beni Oraya Götür",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
      ),
    ).then((_) => setState(() => _haritaKilitli = false));
  }

  Future<void> _yapayZekaOnerisiCek(
    String tercih,
    double mesafeKm,
    double lat,
    double lng,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      ),
    );
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/single_recommendation'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "preference": tercih,
              "radius_km": mesafeKm,
              "current_lat": lat,
              "current_lng": lng,
              "liked_cuisines": _likedCuisines,
              "disliked_cuisines": _dislikedCuisines,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == 'error') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? "Sunucu veya AI Hatası"),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (data['status'] == 'success') {
          // Simülasyon sırasında: mekanı yeni DURAK olarak ekle (rota üzerinden geçir).
          if (_isSimulating) {
            final type = _oneriKategori == 'kafe'
                ? "Kafe"
                : _oneriKategori == 'benzinlik'
                ? "Benzinlik"
                : "Restoran";
            await _triggerInstantPrompt(
              type,
              "Aramanıza göre yol üstünde şu mekanı buldum:",
              Map<String, dynamic>.from(data),
            );
            return;
          }
          final LatLng mekanPos = LatLng(
            double.parse(data['lat'].toString()),
            double.parse(data['lng'].toString()),
          );
          String ozelBaslik = "⭐ ${data['puan']} - ${data['mekan_adi']}";

          await _hedefSec(
            mekanPos,
            pinHue: BitmapDescriptor.hueRed,
            customTitle: ozelBaslik,
            showPanel: false,
          );
          _oneriSonucunuGoster(data);
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _oneriSonucunuGoster(Map data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) => PointerInterceptor(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
                  const SizedBox(width: 4),
                  Text(
                    "${data['puan']} / 5.0 Google Puanı",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data['mekan_adi'],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              if (data['image_url'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(
                    data['image_url'],
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                data['sebep'],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _navigasyonPanelAcik = true;
                    });
                  },
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text(
                    "Navigasyona Geç",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => setState(() => _haritaKilitli = false));
  }

  Widget _kalkanTasarimi({required Widget child}) {
    return PointerInterceptor(child: child);
  }

  // Drawer'da gösterilecek kullanıcı adı (görünen ad; yoksa e-postanın @ öncesi)
  String get _displayName {
    final user = Supabase.instance.client.auth.currentUser;
    final meta = (user?.userMetadata?['display_name'] as String?)?.trim();
    if (meta != null && meta.isNotEmpty) return meta;
    return user?.email?.split('@').first ?? "Kullanıcı";
  }

  // Rota geometrisinden bir sonraki dönüş yönergesini hesaplar (formalite navigasyon)
  String _getNavInstruction() {
    if (_simCurrentPath.length < 3 || _simCurrentPos == null) {
      return "Rotanızda düz devam edin";
    }
    // En yakın rota noktasını bul
    int nearestIdx = 0;
    double minD = double.infinity;
    for (int i = 0; i < _simCurrentPath.length; i++) {
      final d = Geolocator.distanceBetween(
        _simCurrentPos!.latitude,
        _simCurrentPos!.longitude,
        _simCurrentPath[i].latitude,
        _simCurrentPath[i].longitude,
      );
      if (d < minD) {
        minD = d;
        nearestIdx = i;
      }
    }
    // İlerideki ilk anlamlı dönüşü ara (>25° açı değişimi)
    for (int i = nearestIdx; i < _simCurrentPath.length - 2; i++) {
      final b1 = calculateExactBearing(
        _simCurrentPath[i],
        _simCurrentPath[i + 1],
      );
      final b2 = calculateExactBearing(
        _simCurrentPath[i + 1],
        _simCurrentPath[i + 2],
      );
      final diff = ((b2 - b1) + 360) % 360;
      final absDiff = diff > 180 ? 360 - diff : diff;
      if (absDiff > 25) {
        final distM = Geolocator.distanceBetween(
          _simCurrentPos!.latitude,
          _simCurrentPos!.longitude,
          _simCurrentPath[i + 1].latitude,
          _simCurrentPath[i + 1].longitude,
        );
        final yon = diff <= 180 ? "sağa" : "sola";
        final distStr = distM < 1000
            ? "${distM.round()} m sonra"
            : "${(distM / 1000).toStringAsFixed(1)} km sonra";
        return "$distStr $yon dönün";
      }
    }
    return "Rotanızda düz devam edin";
  }

  // Sağ alttaki yuvarlak grup butonundan grup panelini açar (ekran ortasında)
  void _grupPaneliniAc() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => PointerInterceptor(
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: GroupPanel(
            onGatherTeam: _ekibiTopla,
            onPickPlaceForShare: () {
              _snack("Haritadan bir yer seç, sonra 'Sohbete Paylaş'a bas.");
            },
            onShowPlaceOnMap: _haritadaGoster,
            currentLat: _myLat,
            currentLng: _myLng,
          ),
        ),
      ),
    ).then((_) => _refreshCurrentGroup());
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  // Giriş yapan kullanıcının güncel grubunu takip eder (sohbete paylaşım için)
  Future<void> _refreshCurrentGroup() async {
    try {
      final gs = await GroupService.myGroups();
      if (mounted) {
        setState(
          () => _currentGroupId = gs.isNotEmpty
              ? gs.first['id'].toString()
              : null,
        );
      }
    } catch (_) {}
  }

  // Sohbetteki bir yer/konum mesajını haritada işaretler
  Future<void> _haritadaGoster(double lat, double lng, String name) async {
    if (!mounted) return;
    setState(() {
      _navigasyonPanelAcik = false;
      _haritaKilitli = false;
      _isSimulating = false;
    });
    final hedef = LatLng(lat, lng);
    await _hedefSec(hedef, customTitle: name);
    mapController?.animateCamera(CameraUpdate.newLatLngZoom(hedef, 15.0));
  }

  // Seçili mekanı grup sohbetine gönderir
  Future<void> _sohbetePaylas() async {
    if (_currentGroupId == null || _secilenHedef == null) return;
    try {
      await ChatService.sendPlace(
        _currentGroupId!,
        _hedefAdresi,
        _secilenHedef!.latitude,
        _secilenHedef!.longitude,
      );
      _snack("Mekan grup sohbetine gönderildi.");
    } catch (e) {
      _snack("Gönderilemedi: $e");
    }
  }

  // "Ekibi Topla": gruptan canlı beslenen ekranı açar, dönen sonucu işaretler
  Future<void> _ekibiTopla(String groupId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => MutualChoiceScreen(
          groupId: groupId,
          currentLat: _myLat,
          currentLng: _myLng,
        ),
      ),
    );
    if (!mounted) return;
    if (result is Map && result['lat'] != null && result['lng'] != null) {
      setState(() {
        _navigasyonPanelAcik = false;
        _haritaKilitli = false;
        _isSimulating = false;
      });
      final double lat = (result['lat'] as num).toDouble();
      final double lng = (result['lng'] as num).toDouble();
      final String name = result['name']?.toString() ?? "Seçilen Mekan";
      final LatLng hedef = LatLng(lat, lng);
      await _hedefSec(hedef, customTitle: name);
      mapController?.animateCamera(CameraUpdate.newLatLngZoom(hedef, 15.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double topPadding = MediaQuery.of(context).padding.top;
    double bottomPadding = MediaQuery.of(context).padding.bottom;
    bool kalkanAktif =
        _haritaKilitli || _secilenHedef != null || _navigasyonPanelAcik;

    return SelectionArea(
      selectionControls: EmptyTextSelectionControls(),
      child: Scaffold(
        key: _scaffoldKey,
        drawer: AppDrawer(
          displayName: _displayName,
          onSignOut: () => Supabase.instance.client.auth.signOut(),
        ),
        body: Container(
          decoration: _isSimulationMode
              ? BoxDecoration(
                  border: Border.all(width: 6, color: Colors.transparent),
                )
              : null,
          child: Container(
            decoration: _isSimulationMode
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black,
                        Colors.black,
                        Colors.yellowAccent,
                        Colors.yellowAccent,
                      ],
                      stops: [0.0, 0.5, 0.5, 1.0],
                      begin: Alignment.topLeft,
                      end: Alignment(0.05, 0.05),
                      tileMode: TileMode.repeated,
                    ),
                  )
                : null,
            padding: EdgeInsets.all(_isSimulationMode ? 6.0 : 0.0),
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _center,
                    zoom: 12.0,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  onTap: (pos) => _hedefSec(pos),
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  // Web'de "ctrl+scroll ile yakınlaştır" ibaresini kaldırır;
                  // tüm tıklama/scroll doğrudan haritaya gider.
                  webGestureHandling: WebGestureHandling.greedy,
                ),

                if (kalkanAktif && !_isSimulating)
                  Positioned.fill(
                    child: _kalkanTasarimi(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!_navigasyonPanelAcik) {
                            setState(() {
                              _secilenHedef = null;
                              _polylines.clear();
                              _markers.removeWhere(
                                (m) => m.markerId.value == 'hedef_pin',
                              );
                            });
                          }
                        },
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),

                // Simülasyon sırasında üstte varış noktası kutusu
                // Simülasyon sırasında yıldız butonu nav panelinin sağ üzerinde
                if (_isSimulating && _navigasyonPanelAcik)
                  Positioned(
                    bottom: screenHeight * 0.36,
                    right: 20,
                    child: _kalkanTasarimi(
                      child: FloatingActionButton(
                        heroTag: "f1_sim",
                        onPressed: _modernOneriPaneliniAc,
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                        child: const Icon(Icons.auto_awesome, size: 26),
                      ),
                    ),
                  ),

                if (!_isSimulating)
                  Positioned(
                    top: topPadding > 0 ? topPadding + 10 : 50,
                    left: 20,
                    right: 20,
                    child: _kalkanTasarimi(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SmartSearchBar(
                              controller: _searchCtrl,
                              baseUrl: baseUrl,
                              originLat: _myLat ?? _center.latitude,
                              originLng: _myLng ?? _center.longitude,
                              onMenuPressed: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              onPlaceSelected: (lat, lng, name) {
                                _hedefSec(LatLng(lat, lng), customTitle: name);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            shape: const CircleBorder(),
                            elevation: 5,
                            color: Colors.blueAccent,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                setState(() {
                                  _isSimulationMode = !_isSimulationMode;
                                  if (_isSimulationMode) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Simülasyon Modu Aktif! Rotanızı seçip Başlatın.",
                                        ),
                                        backgroundColor: Colors.black87,
                                      ),
                                    );
                                  } else {
                                    _isSimulating = false;
                                    _simTimer?.cancel();
                                  }
                                });
                              },
                              child: SizedBox(
                                width: 54,
                                height: 54,
                                child: Icon(
                                  _isSimulationMode
                                      ? Icons.bug_report
                                      : Icons.bug_report_outlined,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_navigasyonPanelAcik && _currentTargetName.isNotEmpty)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _kalkanTasarimi(
                      child: Container(
                        padding: EdgeInsets.only(
                          top: topPadding + 20,
                          bottom: 25,
                          left: 24,
                          right: 24,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(30),
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 20),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "VARILACAK KONUM",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  _travelingToStop
                                      ? Icons.place_rounded
                                      : Icons.flag_circle_rounded,
                                  color: _travelingToStop
                                      ? Colors.green
                                      : Colors.blueAccent,
                                  size: 30,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _currentTargetName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black87,
                                      fontSize: 18,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                            // Simülasyon sırasında dönüş yönergesi (formalite navigasyon)
                            if (_isSimulating) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.turn_right_rounded,
                                      color: Colors.blueAccent,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _getNavInstruction(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                if (_secilenHedef != null &&
                    !_navigasyonPanelAcik &&
                    !_isSimulating)
                  Positioned(
                    bottom: 150 + bottomPadding,
                    left: 20,
                    right: 20,
                    child: _kalkanTasarimi(
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 25),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _hedefAdresi,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Mesafe: $_mesafeText | Süre: $_sureText",
                              style: TextStyle(
                                color: Colors.blueGrey.shade400,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 52,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        if (_isSimulationMode) {
                                          _startSimulation();
                                        } else {
                                          setState(
                                            () => _navigasyonPanelAcik = true,
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                        elevation: 5,
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      icon: Icon(
                                        _isSimulationMode
                                            ? Icons.play_arrow_rounded
                                            : Icons.navigation_rounded,
                                      ),
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _isSimulationMode
                                              ? "SİMÜLASYONU BAŞLAT"
                                              : "GİT",
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Bir gruptaysan: seçili mekanı sohbete paylaş
                                  if (_currentGroupId != null) ...[
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: _sohbetePaylas,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF2E7D32,
                                          ),
                                          foregroundColor: Colors.white,
                                          elevation: 5,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                        child: const Icon(Icons.share_location),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                AnimatedPositioned(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.fastOutSlowIn,
                  bottom: _navigasyonPanelAcik ? 0 : -screenHeight * 0.35,
                  left: 0,
                  right: 0,
                  child: _kalkanTasarimi(
                    child: Container(
                      height: screenHeight * 0.33 + bottomPadding,
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      decoration: const BoxDecoration(
                        color: Color(0xFF141414),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(35),
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black87, blurRadius: 40),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 35),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _navInfoCol(
                                "KALAN SÜRE",
                                _sureText,
                                Colors.greenAccent,
                              ),
                              _navInfoCol(
                                "TOPLAM MESAFE",
                                _mesafeText,
                                Colors.white,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(28.0),
                            child: SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: OutlinedButton(
                                onPressed: () => setState(() {
                                  _navigasyonPanelAcik = false;
                                  _isSimulating = false;
                                  _simTimer?.cancel();
                                  _polylines.clear();
                                  _secilenHedef = null;
                                  mapController?.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: _center,
                                        zoom: 12.0,
                                        tilt: 0,
                                        bearing: 0,
                                      ),
                                    ),
                                  );
                                  _suankiKonumaGit();
                                }),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Colors.redAccent,
                                    width: 2,
                                  ),
                                  foregroundColor: Colors.redAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: const Text(
                                  "NAVİGASYONU BİTİR",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (!_isSimulating)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.fastOutSlowIn,
                    bottom: _navigasyonPanelAcik
                        ? (screenHeight * 0.33 + 25 + bottomPadding)
                        : (35 + bottomPadding),
                    right: 20,
                    child: _kalkanTasarimi(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FloatingActionButton(
                            heroTag: "f1",
                            onPressed: _modernOneriPaneliniAc,
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            child: const Icon(Icons.auto_awesome, size: 28),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: FloatingActionButton(
                              heroTag: "f2",
                              onPressed: _grupPaneliniAc,
                              backgroundColor: const Color(0xFF3A3A3A),
                              foregroundColor: const Color(0xFFCFCFCF),
                              shape: const CircleBorder(),
                              child: const Icon(Icons.groups, size: 28),
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
      ),
    );
  }

  Widget _navInfoCol(String label, String value, Color valColor) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            color: valColor,
            fontSize: 36,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class EmptyTextSelectionControls extends MaterialTextSelectionControls {
  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    return const SizedBox.shrink();
  }

  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    return const SizedBox.shrink();
  }
}
