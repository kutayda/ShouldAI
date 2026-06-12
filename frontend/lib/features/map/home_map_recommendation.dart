part of 'home_map_screen.dart';

extension _HMRecommendation on _HomeMapScreenState {
  void _modernOneriPaneliniAc() {
    rebuild(() => _haritaKilitli = true);
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
                              _benzinlikMarkasiniKaydet(tercihCtrl.text);
                            }
                            if (k == 'benzinlik') {
                              tercihCtrl.text = _benzinlikMarkasi;
                            } else {
                              tercihCtrl.clear();
                            }
                            rebuild(() => _oneriKategori = k);
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
                      // Benzinlik markasını kalıcı kaydet (DB)
                      if (localKategori == 'benzinlik') {
                        _benzinlikMarkasiniKaydet(input);
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
    ).then((_) => rebuild(() => _haritaKilitli = false));
  }

  Future<void> _yapayZekaOnerisiCek(
    String tercih,
    double mesafeKm,
    double lat,
    double lng,
  ) async {
    // Drawer'dan değiştirilmiş olabilecek en güncel tercihleri yükle (bayatlamayı önler)
    await _profilTercihleriniYukle();

    // Yeni bir arama sorgusuysa exclude listesini sıfırla; aynıysa biriktirmeye devam et
    if (tercih != _lastOneriArama) {
      _oneriExcluded.clear();
      _lastOneriArama = tercih;
    }
    _lastOneriMesafe = mesafeKm;

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
              "mode": _recommendationMode,
              "exclude": _oneriExcluded,
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
          // Önerilen mekanı exclude listesine ekle (Tekrar Dene farklı sonuç versin)
          final ad = data['mekan_adi']?.toString() ?? '';
          if (ad.isNotEmpty && !_oneriExcluded.contains(ad)) {
            _oneriExcluded.add(ad);
          }
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
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () {
                    Navigator.pop(context);
                    rebuild(() {
                      _secilenHedef = null;
                      _polylines.clear();
                      _markers.removeWhere(
                        (m) => m.markerId.value == 'hedef_pin',
                      );
                    });
                  },
                ),
              ),
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
              if ((data['fallback_note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  data['fallback_note'].toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white54,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ],
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
                    rebuild(() {
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
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    final lat = _myLat ?? 39.92077;
                    final lng = _myLng ?? 32.85411;
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
            ],
          ),
        ),
      ),
    ).then((_) => rebuild(() => _haritaKilitli = false));
  }
}
