import 'package:supabase_flutter/supabase_flutter.dart';

/// Grup işlemleri için Supabase sarmalayıcısı.
class GroupService {
  static final _db = Supabase.instance.client;

  /// Yeni grup oluşturur, üretilen grubu (kod dahil) döndürür.
  static Future<Map<String, dynamic>> createGroup(String name) async {
    final res = await _db.rpc('create_group', params: {'p_name': name});
    // RPC tek satır döndürür (list ya da map gelebilir)
    if (res is List && res.isNotEmpty)
      return Map<String, dynamic>.from(res.first);
    return Map<String, dynamic>.from(res as Map);
  }

  /// Koda göre gruba katılır, grubu döndürür.
  static Future<Map<String, dynamic>> joinByCode(String code) async {
    final res = await _db.rpc('join_group_by_code', params: {'p_code': code});
    if (res is List && res.isNotEmpty)
      return Map<String, dynamic>.from(res.first);
    return Map<String, dynamic>.from(res as Map);
  }

  /// Kullanıcının üye olduğu grupları getirir (en yeni önce).
  static Future<List<Map<String, dynamic>>> myGroups() async {
    final uid = _db.auth.currentUser!.id;
    final memberRows = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final ids = (memberRows as List).map((r) => r['group_id']).toList();
    if (ids.isEmpty) return [];
    final groups = await _db
        .from('groups')
        .select('id, name, code, owner_id, created_at')
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(groups as List);
  }

  /// Bir grubun üyelerini (ad listesi) getirir.
  static Future<List<Map<String, dynamic>>> members(String groupId) async {
    final res = await _db.rpc(
      'group_member_names',
      params: {'p_group': groupId},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Gruptan çıkar (kendi üyeliğini siler).
  static Future<void> leave(String groupId) async {
    final uid = _db.auth.currentUser!.id;
    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', uid);
  }
}
