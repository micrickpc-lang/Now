import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_provider.dart';
import '../../../core/network/realtime_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../map/domain/map_models.dart';
import '../../rooms/data/rooms_repository.dart';
import '../../social/data/social_repository.dart';
import '../data/exact_location_share_coordinator.dart';
import '../data/exact_location_shares_repository.dart';
import '../domain/exact_location_models.dart';

class ExactLocationMapScreen extends ConsumerStatefulWidget {
  const ExactLocationMapScreen({super.key});

  @override
  ConsumerState<ExactLocationMapScreen> createState() =>
      _ExactLocationMapScreenState();
}

class _ExactLocationMapScreenState
    extends ConsumerState<ExactLocationMapScreen> {
  MapLibreMapController? _mapController;
  final List<Circle> _markers = [];
  StreamSubscription<RealtimeEvent>? _events;
  Timer? _mapLoadDeadline;
  DeviceLocation? _current;
  List<ExactLocationShare> _mine = const [];
  List<VisibleExactLocation> _visible = const [];
  Object? _loadError;
  bool _loading = true;
  bool _locating = false;
  bool _styleReady = false;
  bool _mapLoadFailed = false;
  int _mapRevision = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    Future.microtask(() {
      _events = ref
          .read(realtimeCoordinatorProvider)
          .events
          .where((event) => event.type.startsWith('location.exact.'))
          .listen((_) => _reload());
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _mapLoadDeadline?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final config = ref.read(appConfigProvider);
    if (!config.canShareExactLocation) {
      if (mounted) {
        setState(() {
          _mine = const [];
          _visible = const [];
          _loadError = null;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final repository = ref.read(exactLocationShareRepositoryProvider);
      final mine = await repository.mine();
      final visible = await repository.visible();
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _visible = visible;
        _loadError = null;
        _loading = false;
      });
      await _syncMarkers();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
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
      _markers.clear();
      _styleReady = false;
      _mapLoadFailed = false;
      _mapRevision += 1;
    });
  }

  Future<void> _syncMarkers() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    try {
      for (final marker in _markers) {
        await controller.removeCircle(marker);
      }
      _markers.clear();
      for (final share in _mine) {
        _markers.add(
          await controller.addCircle(
            CircleOptions(
              geometry: LatLng(share.point.latitude, share.point.longitude),
              circleRadius: 10,
              circleColor: '#31C7A0',
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 3,
              circleOpacity: 1,
            ),
          ),
        );
      }
      for (final share in _visible) {
        _markers.add(
          await controller.addCircle(
            CircleOptions(
              geometry: LatLng(share.point.latitude, share.point.longitude),
              circleRadius: 9,
              circleColor: '#FF6B6B',
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 3,
              circleOpacity: 1,
            ),
          ),
        );
      }
      final current = _current;
      if (current != null) {
        _markers.add(
          await controller.addCircle(
            CircleOptions(
              geometry: LatLng(current.latitude, current.longitude),
              circleRadius: 7,
              circleColor: '#5B6CFF',
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 3,
              circleOpacity: 1,
            ),
          ),
        );
      }
    } catch (_) {
      // A style reload temporarily invalidates annotations.
    }
  }

  Future<void> _moveCamera(double latitude, double longitude) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(latitude, longitude), zoom: 15),
      ),
    );
  }

  Future<DeviceLocation?> _requestCurrentLocation() async {
    if (_locating) return null;
    setState(() => _locating = true);
    final location = ref.read(locationProviderProvider);
    try {
      if (!await location.isLocationServiceEnabled()) {
        if (mounted) _showLocationFailure(LocationFailureCode.serviceDisabled);
        return null;
      }
      var permission = await location.checkPermission();
      if (!permission.isGranted)
        permission = await location.requestPermission();
      if (!permission.isGranted) {
        if (mounted) {
          _showLocationFailure(
            permission == LocationPermissionState.deniedForever
                ? LocationFailureCode.permissionDeniedForever
                : permission == LocationPermissionState.restricted
                ? LocationFailureCode.restricted
                : LocationFailureCode.permissionDenied,
          );
        }
        return null;
      }
      final current = await location.getCurrentLocation();
      if (!mounted) return null;
      setState(() => _current = current);
      await _moveCamera(current.latitude, current.longitude);
      await _syncMarkers();
      return current;
    } on LocationFailure catch (error) {
      if (mounted) _showLocationFailure(error.code);
      return null;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showLocationFailure(LocationFailureCode code) {
    final location = ref.read(locationProviderProvider);
    final (message, action) = switch (code) {
      LocationFailureCode.serviceDisabled => (
        'Включи службы геолокации, чтобы продолжить.',
        SnackBarAction(
          label: 'Настройки',
          onPressed: () => location.openLocationSettings(),
        ),
      ),
      LocationFailureCode.permissionDeniedForever ||
      LocationFailureCode.restricted => (
        'Доступ к геолокации заблокирован в настройках системы.',
        SnackBarAction(
          label: 'Настройки',
          onPressed: () => location.openAppSettings(),
        ),
      ),
      LocationFailureCode.timeout => (
        'Не удалось получить геолокацию вовремя.',
        null,
      ),
      LocationFailureCode.unavailable => (
        'Геолокация временно недоступна.',
        null,
      ),
      LocationFailureCode.permissionDenied => (
        'Доступ к геолокации не предоставлен.',
        null,
      ),
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _createShare() async {
    final config = ref.read(appConfigProvider);
    if (!config.canShareExactLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Точная геолокация доступна только через защищённое HTTPS-соединение.',
          ),
        ),
      );
      return;
    }
    final draft = await showModalBottomSheet<_ExactShareDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ExactShareSheet(),
    );
    if (!mounted || draft == null) return;
    final current = await _requestCurrentLocation();
    if (!mounted || current == null) return;
    try {
      final share = await ref
          .read(exactLocationShareRepositoryProvider)
          .create(
            point: GeoPoint(current.latitude, current.longitude),
            audience: draft.audience,
            expiryMode: draft.expiryMode,
            explicitConsent: true,
            backgroundUpdatesEnabled: false,
            recipientIds: draft.recipientIds,
            circleId: draft.circleId,
            roomId: draft.roomId,
          );
      await ref.read(exactLocationShareCoordinatorProvider).start(share);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось начать передачу точной геолокации.'),
        ),
      );
    }
  }

  Future<void> _revoke(ExactLocationShare share) async {
    try {
      await ref
          .read(exactLocationShareCoordinatorProvider)
          .stop(share.id, suppressRevokeErrors: false);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS остановлен, но сервер не подтвердил отзыв доступа.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final initial = LatLng(
      config.initialMapLatitude,
      config.initialMapLongitude,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            tooltip: 'Обновить геолокации',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            key: ValueKey('exact-map-$_mapRevision'),
            styleString: config.mapStyleUrl,
            initialCameraPosition: CameraPosition(
              target: initial,
              zoom: config.initialMapZoom,
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
                });
              }
              unawaited(_syncMarkers());
            },
            compassEnabled: true,
            attributionButtonMargins: const math.Point(8, 72),
          ),
          if (!_styleReady)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.ink.withValues(alpha: .22),
                child: Center(
                  child: _mapLoadFailed
                      ? FilledButton.icon(
                          onPressed: _retryMap,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Повторить загрузку карты'),
                        )
                      : const SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              ),
            ),
          if (!config.canShareExactLocation)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _SecureTransportNotice(),
            ),
          Positioned(
            right: 16,
            bottom: 235,
            child: SafeArea(
              child: FloatingActionButton.small(
                onPressed: _locating ? null : _requestCurrentLocation,
                tooltip: 'Моё местоположение',
                child: _locating
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: .27,
            minChildSize: .22,
            maxChildSize: .62,
            builder: (context, controller) => _SharePanel(
              controller: controller,
              loading: _loading,
              error: _loadError,
              mine: _mine,
              visible: _visible,
              shareEnabled: config.canShareExactLocation,
              activeShareIds: ref
                  .watch(exactLocationShareCoordinatorProvider)
                  .activeShareIds,
              onShare: _createShare,
              onRevoke: _revoke,
              onRetry: _reload,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecureTransportNotice extends StatelessWidget {
  const _SecureTransportNotice();

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.ink.withValues(alpha: .92),
    child: const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.mint),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Точная геолокация отключена, пока устройство не использует защищённый адрес production-сервера.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SharePanel extends StatelessWidget {
  const _SharePanel({
    required this.controller,
    required this.loading,
    required this.error,
    required this.mine,
    required this.visible,
    required this.shareEnabled,
    required this.activeShareIds,
    required this.onShare,
    required this.onRevoke,
    required this.onRetry,
  });

  final ScrollController controller;
  final bool loading;
  final Object? error;
  final List<ExactLocationShare> mine;
  final List<VisibleExactLocation> visible;
  final bool shareEnabled;
  final Set<String> activeShareIds;
  final VoidCallback onShare;
  final ValueChanged<ExactLocationShare> onRevoke;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppRadii.md),
    ),
    clipBehavior: Clip.antiAlias,
    child: ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.muted.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Точная геолокация',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            FilledButton.icon(
              onPressed: shareEnabled ? onShare : null,
              icon: const Icon(Icons.share_location_rounded),
              label: const Text('Поделиться'),
            ),
          ],
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_off_rounded),
            title: const Text('Не удалось обновить геолокации.'),
            trailing: IconButton(
              onPressed: onRetry,
              tooltip: 'Повторить',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
        if (!loading && error == null && mine.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.location_disabled_outlined),
            title: Text('Ты не делишься точной геолокацией.'),
          ),
        for (final share in mine)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: AppColors.mint,
              child: Icon(Icons.navigation_rounded, color: AppColors.ink),
            ),
            title: Text(share.audienceSummary.label),
            subtitle: Text(
              '${share.audienceSummary.viewerCount} зрителей · ${_expiryLabel(share)}',
            ),
            trailing: IconButton(
              onPressed: () => onRevoke(share),
              tooltip: 'Остановить передачу',
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ),
        if (visible.isNotEmpty) ...[
          const Divider(height: 28),
          Text('Видно тебе', style: Theme.of(context).textTheme.titleMedium),
          for (final share in visible)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.coral.withValues(alpha: .2),
                child: Text(share.ownerEmoji ?? '•'),
              ),
              title: Text(share.ownerName),
              subtitle: Text(_visibleExpiryLabel(share)),
            ),
        ],
      ],
    ),
  );
}

