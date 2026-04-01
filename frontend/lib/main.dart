import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4B2B),
          brightness: Brightness.light,
        ),
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
  String _sebep =
      "Grup üyelerinin konumlarını ve canlarının ne çektiğini girin! ✨";
  bool _yukleniyor = false;

  // YENİ YAPI: İlçeler ve içlerindeki Mahalle/Caddeler (Sözlük Formatı)
  final Map<String, List<String>> _ankaraKonumlari = {
    'Çankaya': [
      '7. Cadde (Bahçelievler)',
      'Anıttepe',
      'Arjantin Caddesi',
      'Ayrancı',
      'Bahçelievler',
      'Balgat',
      'Beşevler',
      'Bilkent',
      'Birlik Mahallesi',
      'Cebeci',
      'Çayyolu',
      'Çukurambar',
      'Demirtepe',
      'Dikmen Vadisi',
      'Emek',
      'Filistin Caddesi',
      'Gaziosmanpaşa (GOP)',
      'Kavaklıdere',
      'Kızılay',
      'Konutkent',
      'Kurtuluş',
      'Mutluköy',
      'Oran',
      'Öveçler',
      'Sancak',
      'Söğütözü',
      'Tunalı Hilmi',
      'Tunus Caddesi',
      'Ümitköy',
      'Yaşamkent',
      'Yıldız',
      '100. Yıl (İşçi Blokları)',
    ],
    'Yenimahalle': [
      'Batıkent Meydan',
      'Demetevler',
      'Ostim',
      'Şentepe',
      'Gazi Mahallesi',
    ],
    'Keçiören': ['Basınevleri', 'Etlik', 'İncirli', 'Aktepe', 'Subayevleri'],
    'Etimesgut': ['Eryaman', 'Elvankent', 'Bağlıca', 'Göksu'],
    'Mamak': ['Kusunlar', 'Abidinpaşa', 'Akdere', 'Boğaziçi', 'Natoyolu'],
    'Altındağ': ['Ulus', 'Siteler', 'Hasköy', 'Hamamönü'],
    'Gölbaşı': ['İncek', 'Mogan', 'Eymir', 'Kızılcaşar'],
    'Pursaklar': ['Merkez', 'Saray'],
    'Sincan': ['Merkez', 'Fatih', 'Yenikent', 'Törekent'],
  };

  // Başlangıç değerlerini yeni formata uygun şekilde güncelledik
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
      _sebep =
          "Yapay zeka sokaklardaki en otantik lezzet noktalarını tarıyor... 🔍";
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
            _sebep = data['sebep'] ?? "Sebep belirtilmedi.";
          });
        } else {
          setState(() {
            _mekanAdi = "Sistem Hatası 🤖";
            _puan = "";
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "🔥 Ekip Toplanıyor",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _kullanicilar.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(20.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: Colors
                                        .primaries[index %
                                            Colors.primaries.length]
                                        .shade100,
                                    child: Text(
                                      _kullanicilar[index]
                                              .adController
                                              .text
                                              .isNotEmpty
                                          ? _kullanicilar[index]
                                                .adController
                                                .text[0]
                                                .toUpperCase()
                                          : "?",
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors
                                            .primaries[index %
                                                Colors.primaries.length]
                                            .shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildSleekTextField(
                                                _kullanicilar[index]
                                                    .adController,
                                                "İsim",
                                                Icons.person_outline,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: _buildLocationAutoComplete(
                                                index,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: _buildSleekTextField(
                                                _kullanicilar[index]
                                                    .tercihController,
                                                "Ne İstiyor?",
                                                Icons.fastfood_outlined,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: CheckboxListTile(
                                                  title: const Text(
                                                    "Araç",
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  value: _kullanicilar[index]
                                                      .araciVarMi,
                                                  activeColor: Colors.green,
                                                  onChanged: (val) => setState(
                                                    () =>
                                                        _kullanicilar[index]
                                                                .araciVarMi =
                                                            val ?? false,
                                                  ),
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  dense: true,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 70,
                        child: ElevatedButton(
                          onPressed: _yukleniyor ? null : _mekanOnerisiAl,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: _yukleniyor
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Krizi Çöz & Mekan Bul",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(32),
                          child: SelectionArea(
                            child: _yukleniyor
                                ? _buildLoadingState()
                                : _buildResultState(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // YENİ ALGORİTMA: İlçe / Mahalle mantığıyla çalışan akıllı otomatik tamamlama
  Widget _buildLocationAutoComplete(int index) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(
        text: _kullanicilar[index].konumController.text,
      ),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final String inputText = textEditingValue.text;

        if (inputText.isEmpty) {
          // Boşken tüm ilçeleri (Sözlüğün anahtarlarını) göster
          return _ankaraKonumlari.keys;
        }

        // Eğer içinde " / " varsa, ilçeyi ayır ve o ilçenin mahallelerinde arama yap
        if (inputText.contains('/')) {
          final parts = inputText.split('/');
          final district = parts[0].trim();
          final searchNeighborhood = parts.length > 1
              ? parts[1].trimLeft().toLowerCase()
              : '';

          if (_ankaraKonumlari.containsKey(district)) {
            final neighborhoods = _ankaraKonumlari[district]!;
            if (searchNeighborhood.isEmpty) {
              return neighborhoods.map((n) => '$district / $n');
            } else {
              return neighborhoods
                  .where((n) => n.toLowerCase().contains(searchNeighborhood))
                  .map((n) => '$district / $n');
            }
          } else {
            return const Iterable<String>.empty();
          }
        } else {
          // Henüz " / " yoksa, yazılan harfe göre ilçeleri (örn: Çankaya) filtrele
          final searchDistrict = inputText.trimLeft().toLowerCase();
          return _ankaraKonumlari.keys.where(
            (d) => d.toLowerCase().contains(searchDistrict),
          );
        }
      },
      onSelected: (String selection) {
        // Eğer kullanıcı sadece ilçeyi seçtiyse (içinde / yoksa), yanına " / " koyarak beklet
        if (!selection.contains('/')) {
          _kullanicilar[index].konumController.text = '$selection / ';
        } else {
          // Kullanıcı tam adresi seçtiyse aynen kaydet
          _kullanicilar[index].konumController.text = selection;
        }
      },
      fieldViewBuilder: (ctx, ctrl, fNode, onComplete) {
        ctrl.addListener(() {
          // TextField içeriği değiştikçe arka plandaki modelimizi güncelliyoruz
          _kullanicilar[index].konumController.text = ctrl.text;
        });

        return TextField(
          controller: ctrl,
          focusNode: fNode,
          decoration: InputDecoration(
            labelText: "İlçe / Mahalle",
            hintText: "Örn: Çankaya / Tunalı",
            prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width:
                300, // Mahalle isimleri uzun olabileceği için genişliği artırdık
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
              ],
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: opts.length,
              itemBuilder: (ctx, i) => ListTile(
                title: Text(
                  opts.elementAt(i),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  onSelected(opts.elementAt(i));
                  // Seçimden sonra klavyenin açık kalması / odaklanması isteniyorsa burada ekstra işlemler yapılabilir
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSleekTextField(
    TextEditingController ctrl,
    String lbl,
    IconData icon,
  ) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: lbl,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildLoadingState() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.travel_explore, size: 80, color: Color(0xFFFF4B2B)),
      const SizedBox(height: 24),
      Text(
        _sebep,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic),
      ),
    ],
  );

  Widget _buildResultState() => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_mekanAdi.isNotEmpty) ...[
          const Icon(Icons.location_on, size: 60, color: Color(0xFFFF4B2B)),
          const Text(
            "🎉 ORTAK NOKTA BULUNDU!",
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
          Text(
            _mekanAdi,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          if (_puan.isNotEmpty && _puan != "-")
            Chip(
              label: Text(_puan),
              avatar: const Icon(Icons.star, color: Colors.amber),
            ),
          const Divider(height: 40),
        ],
        Text(
          _mekanAdi.isNotEmpty
              ? "Yapay Zeka Neden Burayı Seçti?"
              : "Analiz Bekleniyor",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          _sebep,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, height: 1.5),
        ),
      ],
    ),
  );
}
