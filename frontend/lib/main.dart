import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/auth_gate.dart';

// 🚨 Supabase panelinden al: Settings > API
//   - Project URL            -> supabaseUrl
//   - anon / publishable key -> supabaseAnonKey  (istemcide kullanılması GÜVENLİ;
//     gizli/secret key'i ASLA buraya koyma, o sadece sunucu tarafı içindir)
const String supabaseUrl = 'https://dpihmwfhohaaurmnovcg.supabase.co';
const String supabaseAnonKey = 'sb_publishable_yNqgph1kunM6W4XDcDf-iQ_CAADcl5Q';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const ShouldAIApp());
}

class ShouldAIApp extends StatelessWidget {
  const ShouldAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShouldAI',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}
