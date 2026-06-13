import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// E-posta + şifre ile kayıt ve giriş ekranı.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignUp = false; // false: Giriş, true: Kayıt
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.length < 6) {
      _snack("E-posta gir ve en az 6 karakterli bir şifre seç.");
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        await auth.signUp(
          email: email,
          password: pass,
          data: {'display_name': _nameCtrl.text.trim()},
        );
      } else {
        await auth.signInWithPassword(email: email, password: pass);
      }
      // Başarılıysa AuthGate oturumu yakalayıp otomatik yönlendirir.
    } on AuthException catch (e) {
      _snack(_friendlyAuth(e.message));
    } catch (e) {
      _snack("Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Supabase'in İngilizce hata mesajlarını kullanıcı dostu Türkçeye çevirir
  String _friendlyAuth(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return "E-posta veya şifre hatalı.";
    }
    if (m.contains('already registered') ||
        m.contains('already exists') ||
        m.contains('user already')) {
      return "Bu e-posta zaten kayıtlı. Giriş yapmayı dene.";
    }
    if (m.contains('password') && m.contains('6')) {
      return "Şifre en az 6 karakter olmalı.";
    }
    if (m.contains('email') && m.contains('valid')) {
      return "Geçerli bir e-posta adresi gir.";
    }
    if (m.contains('email not confirmed')) {
      return "E-postanı onaylaman gerekiyor.";
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return "Çok fazla deneme oldu, biraz sonra tekrar dene.";
    }
    return "Giriş yapılamadı. Bilgileri kontrol edip tekrar dene.";
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade400,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/shouldailogokare.png',
                  width: 96,
                  height: 96,
                ),
                const SizedBox(height: 12),
                const Text(
                  "ShouldAI",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  _isSignUp ? "Hesap oluştur" : "Tekrar hoş geldin",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey.shade400),
                ),
                const SizedBox(height: 28),
                if (_isSignUp) ...[
                  _field(_nameCtrl, "Görünen ad", Icons.person_outline),
                  const SizedBox(height: 14),
                ],
                _field(
                  _emailCtrl,
                  "E-posta",
                  Icons.mail_outline,
                  keyboard: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                _field(_passCtrl, "Şifre", Icons.lock_outline, obscure: true),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isSignUp ? "Kayıt Ol" : "Giriş Yap",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? "Zaten hesabın var mı? Giriş yap"
                        : "Hesabın yok mu? Kayıt ol",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
