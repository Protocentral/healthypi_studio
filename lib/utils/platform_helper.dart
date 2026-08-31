import 'dart:io';
import 'package:flutter/foundation.dart';

class PlatformHelper {
  static bool get isDesktop => 
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  
  static bool get isMobile => 
      Platform.isAndroid || Platform.isIOS;
  
  static bool get supportsUsb => 
      Platform.isAndroid || Platform.isWindows || Platform.isLinux;
  
  static bool get supportsBluetooth => 
      !kIsWeb;
  
  static String get platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (kIsWeb) return 'Web';
    return 'Unknown';
  }
}
