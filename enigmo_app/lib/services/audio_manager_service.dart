import 'package:flutter/services.dart';

class AudioManagerService {
  static const MethodChannel _channel = MethodChannel('com.enigmo.audio_manager');

  static Future<void> setSpeakerphoneOn(bool enabled) async {
    try {
      await _channel.invokeMethod('setSpeakerphoneOn', {'enabled': enabled});
    } on PlatformException catch (e) {
      print('Failed to set speakerphone: ${e.message}');
    }
  }

  static Future<bool> isSpeakerphoneOn() async {
    try {
      final bool result = await _channel.invokeMethod('isSpeakerphoneOn');
      return result;
    } on PlatformException catch (e) {
      print('Failed to get speakerphone state: ${e.message}');
      return false;
    }
  }

  static Future<void> setAudioMode(int mode) async {
    try {
      await _channel.invokeMethod('setAudioMode', {'mode': mode});
    } on PlatformException catch (e) {
      print('Failed to set audio mode: ${e.message}');
    }
  }

  // Audio modes
  static const int MODE_NORMAL = 0;
  static const int MODE_RINGTONE = 1;
  static const int MODE_IN_CALL = 2;
  static const int MODE_IN_COMMUNICATION = 3;
}