import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulama genelinde kullanılan mutfak kategorileri (onboarding ile birebir aynı)
const List<String> kCuisines = [
  "Kebap / Izgara",
  "Ev Yemekleri / Lokanta",
  "Pide / Lahmacun",
  "Döner",
  "Burger",
  "Pizza",
  "İtalyan",
  "Uzakdoğu / Sushi",
  "Deniz Ürünleri",
  "Tatlı / Pastane",
  "Kahve / Cafe",
  "Kahvaltı",
  "Çiğ Köfte",
  "Tavuk",
  "Vejetaryen / Vegan",
  "Sokak Lezzetleri",
];

const Color _bg = Color(0xFF121212);
const Color _card = Color(0xFF1E1E1E);

/// Soldan sağa kayan geçişle sayfa açar (drawer'dan açılan paneller için)
Route slideFromLeft(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Koyu temalı mutfak tercih editörü. Mevcut tercihleri profilden yükler,
/// kaydedince profiles.liked_cuisines / disliked_cuisines günceller ve geri döner.
class CuisineEditorScreen extends StatefulWidget {
  const CuisineEditorScreen({super.key});

  @override
  State<CuisineEditorScreen> createState() => _CuisineEditorScreenState();
}

class _CuisineEditorScreenState extends State<CuisineEditorScreen> {
  // 0 = nötr, 1 = sevilen, -1 = sevilmeyen
  final Map<String, int> _state = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('liked_cuisines, disliked_cuisines')
          .eq('id', uid)
          .single();
      final liked = List<String>.from(row['liked_cuisines'] ?? []);
      final disliked = List<String>.from(row['disliked_cuisines'] ?? []);
      for (final c in liked) {
        _state[c] = 1;
      }
      for (final c in disliked) {
        _state[c] = -1;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _cycle(String c) {
    setState(() {
      final cur = _state[c] ?? 0;
      _state[c] = cur == 0 ? 1 : (cur == 1 ? -1 : 0);
    });
  }

  Future<void> _save() async {
    final liked = _state.entries
        .where((e) => e.value == 1)
        .map((e) => e.key)
        .toList();
    final disliked = _state.entries
        .where((e) => e.value == -1)
        .map((e) => e.key)
        .toList();

    setState(() => _saving = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client
          .from('profiles')
          .update({'liked_cuisines': liked, 'disliked_cuisines': disliked})
          .eq('id', uid);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Kaydedilemedi: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          "Damak Zevkin",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    "Bir kez dokun = seviyorum · iki kez = sevmiyorum · üç kez = nötr. "
                    "Bunları sana daha iyi öneriler sunmak için kullanırız.",
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: kCuisines.map((c) {
                        final s = _state[c] ?? 0;
                        final Color bg = s == 1
                            ? const Color(0xFF1B3A2A)
                            : (s == -1 ? const Color(0xFF3A1B1B) : _card);
                        final Color border = s == 1
                            ? Colors.greenAccent
                            : (s == -1
                                  ? const Color(0xFFFF6B6B)
                                  : Colors.transparent);
                        final IconData? icon = s == 1
                            ? Icons.favorite
                            : (s == -1 ? Icons.not_interested : null);
                        final Color iconCol = s == 1
                            ? Colors.greenAccent
                            : const Color(0xFFFF6B6B);
                        return InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () => _cycle(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: border, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (icon != null) ...[
                                  Icon(icon, size: 16, color: iconCol),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  c,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Kaydet",
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Öneri modu seçici: Önerilen (Akıllı Öneri) / Seçici (Katı Kurallar).
/// profiles.recommendation_mode kaydeder.
class RecommendationModeScreen extends StatefulWidget {
  const RecommendationModeScreen({super.key});

  @override
  State<RecommendationModeScreen> createState() =>
      _RecommendationModeScreenState();
}

class _RecommendationModeScreenState extends State<RecommendationModeScreen> {
  String _mode = 'default';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('recommendation_mode')
          .eq('id', uid)
          .single();
      final m = (row['recommendation_mode'] ?? 'default').toString();
      _mode = (m == 'selective') ? 'selective' : 'default';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sec(String mode) async {
    setState(() {
      _mode = mode;
      _saving = true;
    });
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client
          .from('profiles')
          .update({'recommendation_mode': mode})
          .eq('id', uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Kaydedilemedi: $e")));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _secenek({
    required String value,
    required String baslik,
    required String aciklama,
  }) {
    final secili = _mode == value;
    return GestureDetector(
      onTap: _saving ? null : () => _sec(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: secili ? Colors.blueAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              secili
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: secili ? Colors.blueAccent : Colors.white38,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baslik,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    aciklama,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          "Öneri Tercihleri",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Yol üstü önerilerinin damak zevkini nasıl kullanacağını seç.",
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  _secenek(
                    value: 'default',
                    baslik: "Önerilen (Akıllı Öneri)",
                    aciklama:
                        "Sevdiğin türleri önceliklendirir ama körü körüne değil. "
                        "Sevdiğin bir yer yakındaysa onu önerir; ancak çevrede "
                        "belirgin şekilde daha iyi (yarım puandan fazla yüksek) "
                        "bir yer varsa onu önerir. Amaç: her zaman gerçekten "
                        "iyi olanı önermek.",
                  ),
                  _secenek(
                    value: 'selective',
                    baslik: "Seçici (Katı Kurallar)",
                    aciklama:
                        "Yalnızca sevdiğin türleri önerir. Çevrede sevdiğin bir "
                        "tür varsa, puan farkına bakmaksızın onu önerir. "
                        "Sevdiğin hiçbir şey yoksa en iyi nötr seçeneği sunar.",
                  ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        "Kaydediliyor...",
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
