import 'package:flutter/material.dart';
import '../../preferences/preferences_screens.dart';

/// Sol üst menü: kullanıcı başlığı + Kişiselleştirme / Tercihler + Çıkış Yap.
class AppDrawer extends StatelessWidget {
  final String displayName;
  final Future<void> Function() onSignOut;

  const AppDrawer({
    super.key,
    required this.displayName,
    required this.onSignOut,
  });

  Widget _menuRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF3A3A3A),
                    child: Icon(Icons.person, size: 34, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            _menuRow(
              icon: Icons.tune,
              title: "Kişiselleştirme",
              onTap: () {
                Navigator.pop(context); // drawer'ı kapat
                Navigator.of(
                  context,
                ).push(slideFromLeft(const CuisineEditorScreen()));
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            _menuRow(
              icon: Icons.recommend_outlined,
              title: "Tercihler",
              onTap: () {
                Navigator.pop(context);
                Navigator.of(
                  context,
                ).push(slideFromLeft(const RecommendationModeScreen()));
              },
            ),
            const Divider(height: 1, color: Colors.white24),
            const Spacer(),
            const Divider(height: 1, color: Colors.white24),
            InkWell(
              onTap: onSignOut,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Color(0xFFFF6B6B)),
                    SizedBox(width: 10),
                    Text(
                      "Çıkış Yap",
                      style: TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
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
}
