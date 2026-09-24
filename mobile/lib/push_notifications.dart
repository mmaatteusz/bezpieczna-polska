import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'model.dart';
import 'app_version.dart';

enum PushPermissionState { notDetermined, denied, authorized, provisional }

abstract class PushPlatformAdapter {
  String get platform;
  bool get supported;
  Future<PushPermissionState> permissionState();
  Future<PushPermissionState> requestPermission();
  Future<String?> token();
  Stream<String> get tokenChanges;
}

abstract class PushSecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecurePushSecretStore implements PushSecretStore {
  static const _key = 'push_manage_secret_v1';
  final FlutterSecureStorage storage;

  SecurePushSecretStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => storage.read(key: _key);

  @override
  Future<void> write(String value) => storage.write(key: _key, value: value);

  @override
  Future<void> delete() => storage.delete(key: _key);
}

class FirebasePushPlatformAdapter implements PushPlatformAdapter {
  final FirebaseMessaging messaging;
  @override
  final String platform;

  FirebasePushPlatformAdapter._(this.messaging, this.platform);

  static Future<FirebasePushPlatformAdapter?> fromBuildConfiguration() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
    const iosBundleId = String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'pl.bezpiecznapolska.bezpiecznaPolska',
    );
    final appId = defaultTargetPlatform == TargetPlatform.iOS
        ? iosAppId
        : androidAppId;
    if ([apiKey, projectId, senderId, appId].any((value) => value.isEmpty)) {
      return null;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: senderId,
          projectId: projectId,
          iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
              ? iosBundleId
              : null,
        ),
      );
    }
    final messaging = FirebaseMessaging.instance;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    return FirebasePushPlatformAdapter._(
      messaging,
      defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
    );
  }

  PushPermissionState _permission(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized => PushPermissionState.authorized,
        AuthorizationStatus.provisional => PushPermissionState.provisional,
        AuthorizationStatus.denied => PushPermissionState.denied,
        AuthorizationStatus.deniedPermanently => PushPermissionState.denied,
        AuthorizationStatus.notDetermined => PushPermissionState.notDetermined,
      };

  @override
  bool get supported => true;

  @override
  Future<PushPermissionState> permissionState() async => _permission(
    (await messaging.getNotificationSettings()).authorizationStatus,
  );

  @override
  Future<PushPermissionState> requestPermission() async => _permission(
    (await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: false,
    )).authorizationStatus,
  );

  @override
  Future<String?> token() =>
      platform == 'IOS' ? messaging.getAPNSToken() : messaging.getToken();

  @override
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh
      .asyncMap(
        (fcmToken) async => platform == 'IOS'
            ? (await messaging.getAPNSToken()) ?? ''
            : fcmToken,
      )
      .where((value) => value.isNotEmpty);
}

@immutable
class PushPreferences {
  final bool criticalPoland;
  final bool regionAlerts;
  final bool watchedLocations;
  final bool cyber;
  final bool border;
  final bool ukraine;

  const PushPreferences({
    this.criticalPoland = true,
    this.regionAlerts = true,
    this.watchedLocations = false,
    this.cyber = true,
    this.border = true,
    this.ukraine = false,
  });

  PushPreferences copyWith({
    bool? criticalPoland,
    bool? regionAlerts,
    bool? watchedLocations,
    bool? cyber,
    bool? border,
    bool? ukraine,
  }) => PushPreferences(
    criticalPoland: criticalPoland ?? this.criticalPoland,
    regionAlerts: regionAlerts ?? this.regionAlerts,
    watchedLocations: watchedLocations ?? this.watchedLocations,
    cyber: cyber ?? this.cyber,
    border: border ?? this.border,
    ukraine: ukraine ?? this.ukraine,
  );

  factory PushPreferences.fromJson(dynamic value) {
    if (value is! Map) return const PushPreferences();
    bool read(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    return PushPreferences(
      criticalPoland: read('criticalPoland', true),
      regionAlerts: read('regionAlerts', true),
      watchedLocations: read('watchedLocations', false),
      cyber: read('cyber', true),
      border: read('border', true),
      ukraine: read('ukraine', false),
    );
  }

  Map<String, dynamic> toJson() => {
    'criticalPoland': criticalPoland,
    'regionAlerts': regionAlerts,
    'watchedLocations': watchedLocations,
    'cyber': cyber,
    'border': border,
    'ukraine': ukraine,
  };
}

@immutable
class PushRegistrationState {
  final PushPermissionState permission;
  final bool configured;
  final bool registered;
  final bool tokenAvailable;
  final bool backendReachable;
  final bool providerReady;
  final String? error;