String _expiryLabel(ExactLocationShare share) {
  if (share.expiresAt == null) return 'Пока не остановишь';
  return 'До ${_timeLabel(share.expiresAt!)}';
}

String _visibleExpiryLabel(VisibleExactLocation share) {
  if (share.expiresAt == null) return 'Пока не остановит владелец';
  return 'До ${_timeLabel(share.expiresAt!)}';
}

String _timeLabel(DateTime value) {
  final minutes = value.difference(DateTime.now()).inMinutes;
  if (minutes <= 0) return 'сейчас';
  if (minutes < 60) return 'через $minutes мин';
  return 'через ${(minutes / 60).ceil()} ч';
}

class _ExactShareDraft {
  const _ExactShareDraft({
    required this.audience,
    required this.expiryMode,
    required this.recipientIds,
    this.circleId,
    this.roomId,
  });

  final ExactLocationAudience audience;
  final ExactLocationExpiry expiryMode;
  final List<String> recipientIds;
  final String? circleId;
  final String? roomId;
}

class _ExactShareSheet extends ConsumerStatefulWidget {
  const _ExactShareSheet();

  @override
  ConsumerState<_ExactShareSheet> createState() => _ExactShareSheetState();
}

class _ExactShareSheetState extends ConsumerState<_ExactShareSheet> {
  ExactLocationAudience _audience = ExactLocationAudience.selectedFriends;
  ExactLocationExpiry _expiryMode = ExactLocationExpiry.thirtyMinutes;
  final Set<String> _recipientIds = {};
  String? _circleId;
  String? _roomId;
  bool _consent = false;

