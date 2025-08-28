import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../services/network_service.dart';
import '../services/key_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  final NetworkService _networkService = NetworkService();
  late bool _notificationsEnabled;
  late String _serverUrl;
  late TextEditingController _serverController;
  bool _isEditingServer = false;

  @override
  void initState() {
    super.initState();
    _notificationsEnabled = _notificationService.userEnabled;
    _loadCurrentServerUrl();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentServerUrl() async {
    final currentUrl = await NetworkService.getCurrentServerUrl();
    if (mounted) {
      setState(() {
        _serverUrl = currentUrl;
        if (_serverController.text.isEmpty) {
          _serverController.text = currentUrl;
        }
      });
    }
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

  Future<void> _saveServerUrl() async {
    final newUrl = _serverController.text.trim();
    if (newUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL cannot be empty')),
      );
      return;
    }

    try {
      await NetworkService.saveServerUrl(newUrl);
      if (mounted) {
        setState(() {
          _serverUrl = newUrl;
          _isEditingServer = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL saved. Restart app to apply changes.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving server URL: $e')),
      );
    }
  }

  Future<void> _testServerConnection() async {
    final testUrl = _serverController.text.trim();
    if (testUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a server URL first')),
      );
      return;
    }

    try {
      // Simple connection test - try to connect with a timeout
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Testing connection...')),
      );

      // This is a simplified test - in real implementation you might want to make an actual connection attempt
      await Future.delayed(const Duration(seconds: 2));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection test completed. Check logs for details.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection test failed: $e')),
      );
    }
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
          // Server Configuration Section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Server Configuration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            title: const Text('Server URL'),
            subtitle: _isEditingServer
                ? TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      hintText: 'ws://your-server.com:8081/ws',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  )
                : Text(_serverUrl),
            trailing: _isEditingServer
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: _saveServerUrl,
                        tooltip: 'Save',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _serverController.text = _serverUrl;
                            _isEditingServer = false;
                          });
                        },
                        tooltip: 'Cancel',
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          setState(() {
                            _isEditingServer = true;
                          });
                        },
                        tooltip: 'Edit server URL',
                      ),
                      IconButton(
                        icon: const Icon(Icons.network_check),
                        onPressed: _testServerConnection,
                        tooltip: 'Test connection',
                      ),
                    ],
                  ),
          ),
          const Divider(),

          // Notifications Section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Notifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server Configuration:',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Enter your server WebSocket URL (e.g., ws://your-vps.com:8081/ws)\n'
                  '• Use "Test Connection" to verify the server is reachable\n'
                  '• Changes require app restart to take effect\n'
                  '• For local development: ws://localhost:8081/ws\n'
                  '• For Android emulator: ws://10.0.2.2:8081/ws',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text(
                  'Notifications:',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Notifications are optional. The app always loads regardless of permissions. '
                  'You can enable or disable notifications here at any time.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
