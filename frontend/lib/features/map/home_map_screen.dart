import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../groups/mutual_choice/mutual_choice_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  late GoogleMapController mapController;
  LatLng _center = const LatLng(39.92077, 32.85411); // Varsayılan: Ankara Kızılay
  double? _myLat;
  double? _myLng;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  BitmapDescriptor _locationIcon = BitmapDescriptor.defaultMarker;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _navigasyonPanelAcik = false;
  String _mesafeText = "0 km";
  String _sureText = "0 dk";
  String _hedefAdresi = "Adres yükleniyor...";
  LatLng? _secilenHedef;
  bool _haritaKilitli = false;

  @override
  void initState() {
    super.initState();
    _baslangicAyarlariniYap();
  }

  Future<void> _baslangicAyarlariniYap() async {
    await _ozelMaviNoktaCiz();
    await _suankiKonumaGit();
  }

  Future<void> _ozelMaviNoktaCiz() async {
    const double size = 60;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const Offset center = Offset(size / 2, size / 2);
    final Paint auraPaint = Paint()..color = Colors.blueAccent.withValues(alpha: 0.15);
    canvas.drawCircle(center, size / 2, auraPaint);
    final Paint borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 12, borderPaint);
    final Paint corePaint = Paint()..color = Colors.blueAccent;
    canvas.drawCircle(center, 8, corePaint);
    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      setState(() {
        _locationIcon = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      });
    }
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
      debugPrint("Konum alınamadı, yedek konum (Kızılay) kullanılıyor.");
      setState(() {
        _myLat = 39.92077;
        _myLng = 32.85411;
        _center = const LatLng(39.92077, 32.85411);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Konum izni alınamadı, varsayılan konum kullanılıyor."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: _center,
          icon: _locationIcon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 10,
        ),
      );
    });
    mapController.animateCamera(CameraUpdate.newLatLngZoom(_center, 14.0));
  }

  // YENİ: Hem rotayı çizen hem de renkleri ayarlayabilen asenkron fonksiyon
  Future<void> _hedefSec(LatLng secilenKonum, {double pinHue = BitmapDescriptor.hueAzure}) async {
    if (_navigasyonPanelAcik || _haritaKilitli) return;

    // Önce eski rotaları ve eski yazıları tamamen temizle ki kafa karışmasın
    setState(() {
      _secilenHedef = secilenKonum;
      _hedefAdresi = "Rota hesaplanıyor...";
      _mesafeText = "..."; 
      _sureText = "...";
      _polylines.clear();
      _markers.removeWhere((m) => m.markerId.value == 'hedef_pin');
      _markers.add(
        Marker(
          markerId: const MarkerId('hedef_pin'),
          position: secilenKonum,
          icon: BitmapDescriptor.defaultMarkerWithHue(pinHue),
        ),
      );
    });

    if (_myLat == null || _myLng == null) {
      setState(() {
        _hedefAdresi = "Konumunuz bilinmediği için rota çizilemiyor.";
        _mesafeText = "-";
        _sureText = "-";
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('http://localhost:8000/api/get_route?origin_lat=$_myLat&origin_lng=$_myLng&dest_lat=${secilenKonum.latitude}&dest_lng=${secilenKonum.longitude}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _mesafeText = data['distance'] ?? "0 km";
          _sureText = data['duration'] ?? "0 dk";
          _hedefAdresi = data['address'] ?? "Adres bulunamadı";
          
          if (data['points'] != null) {
            final List pts = data['points'];
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: pts.map((p) => LatLng(p[0], p[1])).toList(),
                color: Colors.blueAccent,
                width: 6,
              ),
            );
          }
        });
      } else {
         setState(() => _hedefAdresi = "Rota API'ye ulaşılamadı.");
      }
    } catch (e) {
      debugPrint("Rota Hatası: $e");
      setState(() => _hedefAdresi = "Bağlantı sorunu, rota çizilemedi.");
    }
  }

  // --- DETAYLI ARAMA (MOLA VER) ---
  void _detayliAramaDialogAc() {
    setState(() => _haritaKilitli = true);
    TextEditingController kategoriCtrl = TextEditingController();
    double capKm = 5.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Mola Ver", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: kategoriCtrl,
                decoration: InputDecoration(
                  labelText: "Kategori (Otel, Kafe...)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  prefixIcon: const Icon(Icons.category),
                ),
              ),
              const SizedBox(height: 25),
              const Text("Arama Çapı (Kilometre)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              Slider(
                value: capKm,
                min: 1,
                max: 20,
                divisions: 19,
                label: "${capKm.toInt()} km",
                activeColor: Colors.purple,
                onChanged: (val) => setDialogState(() => capKm = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, "iptal"),
              child: const Text("Vazgeç", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () {
                String kat = kategoriCtrl.text;
                Navigator.pop(context, "devam");
                if (kat.isNotEmpty) {
                  _detayliOneriCek(kat, capKm);
                }
              },
              child: const Text("Mekan Bul"),
            ),
          ],
        ),
      ),
    ).then((durum) {
      if (durum != "devam") setState(() => _haritaKilitli = false);
    });
  }

  Future<void> _detayliOneriCek(String kategori, double capKm) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.purple)),
    );

    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/api/category_recommendation'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "category": kategori,
          "radius_km": capKm,
          "current_lat": _myLat ?? 39.92077, 
          "current_lng": _myLng ?? 32.85411, 
        }),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'error') {
          setState(() => _haritaKilitli = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? "Yapay Zeka Hatası!"), backgroundColor: Colors.red)
          );
          return;
        }

        if (data['status'] == 'success') {
          final LatLng mekanPos = LatLng(data['lat'], data['lng']);

          // İŞTE ÇÖZÜMÜN KALBİ BURASI: Haritanın kilidini rotayı çizmeden ÖNCE aç!
          setState(() => _haritaKilitli = false); 

          // Mor pin ile rotayı çizmesini ve mesafe/süre yazılarının güncellenmesini BEKLE (await)
          await _hedefSec(mekanPos, pinHue: BitmapDescriptor.hueViolet);

          // Rota çizildikten sonra InfoWindow eklentisini yap
          setState(() {
            _markers.removeWhere((m) => m.markerId.value == 'hedef_pin');
            _markers.add(
              Marker(
                markerId: const MarkerId('hedef_pin'), 
                position: mekanPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                infoWindow: InfoWindow(title: data['mekan_adi'], snippet: data['sebep']),
              ),
            );
          });
          
          mapController.animateCamera(CameraUpdate.newLatLngZoom(mekanPos, 14.0));
          _oneriSonucunuGoster(data); 
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _haritaKilitli = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sunucu Hatası! Python açık mı?"), backgroundColor: Colors.red));
    }
  }

  // --- HIZLI ÖNERİ ---
  void _tekliOneriDialogAc() {
    setState(() => _haritaKilitli = true);
    TextEditingController tercihCtrl = TextEditingController();
    double dakika = 15;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Hızlı Öneri Al", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tercihCtrl,
                decoration: InputDecoration(
                  labelText: "Ne istersin? (Hamburger, Kebap...)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 20),
              Slider(
                value: dakika,
                min: 5,
                max: 60,
                divisions: 11,
                label: dakika.toInt().toString(),
                onChanged: (val) => setDialogState(() => dakika = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, "iptal"),
              child: const Text("Vazgeç"),
            ),
            ElevatedButton(
              onPressed: () {
                String input = tercihCtrl.text;
                Navigator.pop(context, "devam");
                if (input.isNotEmpty) {
                  _hizliOneriCek(input, dakika.toInt());
                }
              },
              child: const Text("Mekan Bul"),
            ),
          ],
        ),
      ),
    ).then((durum) {
      if (durum != "devam") setState(() => _haritaKilitli = false);
    });
  }

  Future<void> _hizliOneriCek(String tercih, int dakika) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
    );

    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/api/single_recommendation'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "preference": tercih,
          "time_limit_mins": dakika,
          "current_lat": _myLat ?? 39.92077, 
          "current_lng": _myLng ?? 32.85411, 
        }),
      );

      if (!mounted) return;
      Navigator.pop(context); 

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['status'] == 'error') {
          setState(() => _haritaKilitli = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "Hata"), backgroundColor: Colors.red));
          return;
        }

        if (data['status'] == 'success') {
          final LatLng mekanPos = LatLng(data['lat'], data['lng']);

          // KİLİDİ AÇIYORUZ
          setState(() => _haritaKilitli = false); 

          // Kırmızı pin ile rotayı çizmesini ve verileri almasını bekle
          await _hedefSec(mekanPos, pinHue: BitmapDescriptor.hueRed);

          setState(() {
            _markers.removeWhere((m) => m.markerId.value == 'hedef_pin');
            _markers.add(
              Marker(
                markerId: const MarkerId('hedef_pin'),
                position: mekanPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: InfoWindow(title: data['mekan_adi'], snippet: data['sebep']),
              ),
            );
          });
          
          mapController.animateCamera(CameraUpdate.newLatLngZoom(mekanPos, 14.0));
          _oneriSonucunuGoster(data); 
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _haritaKilitli = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sunucu Hatası! Python açık mı?"), backgroundColor: Colors.red));
    }
  }

  void _oneriSonucunuGoster(Map data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data['mekan_adi'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(data['sebep'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); 
                setState(() {
                  _navigasyonPanelAcik = true; 
                });
              },
              child: const Text("Navigasyona Geç"),
            ),
          ],
        ),
      ),
    ).then((_) => setState(() => _haritaKilitli = false));
  }

  Widget _kalkanTasarimi({required Widget child}) {
    return PointerInterceptor(
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double topPadding = MediaQuery.of(context).padding.top;
    double bottomPadding = MediaQuery.of(context).padding.bottom;
    
    bool kalkanAktif = _haritaKilitli || _secilenHedef != null || _navigasyonPanelAcik;

    return SelectionArea(
      selectionControls: EmptyTextSelectionControls(),
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const Drawer(child: Center(child: Text("ShouldAI Menü"))),
        body: Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(target: _center, zoom: 12.0),
              markers: _markers,
              polylines: _polylines,
              onTap: (pos) => _hedefSec(pos), // Elle tıklamalarda standart Mavi Pin atar
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),

            if (kalkanAktif)
              Positioned.fill(
                child: _kalkanTasarimi(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!_navigasyonPanelAcik) {
                        setState(() {
                          _secilenHedef = null;
                          _polylines.clear();
                          _markers.removeWhere((m) => m.markerId.value == 'hedef_pin');
                          _haritaKilitli = false;
                        });
                      }
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),

            // ÜST ARAMA BARI 
            Positioned(
              top: topPadding > 0 ? topPadding + 10 : 50,
              left: 20,
              right: 20,
              child: _kalkanTasarimi(
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        elevation: 5, 
                        shadowColor: Colors.black26,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Arama sayfası yakında eklenecek!"), backgroundColor: Colors.blueGrey, duration: Duration(seconds: 1)),
                            );
                          },
                          child: Container(
                            height: 55,
                            padding: const EdgeInsets.only(right: 15),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.menu),
                                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                                ),
                                const Expanded(
                                  child: Text("Nereye gidiyoruz?", style: TextStyle(color: Colors.grey, fontSize: 16)),
                                ),
                                const Icon(Icons.search, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Material(
                      shape: const CircleBorder(),
                      elevation: 5,
                      color: Colors.blueAccent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Profil sayfası yapım aşamasında!"), backgroundColor: Colors.blueAccent, duration: Duration(seconds: 1)),
                          );
                        },
                        child: const SizedBox(
                          width: 54,
                          height: 54,
                          child: Icon(Icons.person, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // SEÇİLEN YER BİLGİ KUTUSU 
            if (_secilenHedef != null && !_navigasyonPanelAcik)
              Positioned(
                bottom: 220 + bottomPadding,
                left: 20,
                right: 20,
                child: _kalkanTasarimi(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 25)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _hedefAdresi,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Mesafe: $_mesafeText | Süre: $_sureText",
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () => setState(() => _navigasyonPanelAcik = true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              elevation: 5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.navigation_rounded),
                            label: const Text("GİT", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // NAVİGASYON PANELİ 
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
                    borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
                    boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 40)],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 35),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _navInfoCol("KALAN SÜRE", _sureText, Colors.greenAccent),
                          _navInfoCol("TOPLAM MESAFE", _mesafeText, Colors.white),
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
                              _polylines.clear();
                              _secilenHedef = null;
                            }),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent, width: 2),
                              foregroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: const Text("NAVİGASYONU BİTİR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // SAĞ ALT AKSİYON BUTONLARI 
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastOutSlowIn,
              bottom: _navigasyonPanelAcik ? (screenHeight * 0.33 + 25 + bottomPadding) : (35 + bottomPadding),
              right: 20,
              child: _kalkanTasarimi(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: "f3",
                      onPressed: _detayliAramaDialogAc,
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      label: const Text("Mola Ver", style: TextStyle(fontWeight: FontWeight.bold)), 
                      icon: const Icon(Icons.manage_search),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: "f1",
                      onPressed: _tekliOneriDialogAc,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blueAccent,
                      label: const Text("Öneri Al", style: TextStyle(fontWeight: FontWeight.bold)),
                      icon: const Icon(Icons.explore),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: "f2",
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => MutualChoiceScreen(currentLat: _myLat, currentLng: _myLng),
                        ),
                      ),
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      label: const Text("Ekibi Topla", style: TextStyle(fontWeight: FontWeight.bold)),
                      icon: const Icon(Icons.auto_awesome, color: Colors.amber),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navInfoCol(String label, String value, Color valColor) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        ),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(color: valColor, fontSize: 36, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class EmptyTextSelectionControls extends MaterialTextSelectionControls {
  @override
  Widget buildHandle(BuildContext context, TextSelectionHandleType type, double textLineHeight, [VoidCallback? onTap]) {
    return const SizedBox.shrink();
  }
  @override
  Widget buildToolbar(BuildContext context, Rect globalEditableRegion, double textLineHeight, Offset selectionMidpoint, List<TextSelectionPoint> endpoints, TextSelectionDelegate delegate, ValueListenable<ClipboardStatus>? clipboardStatus, Offset? lastSecondaryTapDownPosition) {
    return const SizedBox.shrink();
  }
}