  const PushRegistrationState({
    this.permission = PushPermissionState.notDetermined,
    this.configured = false,
    this.registered = false,
    this.tokenAvailable = false,
    this.backendReachable = true,
    this.providerReady = false,
    this.error,
  });

  PushRegistrationState copyWith({
    PushPermissionState? permission,
    bool? configured,
    bool? registered,
    bool? tokenAvailable,
    bool? backendReachable,
    bool? providerReady,
    String? error,
    bool clearError = false,
  }) => PushRegistrationState(
    permission: permission ?? this.permission,
    configured: configured ?? this.configured,
    registered: registered ?? this.registered,
    tokenAvailable: tokenAvailable ?? this.tokenAvailable,
    backendReachable: backendReachable ?? this.backendReachable,
    providerReady: providerReady ?? this.providerReady,
    error: clearError ? null : error ?? this.error,
  );
}

class PushManager extends ChangeNotifier {
  static const _installationKey = 'push_installation_id_v1';
  static const _legacySecretKey = 'push_manage_secret_v1';
  static const _registeredKey = 'push_registered_v1';
  static const _preferencesKey = 'push_preferences_v1';
  static const _appVersion = appVersion;

  final DataRepository repository;
  final PushPlatformAdapter? adapter;
  final PushSecretStore secretStore;
  PushRegistrationState _state;
  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;

  PushManager(this.repository, this.adapter, {PushSecretStore? secretStore})
    : secretStore = secretStore ?? SecurePushSecretStore(),
      _state = PushRegistrationState(
        configured: adapter?.supported ?? false,
        registered: repository.prefs.getBool(_registeredKey) ?? false,
        backendReachable: repository.api.isNotEmpty,
      );

  PushRegistrationState get state => _state;
  PushPreferences get preferences {
    try {
      final raw = repository.prefs.getString(_preferencesKey);
      return raw == null
          ? const PushPreferences()
          : PushPreferences.fromJson(jsonDecode(raw));
    } catch (_) {
      return const PushPreferences();
    }
  }

  void _setState(PushRegistrationState value) {
    _state = value;
    notifyListeners();
  }

  String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }

  String _randomSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return 'bp_push_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  Future<({String id, String secret})> _identity() async {
    var id = repository.prefs.getString(_installationKey);
    var secret = await secretStore.read();

    // One-way migration from pre-hardening builds. The plaintext legacy copy is
    // deleted as soon as it has been committed to platform secure storage.
    final legacySecret = repository.prefs.getString(_legacySecretKey);
    if (secret == null &&
        legacySecret != null &&
        RegExp(r'^bp_push_[A-Za-z0-9_-]{43}$').hasMatch(legacySecret)) {
      secret = legacySecret;
      await secretStore.write(secret);
      await repository.prefs.remove(_legacySecretKey);
    }

