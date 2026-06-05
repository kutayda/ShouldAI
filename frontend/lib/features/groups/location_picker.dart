import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Haritadan/veritabanından tam adres seçtiren dialog.
/// Seçim yapılınca {name, lat, lng} döndürür (iptalde null).
class LocationPicker extends StatefulWidget {
  final String baseUrl;
  final double biasLat;
  final double biasLng;

  const LocationPicker({
    super.key,
    required this.baseUrl,
    this.biasLat = 39.92077,
    this.biasLng = 32.85411,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  static const Color _bg = Color(0xFF1E1E1E);
  static const Color _field = Color(0xFF2A2A2A);

  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _preds = [];
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String input) {
    _debounce?.cancel();
    final text = input.trim();
    if (text.length < 2) {
      setState(() {
        _preds = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(text));
  }

  Future<void> _fetch(String input) async {
    final my = ++_seq;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/autocomplete'
        '?input=${Uri.encodeQueryComponent(input)}'
        '&lat=${widget.biasLat}&lng=${widget.biasLng}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (my != _seq || !mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _preds = (data['predictions'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (my == _seq && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(Map<String, dynamic> p) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/place_details?place_id=${p['place_id']}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['status'] == 'success' &&
            data['lat'] != null &&
            data['lng'] != null) {
          Navigator.pop(context, {
            'name':
                data['name']?.toString() ??
                p['main_text']?.toString() ??
                p['description']?.toString() ??
                '',
            'lat': (data['lat'] as num).toDouble(),
            'lng': (data['lng'] as num).toDouble(),
          });
          return;
        }
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Konum çözülemedi, tekrar dene.")),
      );
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Konumunu Seç",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: "Adres veya yer ara (örn. Eryaman, Ankara)",
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: _field,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _preds.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        "Aramak için yazmaya başla.",
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _preds.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white12),
                      itemBuilder: (ctx, i) {
                        final p = _preds[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.place_outlined,
                            color: Colors.blueAccent,
                          ),
                          title: Text(
                            (p['main_text'] ?? p['description'] ?? '')
                                .toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              (p['secondary_text'] ?? '').toString().isEmpty
                              ? null
                              : Text(
                                  p['secondary_text'].toString(),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => _select(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
