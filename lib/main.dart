import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/app/app.dart';
import 'package:spendwise/app/providers.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/services/billing/billing_gateway.dart';
import 'package:spendwise/services/crash_reporter.dart';
import 'package:spendwise/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final crash = LocalCrashReporter();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    crash.recordError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crash.recordError(error, stack);
    return true;
  };

  // One zone for binding + runApp (a guarded sub-zone would trip Flutter's zone
  // check in debug builds); uncaught async errors arrive via PlatformDispatcher.onError.
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  final db = AppDatabase.file(File(p.join(dir.path, 'spendwise.sqlite')));
  final notifications = LocalNotificationService();

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(notifications),
      billingGatewayProvider.overrideWith((ref) => PlayBillingGateway()),
    ],
  );

  // Optional services are started without blocking the first frame.
  unawaited(
    container
        .read(subscriptionRepositoryProvider)
        .start()
        .then((_) => runStartupTasks(container)),
  );
  unawaited(notifications.init());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SpendWiseApp(),
    ),
  );
}
