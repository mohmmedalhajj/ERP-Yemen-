import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'backup_service.dart';

class LocalNotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) => _plugin.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'erp_alerts',
        'تنبيهات النظام',
        channelDescription: 'تنبيهات المخزون والنسخ الاحتياطي والترخيص',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

class AutoBackupCoordinator {
  AutoBackupCoordinator(
    this._backup, {
    FlutterSecureStorage? storage,
    LocalNotificationService? notifications,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _notifications = notifications ?? LocalNotificationService();

  final BackupService _backup;
  final FlutterSecureStorage _storage;
  final LocalNotificationService _notifications;
  Timer? _timer;

  Future<void> start() async {
    await _notifications.initialize();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 24), (_) => runOnce());
  }

  Future<void> runOnce() async {
    final password = await _storage.read(key: 'erp_auto_backup_password');
    if (password == null || password.length < 8) return;
    try {
      await _backup.createEncryptedBackup(password: password);
      await _backup.pruneOldBackups(keep: 7);
      await _notifications.show(
        id: 9001,
        title: 'تم النسخ الاحتياطي',
        body: 'تم إنشاء نسخة احتياطية مشفرة بنجاح والاحتفاظ بآخر 7 نسخ.',
      );
    } catch (error) {
      await _notifications.show(
        id: 9002,
        title: 'فشل النسخ الاحتياطي',
        body: 'تعذر إنشاء النسخة الاحتياطية: $error',
      );
    }
  }

  void dispose() => _timer?.cancel();
}