  bool get _targetSelected => switch (_audience) {
    ExactLocationAudience.selectedFriends => _recipientIds.isNotEmpty,
    ExactLocationAudience.circle => _circleId != null,
    ExactLocationAudience.room => _roomId != null,
  };

  void _setAudience(ExactLocationAudience audience) {
    setState(() {
      _audience = audience;
      if (audience != ExactLocationAudience.room &&
          _expiryMode == ExactLocationExpiry.meetingEnd) {
        _expiryMode = ExactLocationExpiry.thirtyMinutes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final circles = ref.watch(circlesProvider);
    final rooms = ref.watch(activeRoomsProvider);
    final enabled = _consent && _targetSelected;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Поделиться точной геолокацией',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Выбери, кто именно сможет видеть эту точку.'),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ExactLocationAudience>(
                  segments: const [
                    ButtonSegment(
                      value: ExactLocationAudience.selectedFriends,
                      label: Text('Друзья'),
                      icon: Icon(Icons.people_outline_rounded),
                    ),
                    ButtonSegment(
                      value: ExactLocationAudience.circle,
                      label: Text('Круг'),
                      icon: Icon(Icons.groups_2_outlined),
                    ),
                    ButtonSegment(
                      value: ExactLocationAudience.room,
                      label: Text('Комната'),
                      icon: Icon(Icons.forum_outlined),
                    ),
                  ],
                  selected: {_audience},
                  onSelectionChanged: (value) => _setAudience(value.first),
                ),
              ),
              const SizedBox(height: 12),
              switch (_audience) {
                ExactLocationAudience.selectedFriends => friends.when(
                  data: (items) => items.isEmpty
                      ? const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.person_off_outlined),
                          title: Text('Нет доступных взаимных друзей.'),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 190),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final friend in items)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _recipientIds.contains(friend.id),
                                  title: Text(friend.name),
                                  secondary: CircleAvatar(
                                    child: Text(friend.emoji ?? '•'),
                                  ),
                                  onChanged: (selected) => setState(() {
                                    if (selected == true) {
                                      _recipientIds.add(friend.id);
                                    } else {
                                      _recipientIds.remove(friend.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Друзья недоступны.'),
                ),
                ExactLocationAudience.circle => circles.when(
                  data: (items) => DropdownButtonFormField<String>(
                    initialValue: _circleId,
                    decoration: const InputDecoration(labelText: 'Круг'),
                    items: items
                        .map(
                          (circle) => DropdownMenuItem(
                            value: circle.id,
                            child: Text(
                              '${circle.emoji ?? '•'} ${circle.name}',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setState(() => _circleId = value),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Круги недоступны.'),
                ),
                ExactLocationAudience.room => rooms.when(
                  data: (items) => DropdownButtonFormField<String>(
                    initialValue: _roomId,
                    decoration: const InputDecoration(
                      labelText: 'Активная комната',
                    ),
                    items: items
                        .map(
                          (room) => DropdownMenuItem(
                            value: room.id,
                            child: Text(room.title),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setState(() => _roomId = value),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Активные комнаты недоступны.'),
                ),
              },
              const SizedBox(height: 20),
              Text('Срок', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ExactLocationExpiry>(
                  segments: [
                    const ButtonSegment(
                      value: ExactLocationExpiry.thirtyMinutes,
                      label: Text('30 min'),
                    ),
                    const ButtonSegment(
                      value: ExactLocationExpiry.oneHour,
                      label: Text('1 час'),
                    ),
                    if (_audience == ExactLocationAudience.room)
                      const ButtonSegment(
                        value: ExactLocationExpiry.meetingEnd,
                        label: Text('До конца комнаты'),
                      ),
                    const ButtonSegment(
                      value: ExactLocationExpiry.manual,
                      label: Text('Пока не остановлю'),
                    ),
                  ],
                  selected: {_expiryMode},
                  onSelectionChanged: (value) =>
                      setState(() => _expiryMode = value.first),
                ),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                title: const Text(
                  'Подтверждаю передачу моей точной геолокации.',
                ),
                subtitle: const Text(
                  'Выбранные выше получатели и срок применятся к этой передаче.',
                ),
                onChanged: (value) => setState(() => _consent = value ?? false),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.phone_android_outlined),
                title: Text('Только обновления на экране'),
                subtitle: Text(
                  'Фоновая геолокация требует отдельного разрешения устройства и сейчас выключена.',
                ),
                trailing: Switch(value: false, onChanged: null),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: enabled
                      ? () => Navigator.pop(
                          context,
                          _ExactShareDraft(
                            audience: _audience,
                            expiryMode: _expiryMode,
                            recipientIds: _recipientIds.toList(growable: false),
                            circleId: _audience == ExactLocationAudience.circle
                                ? _circleId
                                : null,
                            roomId: _audience == ExactLocationAudience.room
                                ? _roomId
                                : null,
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.share_location_rounded),
                  label: const Text('Начать передачу'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
