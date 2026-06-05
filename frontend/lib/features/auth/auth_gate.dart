import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map/home_map_screen.dart';
import 'login_screen.dart';
import 'onboarding_preferences_screen.dart';

/// Oturum durumuna göre yönlendirir:
/// - Oturum yok            -> LoginScreen
/// - Oturum var, onboarded değil -> OnboardingPreferencesScreen
/// - Oturum var, onboarded -> HomeMapScreen
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        return const _PostLoginRouter();
      },
    );
  }
}

class _PostLoginRouter extends StatefulWidget {
  const _PostLoginRouter();

  @override
  State<_PostLoginRouter> createState() => _PostLoginRouterState();
}

class _PostLoginRouterState extends State<_PostLoginRouter> {
  late Future<bool> _onboardedFuture;

  @override
  void initState() {
    super.initState();
    _onboardedFuture = _isOnboarded();
  }

  Future<bool> _isOnboarded() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('onboarded')
          .eq('id', userId)
          .maybeSingle();
      return (row?['onboarded'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboardedFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data!
            ? const HomeMapScreen()
            : const OnboardingPreferencesScreen();
      },
    );
  }
}
