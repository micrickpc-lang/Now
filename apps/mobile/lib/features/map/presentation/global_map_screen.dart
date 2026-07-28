import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/realtime_client.dart';
import '../../social/data/social_repository.dart';
import '../data/location_sharing_repository.dart';

class GlobalMapScreen extends ConsumerStatefulWidget {
  const GlobalMapScreen({super.key});

  @override
  ConsumerState<GlobalMapScreen> createState() => _GlobalMapScreenState();
}

class _GlobalMapScreenState extends ConsumerState<GlobalMapScreen> {
  MapLibreMapController? _controller;
  final Map<String, FriendLocation> _friendByCircleId = {};
  bool _styleReady = false;
  bool _gettingLocation = false;
  Position? _myPosition;
  String? _activeShareId;
  String? _markerSignature;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = ref
        .read(realtimeCoordinatorProvider)
        .events
        .listen(_onRealtimeEvent);
  }

  @override
  void dispose() {
    unawaited(_realtimeSubscription?.cancel());
    _controller?.onCircleTapped.remove(_onCircleTapped);
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (!{
      'location.share.available',
      'location.updated',
      'location.access.revoked',
      'location.share.revoked',
    }.contains(event.type)) {
      return;
    }
    ref.invalidate(friendLocationsProvider);
    ref.invalidate(activeLocationSharesProvider);
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    final locations = ref.read(friendLocationsProvider).value ?? const [];
    await _renderMarkers(locations);
  }

  Future<void> _renderMarkers(List<FriendLocation> friends) async {
    final controller = _controller;
    if (!_styleReady || controller == null) return;
    final signature = [
      for (final friend in friends)
        '${friend.userId}:${friend.latitude}:${friend.longitude}:${friend.expiresAt.millisecondsSinceEpoch}',
      if (_myPosition != null)
        'me:${_myPosition!.latitude}:${_myPosition!.longitude}',
    ].join('|');
    if (signature == _markerSignature) return;
    _markerSignature = signature;
    _friendByCircleId.clear();
    await controller.clearCircles();
    if (_myPosition != null) {
      await controller.addCircle(
        CircleOptions(
          geometry: LatLng(_myPosition!.latitude, _myPosition!.longitude),
          circleRadius: 9,
          circleColor: '#1783D1',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
        {'kind': 'self'},
      );
    }
    for (final friend in friends) {
      final circle = await controller.addCircle(
        CircleOptions(
          geometry: LatLng(friend.latitude, friend.longitude),
          circleRadius: friend.precision == LocationPrecision.exact ? 10 : 15,
          circleColor: friend.precision == LocationPrecision.exact
              ? '#F05C4D'
              : '#D49724',
          circleOpacity: .94,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
        {'userId': friend.userId},
      );
      _friendByCircleId[circle.id] = friend;
    }
  }

  bool _onCircleTapped(Circle circle) {
    final friend = _friendByCircleId[circle.id];
    if (friend == null) return false;
    unawaited(_showFriendSheet(friend));
    return true;
  }

  Future<void> _showFriendSheet(FriendLocation friend) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Text(friend.emoji ?? friend.name[0])),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        friend.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  friend.precision == LocationPrecision.exact
                      ? 'Exact location'
                      : 'Approximate location',
                ),
                const SizedBox(height: 4),
                Text('Available until ${_clock(friend.expiresAt)}'),
              ],
            ),
          ),
        ),
      );

  Future<Position?> _refreshOwnLocation({bool moveCamera = true}) async {
    if (_gettingLocation) return null;
    setState(() => _gettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage('Location services are turned off.');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Location permission is required to share your location.');
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await ref
          .read(locationSharingRepositoryProvider)
          .updateLocation(
            latitude: position.latitude,
            longitude: position.longitude,
          );
      if (!mounted) return null;
      setState(() {
        _myPosition = position;
        _markerSignature = null;
      });
      await _renderMarkers(ref.read(friendLocationsProvider).value ?? const []);
      if (moveCamera) {
        await _controller?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            14,
          ),
        );
      }
      return position;
    } catch (_) {
      if (mounted) _showMessage('Unable to update your location.');
      return null;
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _showShareSheet() async {
    final draft = await showModalBottomSheet<_ShareDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _LocationShareSheet(),
    );
    if (draft == null || !mounted) return;
    final position = await _refreshOwnLocation(moveCamera: false);
    if (position == null || !mounted) return;
    try {
      final share = await ref
          .read(locationSharingRepositoryProvider)
          .createShare(
            audience: draft.audience,
            precision: draft.precision,
            ttl: draft.ttl,
            explicitExactConsent: draft.explicitExactConsent,
            recipientIds: draft.recipientIds,
          );
      if (!mounted) return;
      setState(() => _activeShareId = share.id);
      ref.invalidate(activeLocationSharesProvider);
      ref.invalidate(friendLocationsProvider);
      _showMessage(
        'Location sharing is active until ${_clock(share.expiresAt)}.',
      );
    } catch (_) {
      if (mounted) _showMessage('Unable to start location sharing.');
    }
  }

  Future<void> _revokeShare(String shareId) async {
    try {
      await ref.read(locationSharingRepositoryProvider).revokeShare(shareId);
      if (!mounted) return;
      setState(() => _activeShareId = null);
      ref.invalidate(activeLocationSharesProvider);
      ref.invalidate(friendLocationsProvider);
      _showMessage('Location sharing stopped.');
    } catch (_) {
      if (mounted) _showMessage('Unable to stop location sharing.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final friends = ref.watch(friendLocationsProvider);
    final shares = ref.watch(activeLocationSharesProvider);
    final activeShares = shares.value ?? const <LocationShare>[];
    final activeShareId =
        _activeShareId ?? (activeShares.isEmpty ? null : activeShares.first.id);
    friends.whenData((locations) => unawaited(_renderMarkers(locations)));

    return Scaffold(
      body: Stack(
        children: [
          MapLibreMap(
            styleString: '${config.apiBaseUrl}/maps/style.json',
            initialCameraPosition: const CameraPosition(
              target: LatLng(0, 0),
              zoom: 1,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            compassEnabled: true,
            myLocationEnabled: false,
            attributionButtonMargins: const Point(8, 72),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        'Map',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: activeShareId == null
                        ? 'Share location'
                        : 'Stop sharing location',
                    onPressed: _gettingLocation
                        ? null
                        : () => activeShareId == null
                              ? _showShareSheet()
                              : _revokeShare(activeShareId),
                    icon: Icon(
                      activeShareId == null
                          ? Icons.share_location_outlined
                          : Icons.location_disabled_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 124,
            child: FloatingActionButton.small(
              tooltip: 'Use my location',
              onPressed: _gettingLocation ? null : _refreshOwnLocation,
              child: _gettingLocation
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: SafeArea(
              top: false,
              child: _FriendStrip(
                locations: friends.value ?? const [],
                loading: friends.isLoading,
                onTap: _showFriendSheet,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendStrip extends StatelessWidget {
  const _FriendStrip({
    required this.locations,
    required this.loading,
    required this.onTap,
  });

  final List<FriendLocation> locations;
  final bool loading;
  final ValueChanged<FriendLocation> onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      height: 72,
      child: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : locations.isEmpty
          ? const Center(child: Text('No friends are sharing a location.'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: locations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final friend = locations[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onTap(friend),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          child: Text(friend.emoji ?? friend.name[0]),
                        ),
                        const SizedBox(width: 7),
                        Text(friend.name),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}

class _ShareDraft {
  const _ShareDraft({
    required this.audience,
    required this.precision,
    required this.ttl,
    required this.explicitExactConsent,
    required this.recipientIds,
  });

  final LocationAudience audience;
  final LocationPrecision precision;
  final Duration ttl;
  final bool explicitExactConsent;
  final List<String> recipientIds;
}

class _LocationShareSheet extends ConsumerStatefulWidget {
  const _LocationShareSheet();

  @override
  ConsumerState<_LocationShareSheet> createState() =>
      _LocationShareSheetState();
}

class _LocationShareSheetState extends ConsumerState<_LocationShareSheet> {
  LocationAudience _audience = LocationAudience.friends;
  LocationPrecision _precision = LocationPrecision.approximate;
  Duration _ttl = const Duration(minutes: 30);
  bool _exactConsent = false;
  final Set<String> _recipientIds = {};

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider).value ?? const <FriendModel>[];
    final canShare =
        (_audience == LocationAudience.friends || _recipientIds.isNotEmpty) &&
        (_precision != LocationPrecision.exact || _exactConsent);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share location',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<LocationAudience>(
                segments: const [
                  ButtonSegment(
                    value: LocationAudience.friends,
                    label: Text('Friends'),
                  ),
                  ButtonSegment(
                    value: LocationAudience.selected,
                    label: Text('Selected'),
                  ),
                ],
                selected: {_audience},
                onSelectionChanged: (value) =>
                    setState(() => _audience = value.first),
              ),
              if (_audience == LocationAudience.selected) ...[
                const SizedBox(height: 10),
                for (final friend in friends)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _recipientIds.contains(friend.id),
                    title: Text(friend.name),
                    secondary: CircleAvatar(
                      child: Text(friend.emoji ?? friend.name[0]),
                    ),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _recipientIds.add(friend.id);
                      } else {
                        _recipientIds.remove(friend.id);
                      }
                    }),
                  ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<LocationPrecision>(
                initialValue: _precision,
                decoration: const InputDecoration(labelText: 'Precision'),
                items: const [
                  DropdownMenuItem(
                    value: LocationPrecision.approximate,
                    child: Text('Approximate'),
                  ),
                  DropdownMenuItem(
                    value: LocationPrecision.exact,
                    child: Text('Exact'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _precision = value ?? LocationPrecision.approximate;
                  if (_precision != LocationPrecision.exact)
                    _exactConsent = false;
                }),
              ),
              if (_precision == LocationPrecision.exact)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _exactConsent,
                  title: const Text('I consent to share my exact location.'),
                  onChanged: (value) =>
                      setState(() => _exactConsent = value ?? false),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Duration>(
                initialValue: _ttl,
                decoration: const InputDecoration(labelText: 'Expires after'),
                items: const [
                  DropdownMenuItem(
                    value: Duration(minutes: 15),
                    child: Text('15 minutes'),
                  ),
                  DropdownMenuItem(
                    value: Duration(minutes: 30),
                    child: Text('30 minutes'),
                  ),
                  DropdownMenuItem(
                    value: Duration(minutes: 60),
                    child: Text('1 hour'),
                  ),
                ],
                onChanged: (value) => setState(() => _ttl = value ?? _ttl),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: !canShare
                      ? null
                      : () => Navigator.pop(
                          context,
                          _ShareDraft(
                            audience: _audience,
                            precision: _precision,
                            ttl: _ttl,
                            explicitExactConsent: _exactConsent,
                            recipientIds: _recipientIds.toList(growable: false),
                          ),
                        ),
                  child: const Text('Start sharing'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _clock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
