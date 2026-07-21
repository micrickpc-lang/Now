import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class PlacePickerScreen extends ConsumerStatefulWidget {
  const PlacePickerScreen({super.key});
  @override
  ConsumerState<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends ConsumerState<PlacePickerScreen> {
  final _search = TextEditingController();
  LatLng? _selected;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find(String value) async {
    if (value.trim().length < 2) return;
    setState(() => _searching = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get<List<dynamic>>(
            '/maps/search',
            queryParameters: {'q': value.trim()},
          );
      setState(() => _results = response.data!.cast<Map<String, dynamic>>());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбрать место'),
        actions: [
          TextButton(
            onPressed: _selected == null
                ? null
                : () => context.pop({
                    'latitude': _selected!.latitude,
                    'longitude': _selected!.longitude,
                  }),
            child: const Text('Готово'),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (config.demoMode)
            GestureDetector(
              onTap: () =>
                  setState(() => _selected = const LatLng(43.7384, 7.4246)),
              child: Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF29264A), Color(0xFF173B3A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Демо-карта без сети\nНажми, чтобы выбрать тестовую точку',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            )
          else
            MapLibreMap(
              styleString: '${config.apiBaseUrl}/maps/style.json',
              initialCameraPosition: const CameraPosition(
                target: LatLng(43.7384, 7.4246),
                zoom: 12,
              ),
              onMapLongClick: (_, point) => setState(() => _selected = point),
              onMapClick: (_, point) => setState(() => _selected = point),
              myLocationEnabled: false,
              compassEnabled: true,
              attributionButtonMargins: const Point(8, 56),
            ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: TextField(
                    controller: _search,
                    onSubmitted: _find,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Город, улица или место',
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: () => _find(_search.text),
                              icon: const Icon(Icons.arrow_forward),
                            ),
                    ),
                  ),
                ),
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 230),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final row in _results)
                          ListTile(
                            title: Text(
                              row['label'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                _selected = LatLng(
                                  (row['latitude'] as num).toDouble(),
                                  (row['longitude'] as num).toDouble(),
                                );
                                _results = const [];
                              });
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: .86),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
          if (_selected != null)
            const Center(
              child: IgnorePointer(
                child: Icon(
                  Icons.location_pin,
                  color: AppColors.coral,
                  size: 48,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
