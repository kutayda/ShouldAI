import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Google Places Autocomplete ile beslenen, yazdıkça öneri listeleyen arama çubuğu.
/// - Her tuşta değil, kullanıcı ~400 ms durunca istek atar (debounce).
/// - Bir öneri seçilince /api/place_details ile koordinat çözülür ve
///   onPlaceSelected(lat, lng, name) ile haritaya bildirilir.
class SmartSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String baseUrl;
  final double originLat;
  final double originLng;
  final VoidCallback onMenuPressed;
  final void Function(double lat, double lng, String name) onPlaceSelected;

  const SmartSearchBar({
    super.key,
    required this.controller,
    required this.baseUrl,
    required this.originLat,
    required this.originLng,
    required this.onMenuPressed,
    required this.onPlaceSelected,
  });

  @override
  State<SmartSearchBar> createState() => _SmartSearchBarState();
}

class _SmartSearchBarState extends State<SmartSearchBar> {
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];
  bool _loading = false;
  int _requestSeq = 0; // eski/yavaş cevapların yenisini ezmesini engeller

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String input) {
    _debounce?.cancel();
    final text = input.trim();
    if (text.length < 2) {
      setState(() {
        _predictions = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchPredictions(text);
    });
  }

  Future<void> _fetchPredictions(String input) async {
    final mySeq = ++_requestSeq;
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/autocomplete'
        '?input=${Uri.encodeQueryComponent(input)}'
        '&lat=${widget.originLat}&lng=${widget.originLng}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (mySeq != _requestSeq || !mounted) return; // daha yeni bir istek var
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List preds = data['predictions'] ?? [];
        setState(() {
          _predictions = preds.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mySeq == _requestSeq && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(Map<String, dynamic> prediction) async {
    final placeId = prediction['place_id'];
    final shownName =
        (prediction['main_text'] ?? prediction['description'] ?? '').toString();

    widget.controller.text = shownName;
    FocusScope.of(context).unfocus();
    setState(() {
      _predictions = [];
      _loading = true;
    });

    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/api/place_details?place_id=$placeId',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _loading = false);
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['status'] == 'success' &&
            data['lat'] != null &&
            data['lng'] != null) {
          widget.onPlaceSelected(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
            data['name']?.toString() ?? shownName,
          );
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Konum çözülemedi, tekrar dene.")),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Arama bağlantısı başarısız.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Arama kutusu (mevcut beyaz/yuvarlak stil korunuyor) ---
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          elevation: 5,
          shadowColor: Colors.black26,
          child: Container(
            height: 55,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            child: TextField(
              controller: widget.controller,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) {
                if (_predictions.isNotEmpty) _select(_predictions.first);
              },
              decoration: InputDecoration(
                isCollapsed: true,
                hintText: "Konum veya mekan ara...",
                border: InputBorder.none,
                prefixIcon: IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: widget.onMenuPressed,
                ),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (widget.controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              onPressed: () {
                                widget.controller.clear();
                                setState(() => _predictions = []);
                              },
                            )
                          : const Icon(Icons.search, color: Colors.grey)),
              ),
            ),
          ),
        ),

        // --- Öneri listesi (yalnızca tahmin varsa) ---
        if (_predictions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              elevation: 6,
              shadowColor: Colors.black26,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _predictions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (ctx, i) {
                    final p = _predictions[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.place_outlined,
                        color: Colors.blueAccent,
                      ),
                      title: Text(
                        (p['main_text'] ?? p['description'] ?? '').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: (p['secondary_text'] ?? '').toString().isEmpty
                          ? null
                          : Text(
                              p['secondary_text'].toString(),
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => _select(p),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
