/// Tüm backend API çağrıları bu adresi kullanır.
///
/// - Yerel geliştirme: varsayılan (localhost) kullanılır, hiçbir şey yapma.
/// - Deploy (web build): Render adresini derleme anında geç:
///     flutter build web --dart-define=BASE_URL=https://SENIN-BACKEND.onrender.com
const String kBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://localhost:8000',
);
