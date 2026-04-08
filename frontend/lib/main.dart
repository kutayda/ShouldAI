import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui'; 

void main() {
  runApp(const BitirmeProjesiApp());
}

class BitirmeProjesiApp extends StatelessWidget {
  const BitirmeProjesiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ortak Karar Çöpçatanı',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, 
        fontFamily: 'Roboto',
      ),
      home: const AnaSayfa(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class KullaniciGirdisi {
  TextEditingController adController;
  TextEditingController konumController;
  TextEditingController tercihController;
  bool araciVarMi;

  KullaniciGirdisi(String ad, String konum, String tercih, this.araciVarMi)
      : adController = TextEditingController(text: ad),
        konumController = TextEditingController(text: konum),
        tercihController = TextEditingController(text: tercih);
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  String _mekanAdi = "";
  String _puan = "";
  String _kisaOzet = ""; 
  String _sebep = "";
  bool _yukleniyor = false;

  final Map<String, List<String>> _ankaraKonumlari = {
    'Çankaya': ['7. Cadde (Bahçelievler)', 'Anıttepe', 'Arjantin Caddesi', 'Ayrancı', 'Bahçelievler', 'Balgat', 'Beşevler', 'Bilkent', 'Birlik Mahallesi', 'Cebeci', 'Çayyolu', 'Çukurambar', 'Demirtepe', 'Dikmen Vadisi', 'Emek', 'Filistin Caddesi', 'Gaziosmanpaşa (GOP)', 'Kavaklıdere', 'Kızılay', 'Konutkent', 'Kurtuluş', 'Mutluköy', 'Oran', 'Öveçler', 'Sancak', 'Söğütözü', 'Tunalı Hilmi', 'Tunus Caddesi', 'Ümitköy', 'Yaşamkent', 'Yıldız', '100. Yıl (İşçi Blokları)'],
    'Yenimahalle': ['Batıkent Meydan', 'Demetevler', 'Ostim', 'Şentepe', 'Gazi Mahallesi'],
    'Keçiören': ['Basınevleri', 'Etlik', 'İncirli', 'Aktepe', 'Subayevleri'],
    'Etimesgut': ['Eryaman', 'Elvankent', 'Bağlıca', 'Göksu'],
    'Mamak': ['Kusunlar', 'Abidinpaşa', 'Akdere', 'Boğaziçi', 'Natoyolu'],
    'Altındağ': ['Ulus', 'Siteler', 'Hasköy', 'Hamamönü'],
    'Gölbaşı': ['İncek', 'Mogan', 'Eymir', 'Kızılcaşar'],
    'Pursaklar': ['Merkez', 'Saray'],
    'Sincan': ['Merkez', 'Fatih', 'Yenikent', 'Törekent']
  };

  final List<KullaniciGirdisi> _kullanicilar = [
    KullaniciGirdisi("Ahmet", "Etimesgut / Eryaman", "Suşi", false),
    KullaniciGirdisi("Mehmet", "Çankaya / Çayyolu", "Çıtır Tavuk", true),
    KullaniciGirdisi("Kutay", "Keçiören / Etlik", "Hot Dog", false),
  ];

  Future<void> _mekanOnerisiAl() async {
    setState(() {
      _yukleniyor = true;
      _mekanAdi = "";
      _puan = "";
      _kisaOzet = "";
      _sebep = "";
    });

    try {
      List<Map<String, dynamic>> kullaniciListesi = _kullanicilar.map((k) {
        return {
          "name": k.adController.text,
          "location": k.konumController.text,
          "preference": k.tercihController.text,
          "has_car": k.araciVarMi,
        };
      }).toList();

      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/get_recommendation'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"users": kullaniciListesi}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == 'success') {
          setState(() {
            _mekanAdi = data['mekan_adi'] ?? "";
            _puan = data['puan']?.toString() ?? "";
            _kisaOzet = data['kisa_ozet'] ?? "";
            _sebep = data['sebep'] ?? "Sebep belirtilmedi.";
          });
        } else {
          setState(() {
            _mekanAdi = "Sistem Hatası 🤖";
            _sebep = data['message'] ?? "Bilinmeyen bir hata.";
          });
        }
      } else {
        setState(() => _sebep = "Sunucu Hatası: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _sebep = "Bağlantı hatası: $e");
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  void _sifirla() {
    setState(() {
      _mekanAdi = "";
      _puan = "";
      _kisaOzet = "";
      _sebep = "";
    });
  }

  // YENİ: Çift yıldızları algılayıp kalın yazdıran akıllı fonksiyon
  Widget _buildRichText(String text) {
    final List<TextSpan> spans = [];
    final List<String> parts = text.split('**');

    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        // Çift indeksler normal yazıdır
        spans.add(TextSpan(text: parts[i]));
      } else {
        // Tek indeksler iki yıldız arasında kalan kalın yazıdır
        spans.add(TextSpan(
          text: parts[i], 
          style: const TextStyle(fontWeight: FontWeight.w900) // Kalınlığı iyice artırdık
        ));
      }
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87, fontFamily: 'Roboto'),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 932),
          child: Stack(
            children: [
              Container(
                color: const Color(0xFF262626), 
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 60, bottom: 20),
                      child: const Text(
                        "Ortayı Bul",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: _kullanicilar.length,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF333333), 
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _buildDarkTextField(_kullanicilar[index].adController, "İsim", Icons.person),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: _buildLocationAutoComplete(index),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _buildDarkTextField(_kullanicilar[index].tercihController, "Ne İstiyor?", Icons.fastfood),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _kullanicilar[index].araciVarMi = !_kullanicilar[index].araciVarMi),
                                        child: Container(
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: _kullanicilar[index].araciVarMi ? const Color(0xFF4285F4).withOpacity(0.2) : Colors.black26,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: _kullanicilar[index].araciVarMi ? const Color(0xFF4285F4) : Colors.transparent),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.directions_car, size: 20, color: _kullanicilar[index].araciVarMi ? const Color(0xFF4285F4) : Colors.white54),
                                              const SizedBox(width: 8),
                                              Text("Araç", style: TextStyle(fontWeight: FontWeight.bold, color: _kullanicilar[index].araciVarMi ? const Color(0xFF4285F4) : Colors.white54)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 65,
                        child: ElevatedButton(
                          onPressed: _yukleniyor ? null : _mekanOnerisiAl,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 5,
                          ),
                          child: const Text(
                            "Şaşırt Bizi!",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_yukleniyor)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF4285F4), strokeWidth: 5),
                          SizedBox(height: 30),
                          Text(
                            "Şartlar düşünülerek\nen uygun seçim yapılıyor...",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_mekanAdi.isNotEmpty && !_yukleniyor)
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.only(top: 80),
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                      boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, -10))],
                    ),
                    child: Column(
                      children: [
                        Container(width: 50, height: 6, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10))),
                        const SizedBox(height: 20),
                        // İKON BURADAN KALDIRILDI
                        Expanded(
                          child: SelectionArea(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center, 
                              children: [
                                if (_puan.isNotEmpty && _puan != "-")
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                        const SizedBox(width: 4),
                                        Text(_puan, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                                      ],
                                    ),
                                  ),
                                
                                Text(
                                  _mekanAdi,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87, height: 1.2),
                                ),
                                const SizedBox(height: 12),
                                
                                Text(
                                  _kisaOzet.isNotEmpty ? _kisaOzet : "Sizin için en uygun lokasyon!",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade700, fontStyle: FontStyle.italic),
                                ),
                                
                                const SizedBox(height: 30), 
                                
                                Text(
                                  "Detaylı Analiz",
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 8),
                                
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 20.0),
                                      // BURASI GÜNCELLENDİ: Sadece _sebep yerine _buildRichText fonksiyonunu kullanıyoruz
                                      child: _buildRichText(_sebep),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: OutlinedButton(
                            onPressed: _sifirla,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: const BorderSide(color: Colors.black26, width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text("Yeni Arama Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildLocationAutoComplete(int index) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _kullanicilar[index].konumController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final String inputText = textEditingValue.text;
        if (inputText.isEmpty) return _ankaraKonumlari.keys;

        if (inputText.contains('/')) {
          final parts = inputText.split('/');
          final district = parts[0].trim();
          final searchNeighborhood = parts.length > 1 ? parts[1].trimLeft().toLowerCase() : '';

          if (_ankaraKonumlari.containsKey(district)) {
            final neighborhoods = _ankaraKonumlari[district]!;
            if (searchNeighborhood.isEmpty) {
              return neighborhoods.map((n) => '$district / $n');
            } else {
              return neighborhoods.where((n) => n.toLowerCase().contains(searchNeighborhood)).map((n) => '$district / $n');
            }
          } else {
            return const Iterable<String>.empty();
          }
        } else {
          final searchDistrict = inputText.trimLeft().toLowerCase();
          return _ankaraKonumlari.keys.where((d) => d.toLowerCase().contains(searchDistrict));
        }
      },
      onSelected: (String selection) {
        if (!selection.contains('/')) {
          _kullanicilar[index].konumController.text = '$selection / ';
        } else {
          _kullanicilar[index].konumController.text = selection;
        }
      },
      fieldViewBuilder: (ctx, ctrl, fNode, onComplete) {
        ctrl.addListener(() => _kullanicilar[index].konumController.text = ctrl.text);
        return _buildDarkTextField(ctrl, "Semt", Icons.location_on, focusNode: fNode);
      },
      optionsViewBuilder: (ctx, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 250,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: opts.length,
              itemBuilder: (ctx, i) => ListTile(
                title: Text(opts.elementAt(i), style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)), 
                onTap: () => onSelected(opts.elementAt(i))
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDarkTextField(TextEditingController ctrl, String lbl, IconData icon, {FocusNode? focusNode}) {
    return SizedBox(
      height: 50,
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: lbl,
          hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
          prefixIcon: Icon(icon, size: 20, color: Colors.white54),
          filled: true,
          fillColor: Colors.black26,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}