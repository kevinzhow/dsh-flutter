import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Whether the system lets the app post notifications.
enum NoticePermission {
  /// Notifications may be shown.
  granted,

  /// The user refused (or switched them off in the system settings).
  denied,

  /// The system has not been asked yet.
  notDetermined,

  /// This platform has no notification support in the app.
  unsupported,
}

/// What the app needs from the platform to notify and to stay connected while
/// in the background. [PlatformNotificationService] is the real one; tests
/// inject a recording fake.
abstract interface class NotificationService {
  /// Whether the platform can show notifications at all.
  bool get supported;

  /// Prepare channels and callbacks. [onOpen] receives the session id of a
  /// tapped notification, including the one that launched the app.
  Future<void> init({required void Function(String sessionId) onOpen});

  /// The current permission, without asking.
  Future<NoticePermission> permission();

  /// Show the system's permission prompt (Android 13+ `POST_NOTIFICATIONS`,
  /// iOS authorization) when it has not been answered; returns the result.
  Future<NoticePermission> requestPermission();

  /// Post (or replace) the notification [id] for [sessionId].
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String sessionId,
  });

  /// Withdraw the notification [id].
  Future<void> cancel(int id);

  /// Withdraw every notification of the app.
  Future<void> cancelAll();

  /// Keep the process, and with it the host connection, alive while the app is
  /// in the background (an Android foreground service with an ongoing
  /// notification). A no-op where the platform has no such thing.
  Future<void> startKeepAlive({required String title, required String body});

  /// End [startKeepAlive].
  Future<void> stopKeepAlive();

  /// Open the system's notification settings for the app.
  Future<void> openSettings();
}

/// The strings the platform channels carry (channel names are user visible in
/// the Android settings).
class NoticeStrings {
  const NoticeStrings({
    required this.pendingChannel,
    required this.pendingChannelDescription,
    required this.watchingChannel,
    required this.watchingChannelDescription,
  });

  final String pendingChannel;
  final String pendingChannelDescription;
  final String watchingChannel;
  final String watchingChannelDescription;
}

/// [NotificationService] over `flutter_local_notifications`. Android and iOS
/// are supported; the desktop platforms and the web show nothing.
class PlatformNotificationService implements NotificationService {
  PlatformNotificationService({required this.strings});

  /// Reads the channel names in the language of the moment.
  final NoticeStrings Function() strings;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  void Function(String sessionId)? _onOpen;
  bool _requested = false;

  static const String _pendingChannelId = 'pending';
  static const String _watchingChannelId = 'watching';

  /// Notification id of the keep-alive service (distinct from every pending id,
  /// which are positive hashes).
  static const int _keepAliveId = 1;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _darwin =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  bool get supported => _android || _darwin;

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> init({required void Function(String sessionId) onOpen}) async {
    _onOpen = onOpen;
    if (!supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked explicitly, when the user turns notifications on.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) _onOpen?.call(id);
      },
    );
    final s = strings();
    final android = _androidPlugin;
    if (android != null) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _pendingChannelId,
          s.pendingChannel,
          description: s.pendingChannelDescription,
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _watchingChannelId,
          s.watchingChannel,
          description: s.watchingChannelDescription,
          importance: Importance.low,
          showBadge: false,
        ),
      );
    }
    // The notification that launched the app (it was tapped while the app was
    // not running).
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      _onOpen?.call(payload);
    }
  }

  @override
  Future<NoticePermission> permission() async {
    if (!supported) return NoticePermission.unsupported;
    if (_android) {
      final enabled = await _androidPlugin?.areNotificationsEnabled() ?? false;
      if (enabled) return NoticePermission.granted;
      return _requested
          ? NoticePermission.denied
          : NoticePermission.notDetermined;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    final options = await (ios?.checkPermissions() ?? mac?.checkPermissions());
    if (options?.isEnabled ?? false) return NoticePermission.granted;
    return _requested
        ? NoticePermission.denied
        : NoticePermission.notDetermined;
  }

  @override
  Future<NoticePermission> requestPermission() async {
    if (!supported) return NoticePermission.unsupported;
    _requested = true;
    if (_android) {
      await _androidPlugin?.requestNotificationsPermission();
    } else {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      await (ios?.requestPermissions(alert: true, sound: true) ??
          mac?.requestPermissions(alert: true, sound: true));
    }
    return permission();
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String sessionId,
  }) async {
    if (!supported) return;
    final s = strings();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: sessionId,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _pendingChannelId,
          s.pendingChannel,
          channelDescription: s.pendingChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          autoCancel: true,
          // A session's title and a tool name are not for the lock screen.
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (supported) await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    if (!supported) return;
    // The keep-alive notification is not a pending-item notice.
    final android = _androidPlugin;
    final active = await android?.getActiveNotifications() ?? const [];
    if (android == null) {
      await _plugin.cancelAll();
      return;
    }
    for (final n in active) {
      final id = n.id;
      if (id != null && id != _keepAliveId) await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> startKeepAlive({
    required String title,
    required String body,
  }) async {
    final android = _androidPlugin;
    if (android == null) return;
    final s = strings();
    await android.startForegroundService(
      id: _keepAliveId,
      title: title,
      body: body,
      notificationDetails: AndroidNotificationDetails(
        _watchingChannelId,
        s.watchingChannel,
        channelDescription: s.watchingChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: false,
        category: AndroidNotificationCategory.service,
      ),
      startType: AndroidServiceStartType.startSticky,
      foregroundServiceTypes: const {
        AndroidServiceForegroundType.foregroundServiceTypeSpecialUse,
      },
    );
  }

  @override
  Future<void> stopKeepAlive() async {
    await _androidPlugin?.stopForegroundService();
  }

  @override
  Future<void> openSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);
}
