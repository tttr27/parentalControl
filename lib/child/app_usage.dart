import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

/// Custom Exception for the plugin.
/// Thrown whenever the plugin is used on platforms other than Android.
class AppUsageException implements Exception {
  String _cause;

  AppUsageException(this._cause);

  @override
  String toString() => _cause;
}

class AppUsageInfo {
  late String _packageName, _appName;
  late Duration _usage;
  DateTime _startDate, _endDate, _lastForeground;

  AppUsageInfo(
    String name,
    double usageInSeconds,
    this._startDate,
    this._endDate,
    this._lastForeground,
  ) {
    List<String> tokens = name.split('.');
    _packageName = name;
    _appName = tokens.last;
    _usage = Duration(seconds: usageInSeconds.toInt());
  }

  /// The name of the application
  String get appName => _appName;

  /// The name of the application package
  String get packageName => _packageName;

  /// The amount of time the application has been used
  /// in the specified interval
  Duration get usage => _usage;

  /// The start of the interval
  DateTime get startDate => _startDate;

  /// The end of the interval
  DateTime get endDate => _endDate;

  /// Last time app was in foreground
  DateTime get lastForeground => _lastForeground;

  @override
  String toString() {
    return 'App Usage: $packageName - $appName, duration: $usage [$startDate, $endDate]';
  }
}

class AppUsage {
  static const MethodChannel _methodChannel =
      const MethodChannel("app_usage.methodChannel");

  static final AppUsage _instance = AppUsage._();
  AppUsage._();
  factory AppUsage() => _instance;

  Future<List<AppUsageInfo>> getAppUsage(
    DateTime startDate,
    DateTime endDate,
    String parentID,
    String childID,
  ) async {
    if (Platform.isAndroid) {
      // Convert dates to ms since epoch
      int end = endDate.millisecondsSinceEpoch;
      int start = startDate.millisecondsSinceEpoch;

      // Set parameters
      Map<String, int> interval = {'start': start, 'end': end};

      // Get result and parse it as a Map of <String, List<double>>
      Map usage = await _methodChannel.invokeMethod('getUsage', interval);

      // Convert to list of AppUsageInfo and save to Firestore
      List<AppUsageInfo> result = [];
      Map<String, dynamic> appUsageMap = {};

      for (String key in usage.keys) {
        List<double> temp = List<double>.from(usage[key]);
        if (temp[0] > 0) {
          AppUsageInfo info = AppUsageInfo(
              key,
              temp[0],
              DateTime.fromMillisecondsSinceEpoch(temp[1].round() * 1000),
              DateTime.fromMillisecondsSinceEpoch(temp[2].round() * 1000),
              DateTime.fromMillisecondsSinceEpoch(temp[3].round() * 1000));
          result.add(info);

          // Prepare data for saving
          appUsageMap[info.appName] = {
            'packageName': info.packageName,
            'usage': info.usage.inSeconds, // Store the usage time in seconds
            'lastForeground': info.lastForeground.toIso8601String(),
          };
        }
      }

      // Save to Firestore under the specified parent and child
      await FirebaseFirestore.instance
          .collection('parents')
          .doc(parentID)
          .collection('children')
          .doc(childID)
          .set({
        'appUsage': appUsageMap,
      }, SetOptions(merge: true));

      return result;
    }
    throw AppUsageException('AppUsage API is only available on Android');
  }
}