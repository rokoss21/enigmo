// Facade with conditional export to select platform-specific implementation.
// On web, use the implementation that relies on dart:html.
// On other platforms (iOS/Android/desktop), use the dart:html-free implementation.

export 'notification_service_mobile.dart'
    if (dart.library.html) 'notification_service_web.dart';