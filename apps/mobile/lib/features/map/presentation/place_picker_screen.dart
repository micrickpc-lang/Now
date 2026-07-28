import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../data/maps_repository.dart';
import '../domain/map_models.dart';

class PlacePickerScreen extends ConsumerStatefulWidget {
  const PlacePickerScreen({
    this.request = const PlacePickerRequest.signal(),
    super.key,
  });

  final PlacePickerRequest request;

  @override
  ConsumerState<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

enum _LocationUiState {
  idle,
  requesting,
  locating,
  ready,
  serviceDisabled,
  denied,
  deniedForever,
  restricted,
  timeout,
  unavailable,
}

class _PlacePickerScreenState extends ConsumerState<PlacePickerScreen> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  Timer? _mapLoadDeadline;
  MapLibreMapController? _mapController;
  Circle? _selectedMarker;

  late LocationPrivacyMode _mode;
  GeoPoint? _selected;
  DeviceLocation? _current;
  LocationPermissionState? _permission;
  _LocationUiState _locationState = _LocationUiState.idle;
  List<MapPlace> _results = const [];
  String? _selectedLabel;
  String? _searchError;
  String? _reverseError;
  String? _submitError;
  double? _selectedAccuracyMeters;
  bool _permissionExplained = false;
  bool _styleReady = false;
  bool _mapLoadFailed = false;
  bool _searching = false;
  bool _reversing = false;
  bool _submitting = false;
  int _searchRevision = 0;
  int _reverseRevision = 0;
  int _mapRevision = 0;

