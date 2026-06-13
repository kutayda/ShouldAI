import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

/// Kayıt sonrası tercih ekranı. Her mutfak/kategori için kullanıcı:
///   1 kez dokun -> Seviyorum (yeşil)
///   2 kez dokun -> Sevmiyorum (kırmızı)
///   3 kez dokun -> Nötr
/// Kaydedince profiles.liked_cuisines / disliked_cuisines güncellenir.
class OnboardingPreferencesScreen extends StatefulWidget {
  const OnboardingPreferencesScreen({super.key});

  @override
  State<OnboardingPreferencesScreen> createState() =>
      _OnboardingPreferencesScreenState();
}

class _OnboardingPreferencesScreenState
    extends State<OnboardingPreferencesScreen> {
  // Öneri motorunun anlayacağı kategoriler (Türkiye bağlamı)
  static const List<String> _cuisines = [
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

  // 0 = nötr, 1 = sevilen, -1 = sevilmeyen
  final Map<String, int> _state = {};
  bool _saving = false;

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
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client
          .from('profiles')
          .update({
            'liked_cuisines': liked,
            'disliked_cuisines': disliked,
            'onboarded': true,
          })
          .eq('id', userId);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          "Damak Zevkin",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              "Bir kez dokun = seviyorum · iki kez = sevmiyorum. "
              "Bunları sana daha iyi öneriler sunmak için kullanacağız.",
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _cuisines.map((c) {
                  final s = _state[c] ?? 0;
                  final Color bg = s == 1
                      ? const Color(0xFF1B3A2A)
                      : (s == -1
                            ? const Color(0xFF3A1B1B)
                            : const Color(0xFF1E1E1E));
                  final Color border = s == 1
                      ? Colors.greenAccent
                      : (s == -1
                            ? const Color(0xFFFF6B6B)
                            : Colors.transparent);
                  final IconData? icon = s == 1
                      ? Icons.favorite
                      : (s == -1 ? Icons.not_interested : null);
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
                            Icon(
                              icon,
                              size: 16,
                              color: s == 1
                                  ? Colors.greenAccent
                                  : const Color(0xFFFF6B6B),
                            ),
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
                          "Devam Et",
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