    final validId =
        id != null &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(id);
    final validSecret =
        secret != null &&
        RegExp(r'^bp_push_[A-Za-z0-9_-]{43}$').hasMatch(secret);
    if (!validId || !validSecret) {
      id = _randomId();
      secret = _randomSecret();
      await repository.prefs.setString(_installationKey, id);
      await secretStore.write(secret);
      await repository.prefs.remove(_legacySecretKey);
      await repository.prefs.setBool(_registeredKey, false);
    }
    return (id: id, secret: secret);
  }

  Uri _uri(String suffix) {
    if (repository.api.isEmpty) {
      throw const ApiFailure(ApiFailureKind.notConfigured);
    }
    final base = DataRepository.validateApi(repository.api);
    return base.replace(
      path: '${base.path}$suffix',
      query: null,
      fragment: null,
    );
  }

  Map<String, dynamic> _apiPreferences(PushPreferences prefs) => {
    ...prefs.toJson(),
    'regionId': prefs.regionAlerts ? repository.region : null,
    'locations': prefs.watchedLocations
        ? repository.watchedLocations
              .map(
                (location) => {
                  'id': location.id,
                  'label': location.label,
                  'latitude': location.latitude,
                  'longitude': location.longitude,
                  'radiusKm': location.radiusKm,
                  'regionId': location.regionId,
                },
              )
              .toList()
        : <Map<String, dynamic>>[],
  };

  Map<String, String> _headers(String secret) => {
    'authorization': 'Bearer $secret',
    'content-type': 'application/json; charset=utf-8',
  };

  Future<dynamic> _jsonRequest(
    String method,
    Uri uri,
    String secret, {
    Object? body,
  }) async {
    final future = switch (method) {
      'POST' => repository.client.post(
        uri,
        headers: _headers(secret),
        body: jsonEncode(body),
      ),
      'PUT' => repository.client.put(
        uri,
        headers: _headers(secret),
        body: jsonEncode(body),
      ),
      'DELETE' => repository.client.delete(uri, headers: _headers(secret)),
      _ => repository.client.get(uri, headers: _headers(secret)),
    };
    final request = await future.timeout(const Duration(seconds: 8));
    if (request.statusCode < 200 || request.statusCode >= 300) {
      throw ApiFailure(
        request.statusCode == 503
            ? ApiFailureKind.server
            : request.statusCode == 401
            ? ApiFailureKind.invalidResponse
            : ApiFailureKind.network,
      );
    }
    if (request.bodyBytes.length > 128 * 1024) {
      throw const ApiFailure(ApiFailureKind.invalidResponse);
    }
    return request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(utf8.decode(request.bodyBytes));
  }

  bool _permissionAllows(PushPermissionState value) =>
      value == PushPermissionState.authorized ||
      value == PushPermissionState.provisional;

  Future<void> initializeWithoutPrompt() async {
    if (_initialized) return;
    _initialized = true;
    if (adapter == null || !adapter!.supported) {
      _setState(_state.copyWith(configured: false));
      return;
    }
    _tokenSubscription = adapter!.tokenChanges.listen((token) {
      if (_state.registered && _permissionAllows(_state.permission)) {
        unawaited(_registerToken(token, update: true));
      }
    });
    try {
      final permission = await adapter!.permissionState();
      _setState(
        _state.copyWith(
          configured: true,
          permission: permission,
          clearError: true,
        ),
      );
      if (_state.registered && _permissionAllows(permission)) {
        final currentToken = await adapter!.token();
        if (currentToken != null && currentToken.isNotEmpty) {
          await _registerToken(currentToken, update: true);
        } else {
          _setState(_state.copyWith(tokenAvailable: false));
        }
      } else if (_state.registered) {
        await refreshStatus();
      }
    } catch (_) {
      _setState(
        _state.copyWith(
          backendReachable: false,
          error: 'Nie udało się odświeżyć stanu powiadomień.',
        ),
      );
    }
  }

  Future<void> refreshForSettings() async {
    await initializeWithoutPrompt();
    if (_state.registered) {
      try {
        await refreshStatus();
      } catch (_) {}
    }
  }

  Future<void> enable() async {
    if (adapter == null || !adapter!.supported) {
      _setState(
        _state.copyWith(
          configured: false,
          error: 'Push nie jest skonfigurowany w tym buildzie.',
        ),
      );
      return;
    }
    final permission = await adapter!.requestPermission();
    _setState(
      _state.copyWith(
        configured: true,
        permission: permission,
        clearError: true,
      ),
    );
    if (!_permissionAllows(permission)) return;
    final currentToken = await adapter!.token();
    if (currentToken == null || currentToken.isEmpty) {
      _setState(
        _state.copyWith(
          tokenAvailable: false,
          error: 'System nie udostępnił jeszcze tokenu powiadomień.',
        ),
      );
      return;
    }
    await _registerToken(currentToken, update: _state.registered);
  }

  Future<void> _registerToken(String token, {required bool update}) async {
    final identity = await _identity();
    final prefs = preferences;
    final payload = {
      'installationId': identity.id,
      'platform': adapter!.platform,
      'token': token,
      'appVersion': _appVersion,
      'language': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
      'preferences': _apiPreferences(prefs),
    };
    try {
      final result = Map<String, dynamic>.from(
        await _jsonRequest(
              update ? 'PUT' : 'POST',
              _uri(
                update ? '/v1/push/devices/${identity.id}' : '/v1/push/devices',
              ),
              identity.secret,
              body: update
                  ? (Map<String, dynamic>.from(payload)
                      ..remove('installationId'))
                  : payload,
            )
            as Map,
      );
      await repository.prefs.setBool(_registeredKey, true);
      _setState(
        _state.copyWith(
          registered: true,
          tokenAvailable: true,
          backendReachable: true,
          providerReady: result['providerReady'] == true,
          clearError: true,
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          tokenAvailable: true,
          backendReachable: false,
          error: apiFailureMessage(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> refreshStatus() async {
    if (!(repository.prefs.getBool(_registeredKey) ?? false)) {
      _setState(_state.copyWith(registered: false, clearError: true));
      return;
    }
    final identity = await _identity();
    try {
      final result = Map<String, dynamic>.from(
        await _jsonRequest(
              'GET',
              _uri('/v1/push/devices/${identity.id}'),
              identity.secret,
            )
            as Map,
      );
      final registered = result['registered'] == true;
      await repository.prefs.setBool(_registeredKey, registered);
      _setState(
        _state.copyWith(
          registered: registered,
          backendReachable: true,
          providerReady: result['providerReady'] == true,
          clearError: true,
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          backendReachable: false,
          error: apiFailureMessage(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> setPreferences(PushPreferences value) async {
    await repository.prefs.setString(
      _preferencesKey,
      jsonEncode(value.toJson()),
    );
    notifyListeners();
    if (!_state.registered) return;
    final identity = await _identity();
    try {
      await _jsonRequest(
        'PUT',
        _uri('/v1/push/devices/${identity.id}/preferences'),
        identity.secret,
        body: _apiPreferences(value),
      );
      _setState(_state.copyWith(backendReachable: true, clearError: true));
    } catch (error) {
      _setState(
        _state.copyWith(
          backendReachable: false,
          error: apiFailureMessage(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> syncCurrentPreferences() async {
    if (!_state.registered) return;
    try {
      await setPreferences(preferences);
    } catch (_) {}
  }

  Future<void> unregister() async {
    if (!_state.registered) return;
    final identity = await _identity();
    try {
      await _jsonRequest(
        'DELETE',
        _uri('/v1/push/devices/${identity.id}'),
        identity.secret,
      );
      await repository.prefs.setBool(_registeredKey, false);
      await repository.prefs.remove(_installationKey);
      await repository.prefs.remove(_legacySecretKey);
      await secretStore.delete();
      _setState(
        _state.copyWith(
          registered: false,
          tokenAvailable: false,
          backendReachable: true,
          providerReady: false,
          clearError: true,
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          backendReachable: false,
          error: apiFailureMessage(error),
        ),
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    unawaited(_tokenSubscription?.cancel());
    super.dispose();
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  final PushManager manager;
  const NotificationSettingsScreen({super.key, required this.manager});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool busy = false;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_changed);
    unawaited(widget.manager.refreshForSettings());
  }

  @override
  void dispose() {
    widget.manager.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _enable() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Włączyć powiadomienia?'),
        content: const Text(
          'Dopiero po kontynuowaniu pojawi się systemowa prośba o zgodę. Wybrane kategorie zostaną zapisane dla tego urządzenia. Obserwowane lokalizacje są wysyłane tylko wtedy, gdy osobno włączysz tę kategorię; aplikacja działa bez historii GPS i nie zapisuje historii przemieszczania.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Nie teraz'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Kontynuuj'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.manager.enable();
    } catch (_) {
      // Stan managera zawiera komunikat dla użytkownika.
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => busy = true);
    try {
      await widget.manager.refreshForSettings();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _update(PushPreferences value) async {
    setState(() => busy = true);
    try {
      await widget.manager.setPreferences(value);
    } catch (_) {
      // Lokalny wybór zostaje zachowany; stan usługi jest pokazany wyżej.
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get _permissionText => switch (widget.manager.state.permission) {
    PushPermissionState.authorized => 'Zgoda systemowa: przyznana',
    PushPermissionState.provisional => 'Zgoda systemowa: tymczasowa',
    PushPermissionState.denied => 'Zgoda systemowa: odmówiona',
    PushPermissionState.notDetermined => 'Zgoda systemowa: jeszcze nie pytano',
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.manager.state, prefs = widget.manager.preferences;
    final permissionGranted =
        state.permission == PushPermissionState.authorized ||
        state.permission == PushPermissionState.provisional;
    final registered = state.registered && permissionGranted;
    final deliveryReady =
        registered && state.providerReady && state.backendReachable;

    final title = !state.configured
        ? 'Powiadomienia niedostępne w tej wersji'
        : !state.backendReachable
        ? 'Nie można potwierdzić działania powiadomień'
        : state.permission == PushPermissionState.denied
        ? 'Powiadomienia zablokowane w systemie'
        : deliveryReady
        ? 'Powiadomienia gotowe'
        : registered
        ? 'Urządzenie zapisane, ale wysyłka nie jest aktywna'
        : 'Powiadomienia wyłączone';

    final description = !state.configured
        ? 'Ta kompilacja nie ma skonfigurowanej usługi powiadomień. Ustawienia kategorii można przygotować, ale aplikacja nie będzie udawać, że alerty są wysyłane.'
        : !state.backendReachable
        ? 'Ostatnia próba połączenia nie powiodła się. Zapisane ustawienia pozostają na urządzeniu.'
        : registered && !state.providerReady
        ? 'Urządzenie jest zapisane, ale usługa wysyłki po stronie serwera nie jest gotowa. Do czasu zmiany tego stanu powiadomienia nie są uznawane za działające.'
        : deliveryReady
        ? 'Systemowa zgoda, rejestracja urządzenia i usługa wysyłki są gotowe.'
        : 'Włączenie nastąpi dopiero po Twoim kliknięciu i systemowej zgodzie.';

    return Scaffold(
      appBar: AppBar(title: const Text('Powiadomienia')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        deliveryReady
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(description),
                  const SizedBox(height: 10),
                  Text(_permissionText),
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    Text(state.error!),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                  if (state.registered) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: busy ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Sprawdź ponownie'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!registered && state.configured)
            FilledButton.icon(
              onPressed: busy ? null : _enable,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Włącz powiadomienia'),
            ),
          if (!state.configured)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Wysyłka jest wyłączona'),
                subtitle: Text(
                  'Ta wersja aplikacji nie ma kompletnej konfiguracji usługi powiadomień.',
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Kategorie',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SwitchListTile(
            title: const Text('Krytyczne alerty Polski'),
            value: prefs.criticalPoland,
            onChanged: busy
                ? null
                : (value) => _update(prefs.copyWith(criticalPoland: value)),
          ),
          SwitchListTile(
            title: const Text('Alerty wybranego województwa'),
            subtitle: Text(regions[widget.manager.repository.region] ?? ''),
            value: prefs.regionAlerts,
            onChanged: busy
                ? null
                : (value) => _update(prefs.copyWith(regionAlerts: value)),
          ),
          SwitchListTile(
            title: const Text('Obserwowane lokalizacje'),
            subtitle: Text(
              '${widget.manager.repository.watchedLocations.length} zapisanych punktów • bez historii przemieszczania',
            ),
            value: prefs.watchedLocations,
            onChanged: busy
                ? null
                : (value) => _update(prefs.copyWith(watchedLocations: value)),
          ),
          SwitchListTile(
            title: const Text('Cyberbezpieczeństwo'),
            value: prefs.cyber,
            onChanged: busy
                ? null
                : (value) => _update(prefs.copyWith(cyber: value)),
          ),
          SwitchListTile(
            title: const Text('Granice'),
            value: prefs.border,
            onChanged: busy
                ? null
                : (value) => _update(prefs.copyWith(border: value)),
          ),
          SwitchListTile(
            title: const Text('Alarmy Ukrainy'),
            subtitle: const Text(
              'Osobna kategoria; nie wpływa na Status Polski. Domyślnie wyłączona.',
            ),
            value: prefs.ukraine,
            onChanged: busy
                ? null
                : (value) => _update(prefs.copyWith(ukraine: value)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Brak powiadomienia nie oznacza bezpieczeństwa. Aplikacja zawsze opiera główny status na stanie danych i źródeł, nie na samym push.',
          ),
          if (state.registered)
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await widget.manager.unregister();
                      } catch (_) {
                        // Rejestracja pozostaje aktywna, jeśli serwer nie potwierdził usunięcia.
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              icon: const Icon(Icons.notifications_off_outlined),
              label: const Text('Wyłącz powiadomienia na tym urządzeniu'),
            ),
        ],
      ),
    );
  }
}
