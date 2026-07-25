import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point for the pocket-mode foreground task isolate.
@pragma('vm:entry-point')
void pocketForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(PocketForegroundTaskHandler());
}

class PocketForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain({'ping': true});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.sendDataToMain({
        'action': 'stop',
        'bringToForeground': true,
      });
    } else if (id == 'disarm') {
      FlutterForegroundTask.sendDataToMain({
        'action': 'disarm',
        'bringToForeground': true,
      });
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

/// Android foreground service that keeps BLE timing alive with the screen off.
class PocketForegroundService {
  static bool _initialized = false;

  // New channel id when importance changes — Android caches the old HIGH channel.
  static const _channelId = 'open_dragy_pocket_quiet';
  static const _serviceId = 4243;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'OpenDragy pocket / logger',
        channelDescription:
            'Keeps pocket timing or logger recording active with the screen off.',
        onlyAlertOnce: true,
        showWhen: false,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        // LOW = stays collapsed in the shade (no heads-up banner on start).
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    return true;
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<void> startOrUpdate({
    required String title,
    required String subtitle,
    bool showDisarm = false,
    bool showStop = false,
  }) async {
    ensureInitialized();
    if (!Platform.isAndroid) return;

    final buttons = <NotificationButton>[];
    if (showStop) {
      buttons.add(const NotificationButton(id: 'stop', text: 'Stop'));
    }
    if (showDisarm) {
      buttons.add(const NotificationButton(id: 'disarm', text: 'Disarm'));
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: subtitle,
        notificationButtons: buttons,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.connectedDevice],
      serviceId: _serviceId,
      notificationTitle: title,
      notificationText: subtitle,
      notificationButtons: buttons,
      callback: pocketForegroundStartCallback,
    );
  }

  static Future<void> startArmed({required String subtitle}) async {
    await startOrUpdate(
      title: 'OpenDragy — Armed',
      subtitle: subtitle,
      showDisarm: true,
      showStop: false,
    );
  }

  static Future<void> startLogging({required String subtitle}) async {
    await startOrUpdate(
      title: 'OpenDragy — Logger',
      subtitle: subtitle,
      showDisarm: false,
      showStop: true,
    );
  }

  static Future<void> update({
    required String title,
    required String subtitle,
    bool showDisarm = false,
    bool showStop = false,
  }) async {
    await startOrUpdate(
      title: title,
      subtitle: subtitle,
      showDisarm: showDisarm,
      showStop: showStop,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> bringAppToForeground() async {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.launchApp('/');
  }
}
