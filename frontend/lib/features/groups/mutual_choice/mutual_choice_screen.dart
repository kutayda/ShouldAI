import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../group_service.dart';
import '../location_picker.dart';

/// Gruptan canlı beslenen "Ekibi Topla" ekranı:
/// - Üye sayısı kadar satır; her satırın adı gruptaki üyeden gelir.
/// - Bir üyenin adresini SADECE o üye düzenleyebilir (enter'layınca herkese yansır).
/// - Panel açıkken başkası güncelleme yaparsa üstte "Veriler güncel değil" uyarısı çıkar.
class MutualChoiceScreen extends StatefulWidget {
  final String groupId;
  final double? currentLat;
  final double? currentLng;

  const MutualChoiceScreen({
    super.key,
    required this.groupId,
    this.currentLat,
    this.currentLng,
  });

  @override
  State<MutualChoiceScreen> createState() => _MutualChoiceScreenState();
}

class _Uye {
  final String userId;
  final String ad;
  String adres;
  double? lat;
  double? lng;
  _Uye(this.userId, this.ad, this.adres, {this.lat, this.lng});
}

class _MutualChoiceScreenState extends State<MutualChoiceScreen> {
  static const Color _bg = Color(0xFF121212);
  static const Color _card = Color(0xFF1E1E1E);
  static const Color _field = Color(0xFF2A2A2A);
  final String baseUrl = "http://localhost:8000";

  final _db = Supabase.instance.client;
  RealtimeChannel? _channel;

  List<_Uye> _uyeler = [];
  bool _loading = true;
  bool _stale = false; // başka kullanıcı güncelleme yaptı mı?
  bool _busy = false;
  String _kategori = "Restoran"; // grup hangi kategoride toplanıyor

  String? get _myId => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _yukle();
    _aboneOl();
  }

  @override
  void dispose() {
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _yukle({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final members = await GroupService.members(widget.groupId);
      final rows = await _db
          .from('gather_locations')
          .select('user_id, address, lat, lng')
          .eq('group_id', widget.groupId);

      final byUser = <String, Map<String, dynamic>>{};
      for (final r in (rows as List)) {
        byUser[r['user_id'].toString()] = Map<String, dynamic>.from(r);
      }

      _uyeler = members.map((m) {
        final uid = m['user_id'].toString();
        final row = byUser[uid];
        return _Uye(
          uid,
          m['display_name']?.toString() ?? "Üye",
          (row?['address'] ?? '').toString(),
          lat: (row?['lat'] as num?)?.toDouble(),
          lng: (row?['lng'] as num?)?.toDouble(),
        );
      }).toList();
      _stale = false;
    } catch (e) {
      _snack("Veriler yüklenemedi: $e");
    }
    if (mounted) setState(() => _loading = false);
  }

  void _aboneOl() {
    _channel = _db.channel('gather_${widget.groupId}');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'gather_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: widget.groupId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            final uid = rec['user_id'];
            // Kendi düzenlememiz değilse "güncel değil" uyarısı çıkar
            if (uid != null && uid != _myId && mounted) {
              setState(() => _stale = true);
            }
          },
        )
        .subscribe();
  }

  // Kendi adresini haritadan (Google) seçtirir, koordinatla birlikte kaydeder
  Future<void> _konumSec(_Uye u) async {
    final secim = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => LocationPicker(
        baseUrl: baseUrl,
        biasLat: widget.currentLat ?? 39.92077,
        biasLng: widget.currentLng ?? 32.85411,
      ),
    );
    if (secim == null) return;

    final address = secim['name']?.toString() ?? '';
    final lat = (secim['lat'] as num?)?.toDouble();
    final lng = (secim['lng'] as num?)?.toDouble();

    try {
      await _db.from('gather_locations').upsert({
        'group_id': widget.groupId,
        'user_id': _myId,
        'address': address,
        'lat': lat,
        'lng': lng,
      });
      if (mounted) {
        setState(() {
          u.adres = address;
          u.lat = lat;
          u.lng = lng;
        });
      }
      _snack("Konumun güncellendi.");
    } catch (e) {
      _snack("Kaydedilemedi: $e");
    }
  }

  Future<void> _mekanOner() async {
    // Öneri öncesi en güncel veriyi çek: ekran açıkken başkası konum
    // girmiş olabilir; centroid TÜM üyeleri kapsasın.
    await _yukle(silent: true);

    final secili = _uyeler.where((u) => u.adres.trim().isNotEmpty).toList();
    final users = secili
        .map(
          (u) => {
            "name": u.ad,
            "location": u.adres.trim(),
            "preference": "",
            "lat": u.lat,
            "lng": u.lng,
          },
        )
        .toList();

    if (users.isEmpty) {
      _snack("En az bir kişinin konumu seçilmeli.");
      return;
    }

    setState(() => _busy = true);
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/get_recommendation'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "users": users,
              "category": _kategori.toLowerCase(),
              "current_lat": widget.currentLat,
              "current_lng": widget.currentLng,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['status'] == 'success') {
          _sonucGoster(data);
        } else {
          _snack(data['message']?.toString() ?? "Uygun mekan bulunamadı.");
        }
      } else {
        _snack("Sunucu hatası: ${res.statusCode}");
      }
    } catch (e) {
      _snack("Bağlantı hatası: Backend açık mı?");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sonucGoster(Map data) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    "${data['puan']} / 5.0",
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data['mekan_adi']?.toString() ?? "",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                data['sebep']?.toString() ?? "",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx); // dialog
                    Navigator.pop(context, {
                      'lat': data['lat'],
                      'lng': data['lng'],
                      'name': data['mekan_adi'],
                    });
                  },
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text(
                    "Navigasyonda Gör",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF333333),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Ekibi Topla",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_stale) _staleBanner(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _uyeler.length,
                    itemBuilder: (ctx, i) => _uyeKart(_uyeler[i]),
                  ),
                ),
                _kategoriSecici(),
                _altButon(),
              ],
            ),
    );
  }

  // Grup hangi kategoride toplanacak? (yatayda ortalı Kafe/Restoran şalteri)
  Widget _kategoriSecici() {
    Widget secenek(String label, IconData icon) {
      final secili = _kategori == label;
      return GestureDetector(
        onTap: () => setState(() => _kategori = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: secili ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: secili ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: secili ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            secenek("Kafe", Icons.local_cafe),
            secenek("Restoran", Icons.restaurant),
          ],
        ),
      ),
    );
  }

  Widget _staleBanner() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              "Veriler güncel değil. Sayfayı yenilemek ister misiniz?",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _yukle,
            child: const Text(
              "Yenile",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _uyeKart(_Uye u) {
    final benim = u.userId == _myId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 14,
                backgroundColor: _field,
                child: Icon(Icons.person, size: 16, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              Text(
                benim ? "${u.ad} (Sen)" : u.ad,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!benim) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock_outline, size: 14, color: Colors.white38),
              ],
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: benim ? () => _konumSec(u) : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _field,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: Colors.white54),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      u.adres.trim().isNotEmpty
                          ? u.adres
                          : (benim
                                ? "Konumunu seçmek için dokun"
                                : "Konum bekleniyor..."),
                      style: TextStyle(
                        color: u.adres.trim().isNotEmpty
                            ? Colors.white
                            : Colors.white38,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (benim)
                    const Icon(Icons.search, color: Colors.blueAccent, size: 20)
                  else
                    const Icon(
                      Icons.lock_outline,
                      color: Colors.white24,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _altButon() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _mekanOner,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.restaurant),
            label: Text(
              _busy ? "Hesaplanıyor..." : "Mekan Öner",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
