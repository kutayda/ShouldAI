import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'group_service.dart';
import 'chat_service.dart';

/// Sağ alttaki yuvarlak grup butonundan açılan, ekran ortasında koyu panel.
class GroupPanel extends StatefulWidget {
  final void Function(String groupId) onGatherTeam;
  final VoidCallback onPickPlaceForShare;
  final void Function(double lat, double lng, String name) onShowPlaceOnMap;
  final double? currentLat;
  final double? currentLng;

  const GroupPanel({
    super.key,
    required this.onGatherTeam,
    required this.onPickPlaceForShare,
    required this.onShowPlaceOnMap,
    this.currentLat,
    this.currentLng,
  });

  @override
  State<GroupPanel> createState() => _GroupPanelState();
}

class _GroupPanelState extends State<GroupPanel> {
  static const Color _bg = Color(0xFF1E1E1E);
  static const Color _field = Color(0xFF2A2A2A);

  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _members = [];

  int _tab = 0;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _msgCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groups = await GroupService.myGroups();
      if (groups.isNotEmpty) {
        _group = groups.first;
        _members = await GroupService.members(_group!['id'].toString());
      } else {
        _group = null;
      }
    } catch (e) {
      _snack(_friendly(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  String _friendly(Object e) {
    if (e is PostgrestException) return e.message;
    if (e is AuthException) return e.message;
    return "Bir şeyler ters gitti, tekrar dener misin?";
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF333333),
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack("Önce bir grup adı yaz.");
      return;
    }
    setState(() => _busy = true);
    try {
      final g = await GroupService.createGroup(name);
      if (!mounted) return;
      await _showCodePopup(g['code'].toString());
      await _load();
    } catch (e) {
      _snack(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase().replaceAll('#', '');
    if (code.isEmpty) {
      _snack("Önce grup kodunu yaz.");
      return;
    }
    setState(() => _busy = true);
    try {
      await GroupService.joinByCode(code);
      await _load();
    } catch (e) {
      _snack(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCodePopup(String code) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const Text(
                "Gruba katılmasını istediğin arkadaşlarınla aşağıdaki kodu paylaşabilirsin:",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: _field,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent, width: 1.5),
                ),
                child: Text(
                  "#$code",
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: _loading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : (_group == null ? _buildNoGroup() : _buildInGroup()),
    );
  }

  // ---------- Gruba üye değilken ----------
  Widget _buildNoGroup() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _closeRow(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _tabHeader("Grup Oluştur", 0),
              _tabHeader("Gruba Katıl", 1),
            ],
          ),
          const SizedBox(height: 22),
          if (_tab == 0) ...[
            _input(_nameCtrl, "Grup Adı", Icons.badge_outlined),
            const SizedBox(height: 16),
            _primaryButton("Oluştur", _create),
          ] else ...[
            _input(_codeCtrl, "Grup Kodu (#ABC12)", Icons.tag, caps: true),
            const SizedBox(height: 16),
            _primaryButton("Katıl", _join),
          ],
        ],
      ),
    );
  }

  // ---------- Gruba üyeyken ----------
  Widget _buildInGroup() {
    final gid = _group!['id'].toString();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _closeRow(),
        Row(
          children: [
            const Icon(Icons.groups, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _group!['name'].toString(),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _field,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "#${_group!['code']}",
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.blueAccent,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Üyeler (kompakt çipler)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _members
              .map(
                (m) => Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _field,
                  avatar: const Icon(
                    Icons.person,
                    size: 16,
                    color: Colors.white70,
                  ),
                  label: Text(
                    m['display_name']?.toString() ?? "Üye",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onGatherTeam(gid);
            },
            icon: const Icon(Icons.travel_explore, size: 20),
            label: const Text(
              "Ekibi Topla",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const Divider(color: Colors.white24, height: 22),
        // Sohbet
        const Text(
          "Grup Sohbeti",
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 6),
        SizedBox(height: 220, child: _buildChat(gid)),
        const SizedBox(height: 8),
        _buildInputRow(gid),
      ],
    );
  }

  Widget _buildChat(String groupId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ChatService.messagesStream(groupId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final msgs = snap.data!;
        if (msgs.isEmpty) {
          return const Center(
            child: Text(
              "Henüz mesaj yok. İlk mesajı sen at!",
              style: TextStyle(color: Colors.white38),
            ),
          );
        }
        // Yeni mesaj geldiğinde en alta kaydır (sohbet aşağı doğru akar)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScroll.hasClients) {
            _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _chatScroll,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: msgs.length,
          itemBuilder: (ctx, i) => _bubble(msgs[i]), // eski üstte, yeni altta
        );
      },
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['sender_id'] == _myId;
    final kind = m['kind']?.toString() ?? 'text';
    final name = m['sender_name']?.toString() ?? "Üye";

    Widget content;
    if (kind == 'place' || kind == 'location') {
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(m['body']?.toString() ?? '{}');
      } catch (_) {}
      final title = kind == 'place'
          ? (data['name']?.toString() ?? "Paylaşılan mekan")
          : "Konum paylaşıldı";
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place, size: 16, color: Colors.blueAccent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (lat != null && lng != null)
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                Navigator.pop(context); // paneli kapat, haritayı göster
                widget.onShowPlaceOnMap(lat, lng, title);
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text("Haritada Gör"),
            ),
        ],
      );
    } else {
      content = Text(
        m['body']?.toString() ?? "",
        style: const TextStyle(color: Colors.white),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? Colors.blueAccent.withValues(alpha: 0.25) : _field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow(String groupId) {
    return Row(
      children: [
        // "+" paylaşım menüsü
        PopupMenuButton<String>(
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
          color: _field,
          onSelected: (v) {
            if (v == 'location') {
              if (widget.currentLat != null && widget.currentLng != null) {
                ChatService.sendLocation(
                  groupId,
                  widget.currentLat!,
                  widget.currentLng!,
                );
              } else {
                _snack("Konumun henüz hazır değil.");
              }
            } else if (v == 'place') {
              Navigator.pop(context); // paneli kapat
              widget.onPickPlaceForShare();
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(
              value: 'place',
              child: Text("Yer Paylaş", style: TextStyle(color: Colors.white)),
            ),
            PopupMenuItem(
              value: 'location',
              child: Text(
                "Konum Paylaş",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendText(groupId),
            decoration: InputDecoration(
              hintText: "Mesaj yaz...",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: _field,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send, color: Colors.blueAccent),
          onPressed: () => _sendText(groupId),
        ),
      ],
    );
  }

  Future<void> _sendText(String groupId) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    try {
      await ChatService.sendText(groupId, text);
    } catch (e) {
      _snack(_friendly(e));
    }
  }

  // ---------- Yardımcılar ----------
  Widget _closeRow() => Align(
    alignment: Alignment.topRight,
    child: IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: const Icon(Icons.close, color: Colors.white54),
      onPressed: () => Navigator.pop(context),
    ),
  );

  Widget _tabHeader(String text, int index) {
    final selected = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
              color: selected ? Colors.white : Colors.white54,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 3,
            width: 90,
            color: selected ? Colors.blueAccent : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _input(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool caps = false,
  }) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      textCapitalization: caps
          ? TextCapitalization.characters
          : TextCapitalization.none,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: _field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap, {IconData? icon}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
        label: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
