import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/key_manager.dart';
import '../services/crypto_engine.dart';
import 'package:cryptography/cryptography.dart';

class CryptoTestScreen extends StatefulWidget {
  const CryptoTestScreen({super.key});

  @override
  State<CryptoTestScreen> createState() => _CryptoTestScreenState();
}

class _CryptoTestScreenState extends State<CryptoTestScreen> {
  final _messageController = TextEditingController();
  final _recipientKeyController = TextEditingController();
  final _encryptedController = TextEditingController();
  final _decryptedController = TextEditingController();
  
  String _userId = '';
  String _encryptionPublicKey = '';
  String _signingPublicKey = '';
  bool _isLoading = false;
  String _statusMessage = '';
  
  @override
  void initState() {
    super.initState();
    _initializeKeys();
  }
  
  Future<void> _initializeKeys() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing keys...';
    });
    
    try {
      // Load or generate keys
      final hasKeys = await KeyManager.hasUserKeys();
      if (!hasKeys) {
        await KeyManager.generateUserKeys();
        setState(() {
          _statusMessage = 'New keys generated';
        });
      } else {
        await KeyManager.loadUserKeys();
        setState(() {
          _statusMessage = 'Keys loaded';
        });
      }
      
      // Get user information
      _userId = await KeyManager.getUserId();
      
      final encryptionKey = await KeyManager.getEncryptionPublicKey();
      _encryptionPublicKey = await KeyManager.publicKeyToString(encryptionKey);
      
      final signingKey = await KeyManager.getSigningPublicKey();
      _signingPublicKey = await KeyManager.publicKeyToString(signingKey);
      
      setState(() {
        _statusMessage = 'Ready';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _encryptMessage() async {
    if (_messageController.text.isEmpty || _recipientKeyController.text.isEmpty) {
      _showSnackBar('Enter a message and recipient key');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Encrypting...';
    });
    
    try {
      // Convert recipient key string into a PublicKey
      final recipientKey = await KeyManager.publicKeyFromString(
        _recipientKeyController.text,
        isEncryption: true,
      );
      
      // Encrypt the message
      final encryptedMessage = await CryptoEngine.encryptMessage(
        _messageController.text,
        recipientKey,
      );
      
      // Convert to JSON for display
      final encryptedJson = encryptedMessage.toJson();
      _encryptedController.text = encryptedJson.toString();
      
      setState(() {
        _statusMessage = 'Message encrypted';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Encryption error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _decryptMessage() async {
    if (_encryptedController.text.isEmpty) {
      _showSnackBar('Enter an encrypted message');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Decrypting...';
    });
    
    try {
      // For demo purposes, use our own keys as the sender's keys
      final senderEncryptionKey = await KeyManager.getEncryptionPublicKey();
      final senderSigningKey = await KeyManager.getSigningPublicKey();
      
      // Parse the encrypted message (simplified parsing)
      final encryptedText = _encryptedController.text;
      
      // In a real app there would be proper JSON parsing here
      // For demonstration, show a placeholder
      _showSnackBar('A second user is required for a full demo');
      
      setState(() {
        _statusMessage = 'Sender keys are required for decryption';
        _decryptedController.text = 'Demo: decryption requires sender keys';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Decryption error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _generateNewKeys() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Generating new keys...';
    });
    
    try {
      await KeyManager.deleteUserKeys();
      await _initializeKeys();
    } catch (e) {
      setState(() {
        _statusMessage = 'Key generation error: $e';
      });
    }
  }
  
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('$label copied to clipboard');
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cryptography Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // User information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'User information',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('User ID: $_userId'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Encryption key: ${_encryptionPublicKey.substring(0, 20)}...',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copyToClipboard(
                                  _encryptionPublicKey,
                                  'Encryption key',
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Signing key: ${_signingPublicKey.substring(0, 20)}...',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copyToClipboard(
                                  _signingPublicKey,
                                  'Signing key',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Encryption
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Message encryption',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              labelText: 'Message to encrypt',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _recipientKeyController,
                            decoration: const InputDecoration(
                              labelText: 'Recipient public key (for encryption)',
                              border: OutlineInputBorder(),
                              hintText: "Paste recipient's encryption key",
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _encryptMessage,
                            child: const Text('Encrypt'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _encryptedController,
                            decoration: const InputDecoration(
                              labelText: 'Encrypted message',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 5,
                            readOnly: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Decryption
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Message decryption',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _decryptMessage,
                            child: const Text('Decrypt'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _decryptedController,
                            decoration: const InputDecoration(
                              labelText: 'Decrypted message',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                            readOnly: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Status and controls
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status: $_statusMessage',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _generateNewKeys,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text('Generate new keys'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  @override
  void dispose() {
    _messageController.dispose();
    _recipientKeyController.dispose();
    _encryptedController.dispose();
    _decryptedController.dispose();
    super.dispose();
  }
}