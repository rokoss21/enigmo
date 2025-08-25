import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  late bool _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _notificationsEnabled = _notificationService.userEnabled;
  }

  Future<void> _requestPermission() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission request is for web browsers only')),
      );
      return;
    }
    final granted = await _notificationService.requestPermissionIfNeeded();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted
            ? 'Notifications permitted by browser'
            : 'Notifications are blocked or not granted'),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: scheme.surfaceVariant,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable notifications'),
            subtitle: Text(
              _notificationService.isEnabled
                  ? 'Enabled (browser permission granted)'
                  : _notificationsEnabled
                      ? 'Disabled by browser permissions'
                      : 'Disabled by user preference',
            ),
            value: _notificationsEnabled,
            onChanged: (val) {
              setState(() {
                _notificationsEnabled = val;
                _notificationService.setUserEnabled(val);
              });
            },
          ),
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _requestPermission,
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Request browser permission'),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    _notificationService.isEnabled ? Icons.check_circle : Icons.error_outline,
                    color: _notificationService.isEnabled ? Colors.green : scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Notifications are optional. The app always loads regardless of permissions. '
              'You can enable or disable notifications here at any time.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