  @override
  void initState() {
    super.initState();
    _mode = widget.request.initialMode;
    _selected = widget.request.initialPoint;
    _selectedLabel = widget.request.initialLabel;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _mapLoadDeadline?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _startMapLoadDeadline() {
    _mapLoadDeadline?.cancel();
    _mapLoadDeadline = Timer(const Duration(seconds: 15), () {
      if (mounted && !_styleReady) setState(() => _mapLoadFailed = true);
    });
  }

  void _retryMap() {
    _mapLoadDeadline?.cancel();
    setState(() {
      _mapController = null;
      _selectedMarker = null;
      _styleReady = false;
      _mapLoadFailed = false;
      _mapRevision++;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _find(value),
    );
  }

  Future<void> _find(String value) async {
    final query = value.trim();
    if (query.length < 2 || _searching && query != _search.text.trim()) return;
    final revision = ++_searchRevision;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await ref.read(mapsRepositoryProvider).search(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _results = results;
        if (results.isEmpty) _searchError = 'Ничего не найдено';
      });
    } catch (_) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _results = const [];
        _searchError = 'Поиск сейчас недоступен';
      });
    } finally {
      if (mounted && revision == _searchRevision) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _choosePlace(MapPlace place) async {
    FocusScope.of(context).unfocus();
    _search.text = place.label;
    setState(() => _results = const []);
    await _selectPoint(
      place.point,
      fallbackLabel: place.label,
      moveCamera: true,
    );
  }

  Future<void> _selectPoint(
    GeoPoint point, {
    String? fallbackLabel,
    bool moveCamera = false,
    double? accuracyMeters,
  }) async {
    if (widget.request.readOnly) return;
    final revision = ++_reverseRevision;
    setState(() {
      _selected = point;
      _selectedLabel = fallbackLabel ?? 'Выбранная точка';
      _selectedAccuracyMeters = accuracyMeters;
      _reverseError = null;
      _submitError = null;
      _reversing = true;
    });
    await _syncSelectedMarker();
    if (moveCamera) await _moveCamera(point, zoom: 15);
    try {
      final reverse = await ref.read(mapsRepositoryProvider).reverse(point);
      if (!mounted || revision != _reverseRevision) return;
      setState(() => _selectedLabel = reverse.label);
    } catch (_) {
      if (!mounted || revision != _reverseRevision) return;
      setState(() => _reverseError = 'Адрес не найден — точка сохранена');
    } finally {
      if (mounted && revision == _reverseRevision) {
        setState(() => _reversing = false);
      }
    }
  }

  Future<void> _syncSelectedMarker() async {
    final controller = _mapController;
    final point = _selected;
    if (controller == null || point == null || !_styleReady) return;
    final options = CircleOptions(
      geometry: LatLng(point.latitude, point.longitude),
      circleRadius: 10,
      circleColor: '#FF6B6B',
      circleStrokeWidth: 3,
      circleStrokeColor: '#FFFFFF',
      circleOpacity: 1,
    );
    final marker = _selectedMarker;
    try {
      if (marker == null) {
        _selectedMarker = await controller.addCircle(options);
      } else {
        await controller.updateCircle(marker, options);
      }
    } catch (_) {
      // Style reloads briefly invalidate annotations. onStyleLoaded retries.
    }
  }

  Future<void> _moveCamera(GeoPoint point, {double zoom = 16}) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(point.latitude, point.longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  Future<void> _useMyLocation() async {
    if (_locationState == _LocationUiState.requesting ||
        _locationState == _LocationUiState.locating) {
      return;
    }
    if (!_permissionExplained) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.my_location_rounded),
          title: const Text('Использовать геопозицию?'),
          content: Text(
            widget.request.exactRoom
                ? 'Приложение получит геопозицию только после этого нажатия. Точная точка не публикуется, пока ты отдельно не подтвердишь отправку в комнате.'
                : 'Приложение получит геопозицию только после этого нажатия. Для сигнала сервер сохранит только выбранный безопасный уровень: город, район или приблизительную зону.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Не сейчас'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
      _permissionExplained = true;
    }

    final provider = ref.read(locationProviderProvider);
    setState(() {
      _locationState = _LocationUiState.requesting;
      _submitError = null;
    });
    try {
      if (!await provider.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationState = _LocationUiState.serviceDisabled);
        }
        return;
      }
      var permission = await provider.checkPermission();
      if (permission == LocationPermissionState.notDetermined ||
          permission == LocationPermissionState.denied) {
        permission = await provider.requestPermission();
      }
      if (!mounted) return;
      _permission = permission;
      if (!permission.isGranted) {
        setState(
          () => _locationState = switch (permission) {
            LocationPermissionState.deniedForever =>
              _LocationUiState.deniedForever,
            LocationPermissionState.restricted => _LocationUiState.restricted,
            _ => _LocationUiState.denied,
          },
        );
        return;
      }
      setState(() => _locationState = _LocationUiState.locating);
      final location = await provider.getCurrentLocation();
      if (!mounted) return;
      _current = location;
      setState(() => _locationState = _LocationUiState.ready);
      await _selectPoint(
        GeoPoint(location.latitude, location.longitude),
        moveCamera: true,
        accuracyMeters: location.accuracyMeters,
      );
    } on LocationFailure catch (error) {
      if (!mounted) return;
      setState(
        () => _locationState = switch (error.code) {
          LocationFailureCode.permissionDenied => _LocationUiState.denied,
          LocationFailureCode.permissionDeniedForever =>
            _LocationUiState.deniedForever,
          LocationFailureCode.restricted => _LocationUiState.restricted,
          LocationFailureCode.serviceDisabled =>
            _LocationUiState.serviceDisabled,
          LocationFailureCode.timeout => _LocationUiState.timeout,
          LocationFailureCode.unavailable => _LocationUiState.unavailable,
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _locationState = _LocationUiState.unavailable);
      }
    }
  }

  Future<void> _finish() async {
    if (_submitting) return;
    if (_mode == LocationPrivacyMode.none) {
      context.pop(const MapSelectionResult.none());
      return;
    }
    final point = _selected;
    if (point == null) {
      setState(() => _submitError = 'Выбери точку на карте или через поиск');
      return;
    }
    final config = ref.read(appConfigProvider);
    if (widget.request.exactRoom && !config.canShareExactLocation) {
      setState(
        () => _submitError =
            'Точная геопозиция отключена без защищённого HTTPS-соединения',
      );
      return;
    }
    if (widget.request.exactRoom) {
      context.pop(
        MapSelectionResult(
          mode: LocationPrivacyMode.exactRoomOnly,
          sourcePoint: point,
          accuracyMeters: _selectedAccuracyMeters,
          label: _selectedLabel,
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final safeLocation = await ref
          .read(mapsRepositoryProvider)
          .createSafeLocation(
            mode: _mode,
            point: point,
            accuracyMeters: _selectedAccuracyMeters ?? 0,
          );
      if (!mounted) return;
      context.pop(
        MapSelectionResult(
          mode: _mode,
          label: safeLocation.description,
          safeLocation: safeLocation,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _submitError =
              'Не удалось создать безопасную зону. Попробуй ещё раз.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final initial =
        widget.request.initialPoint ??
        GeoPoint(config.initialMapLatitude, config.initialMapLongitude);
    final exactBlocked =
        widget.request.exactRoom && !config.canShareExactLocation;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.request.readOnly ? 'Точное место' : 'Выбрать место'),
        actions: [
          if (!widget.request.readOnly)
            TextButton(
              onPressed: _submitting || exactBlocked ? null : _finish,
              child: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Готово'),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (config.demoMode)
            _DemoMap(
              selected: _selected,
              onTap: widget.request.readOnly
                  ? null
                  : () => _selectPoint(
                      GeoPoint(
                        config.pilotCenterLatitude,
                        config.pilotCenterLongitude,
                      ),
                      fallbackLabel: config.pilotRegion,
                    ),
            )
          else
            MapLibreMap(
              key: ValueKey('place-map-$_mapRevision'),
              styleString: config.mapStyleUrl,
              initialCameraPosition: CameraPosition(
                target: LatLng(initial.latitude, initial.longitude),
                zoom: widget.request.initialPoint == null
                    ? config.initialMapZoom
                    : 15,
              ),
              cameraTargetBounds: config.usesGlobalMapProvider
                  ? CameraTargetBounds.unbounded
                  : CameraTargetBounds(
                      LatLngBounds(
                        southwest: LatLng(
                          config.pilotBounds.south,
                          config.pilotBounds.west,
                        ),
                        northeast: LatLng(
                          config.pilotBounds.north,
                          config.pilotBounds.east,
                        ),
                      ),
                    ),
              minMaxZoomPreference: MinMaxZoomPreference(
                config.minimumMapZoom,
                config.maximumMapZoom,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                _startMapLoadDeadline();
              },
              onStyleLoadedCallback: () {
                _mapLoadDeadline?.cancel();
                if (mounted) {
                  setState(() {
                    _styleReady = true;
                    _mapLoadFailed = false;
                    _selectedMarker = null;
                  });
                }
                unawaited(_syncSelectedMarker());
              },
              onMapClick: widget.request.readOnly
                  ? null
                  : (_, point) =>
                        _selectPoint(GeoPoint(point.latitude, point.longitude)),
              onMapLongClick: widget.request.readOnly
                  ? null
                  : (_, point) =>
                        _selectPoint(GeoPoint(point.latitude, point.longitude)),
              myLocationEnabled: _current != null,
              myLocationTrackingMode: MyLocationTrackingMode.none,
              myLocationRenderMode: MyLocationRenderMode.normal,
              compassEnabled: true,
              attributionButtonMargins: const math.Point(8, 72),
            ),
          if (!config.demoMode && !_styleReady)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_mapLoadFailed,
                child: ColoredBox(
                  color: AppColors.ink.withValues(alpha: .2),
                  child: Center(
                    child: Card(
                      margin: const EdgeInsets.all(32),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: _mapLoadFailed
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cloud_off_rounded),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Карта не загрузилась. Проверь соединение с сервером.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  TextButton(
                                    onPressed: _retryMap,
                                    child: const Text('Повторить'),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Загружаем карту…'),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!widget.request.readOnly)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _SearchPanel(
                controller: _search,
                searching: _searching,
                error: _searchError,
                results: _results,
                onChanged: _onSearchChanged,
                onSubmitted: _find,
                onSearch: () => _find(_search.text),
                onPlace: _choosePlace,
              ),
            ),
          Positioned(
            right: 12,
            bottom: widget.request.readOnly ? 84 : 260,
            child: SafeArea(
              child: Column(
                children: [
                  if (!widget.request.readOnly)
                    FloatingActionButton.small(
                      heroTag: 'place-picker-gps',
                      onPressed: _useMyLocation,
                      tooltip: 'Моё местоположение',
                      child:
                          _locationState == _LocationUiState.requesting ||
                              _locationState == _LocationUiState.locating
                          ? const Padding(
                              padding: EdgeInsets.all(11),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                  if (_current != null) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'place-picker-recenter',
                      onPressed: () => _moveCamera(
                        GeoPoint(_current!.latitude, _current!.longitude),
                      ),
                      tooltip: 'Вернуться к моей точке',
                      child: const Icon(Icons.center_focus_strong_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: _SelectionPanel(
                request: widget.request,
                mode: _mode,
                label: _selectedLabel,
                reversing: _reversing,
                reverseError: _reverseError,
                submitError: _submitError,
                locationState: _locationState,
                permission: _permission,
                current: _current,
                exactBlocked: exactBlocked,
                onModeChanged: (mode) => setState(() {
                  _mode = mode;
                  _submitError = null;
                }),
                onOpenAppSettings: () =>
                    ref.read(locationProviderProvider).openAppSettings(),
                onOpenLocationSettings: () =>
                    ref.read(locationProviderProvider).openLocationSettings(),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: widget.request.readOnly ? 12 : 224,
            child: SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: .86),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.searching,
    required this.error,
    required this.results,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSearch,
    required this.onPlace,
  });

  final TextEditingController controller;
  final bool searching;
  final String? error;
  final List<MapPlace> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSearch;
  final ValueChanged<MapPlace> onPlace;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    borderRadius: BorderRadius.circular(AppRadii.md),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Город, улица или место',
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: onSearch,
                    tooltip: 'Найти',
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
          ),
        ),
        if (error case final message?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Align(alignment: Alignment.centerLeft, child: Text(message)),
          ),
        if (results.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final place = results[index];
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    place.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onPlace(place),
                );
              },
            ),
          ),
      ],
    ),
  );
}

class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({
    required this.request,
    required this.mode,
    required this.label,
    required this.reversing,
    required this.reverseError,
    required this.submitError,
    required this.locationState,
    required this.permission,
    required this.current,
    required this.exactBlocked,
    required this.onModeChanged,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final PlacePickerRequest request;
  final LocationPrivacyMode mode;
  final String? label;
  final bool reversing;
  final String? reverseError;
  final String? submitError;
  final _LocationUiState locationState;
  final LocationPermissionState? permission;
  final DeviceLocation? current;
  final bool exactBlocked;
  final ValueChanged<LocationPrivacyMode> onModeChanged;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _locationStatus(locationState, permission, current);
    return Material(
      elevation: 10,
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request.purpose == PlacePickerPurpose.signal)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<LocationPrivacyMode>(
                  segments: const [
                    ButtonSegment(
                      value: LocationPrivacyMode.none,
                      label: Text('Скрыто'),
                    ),
                    ButtonSegment(
                      value: LocationPrivacyMode.city,
                      label: Text('Город'),
                    ),
                    ButtonSegment(
                      value: LocationPrivacyMode.district,
                      label: Text('Район'),
                    ),
                    ButtonSegment(
                      value: LocationPrivacyMode.approximate,
                      label: Text('Зона'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (value) => onModeChanged(value.first),
                ),
              )
            else
              Row(
                children: [
                  const Icon(Icons.shield_rounded, color: AppColors.mint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.readOnly
                          ? 'Точка доступна только участникам комнаты'
                          : 'Точная точка — только после подтверждения в комнате',
                    ),
                  ),
                ],
              ),
            if (label != null || reversing) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reversing ? 'Определяем адрес…' : label!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (status != null) ...[
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: AppColors.muted)),
            ],
            if (reverseError != null) ...[
              const SizedBox(height: 6),
              Text(
                reverseError!,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (exactBlocked) ...[
              const SizedBox(height: 8),
              Text(
                'Точный обмен отключён: требуется защищённое HTTPS-соединение.',
                style: TextStyle(color: colors.error),
              ),
            ],
            if (submitError != null) ...[
              const SizedBox(height: 8),
              Text(submitError!, style: TextStyle(color: colors.error)),
            ],
            if (locationState == _LocationUiState.serviceDisabled) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: onOpenLocationSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Включить геолокацию'),
              ),
            ] else if (locationState == _LocationUiState.deniedForever ||
                locationState == _LocationUiState.restricted) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: onOpenAppSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Открыть настройки приложения'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _locationStatus(
  _LocationUiState state,
  LocationPermissionState? permission,
  DeviceLocation? current,
) {
  switch (state) {
    case _LocationUiState.idle:
      return 'GPS не запускается автоматически — нажми кнопку геопозиции.';
    case _LocationUiState.requesting:
      return 'Проверяем разрешение…';
    case _LocationUiState.locating:
      return 'Определяем текущее место…';
    case _LocationUiState.ready:
      final accuracy = current?.accuracyMeters.round();
      final precision =
          permission == LocationPermissionState.whileInUseApproximate
          ? 'Системная точность ограничена'
          : 'Точная геопозиция разрешена';
      return accuracy == null
          ? precision
          : '$precision · точность ±$accuracy м';
    case _LocationUiState.serviceDisabled:
      return 'Службы геолокации выключены на устройстве.';
    case _LocationUiState.denied:
      return 'Доступ к геопозиции не предоставлен. Можно выбрать место вручную.';
    case _LocationUiState.deniedForever:
      return 'Доступ запрещён в настройках. Можно выбрать место вручную.';
    case _LocationUiState.restricted:
      return 'Доступ ограничен системой или родительским контролем.';
    case _LocationUiState.timeout:
      return 'GPS не успел определить место. Попробуй ещё раз.';
    case _LocationUiState.unavailable:
      return 'Геопозиция сейчас недоступна. Выбери место вручную.';
  }
}

class _DemoMap extends StatelessWidget {
  const _DemoMap({required this.selected, required this.onTap});

  final GeoPoint? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ColoredBox(
      color: AppColors.ink,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF29264A), Color(0xFF173B3A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected == null ? Icons.map_outlined : Icons.location_pin,
                color: selected == null ? Colors.white70 : AppColors.coral,
                size: 52,
              ),
              const SizedBox(height: 10),
              Text(
                onTap == null
                    ? 'Демо-карта без сети'
                    : 'Демо-карта без сети\nНажми, чтобы выбрать тестовую точку',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
