import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Grup sohbeti için Supabase sarmalayıcısı (realtime + gönderme).
class ChatService {
  static final _db = Supabase.instance.client;

  static String get _myName {
    final u = _db.auth.currentUser;
    final meta = (u?.userMetadata?['display_name'] as String?)?.trim();
    if (meta != null && meta.isNotEmpty) return meta;
    return u?.email?.split('@').first ?? "Üye";
  }

  /// Bir grubun mesajlarını canlı (realtime) akış olarak verir (eski->yeni).
  static Stream<List<Map<String, dynamic>>> messagesStream(String groupId) {
    return _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .order('created_at', ascending: true);
  }

  static Future<void> sendText(String groupId, String text) async {
    await _db.from('messages').insert({
      'group_id': groupId,
      'sender_id': _db.auth.currentUser!.id,
      'sender_name': _myName,
      'kind': 'text',
      'body': text,
    });
  }

  /// Bir mekanı paylaşır (ad + koordinat).
  static Future<void> sendPlace(
    String groupId,
    String name,
    double lat,
    double lng,
  ) async {
    await _db.from('messages').insert({
      'group_id': groupId,
      'sender_id': _db.auth.currentUser!.id,
      'sender_name': _myName,
      'kind': 'place',
      'body': jsonEncode({'name': name, 'lat': lat, 'lng': lng}),
    });
  }

  /// Anlık konum paylaşır (WhatsApp tarzı).
  static Future<void> sendLocation(
    String groupId,
    double lat,
    double lng,
  ) async {
    await _db.from('messages').insert({
      'group_id': groupId,
      'sender_id': _db.auth.currentUser!.id,
      'sender_name': _myName,
      'kind': 'location',
      'body': jsonEncode({'lat': lat, 'lng': lng}),
    });
  }
}
