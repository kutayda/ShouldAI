import 'package:flutter/material.dart';

/// Sol üst menü: kullanıcı başlığı (yatayda ortalı) + Çıkış Yap.
class AppDrawer extends StatelessWidget {
  final String displayName;
  final Future<void> Function() onSignOut;

  const AppDrawer({
    super.key,
    required this.displayName,
    required this.onSignOut,
  });

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
