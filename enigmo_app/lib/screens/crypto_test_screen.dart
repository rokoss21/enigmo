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
      _statusMessage = 'Инициализация ключей...';
    });
    
    try {
      // Загружаем или генерируем ключи
      final hasKeys = await KeyManager.hasUserKeys();
      if (!hasKeys) {
        await KeyManager.generateUserKeys();
        setState(() {
          _statusMessage = 'Новые ключи сгенерированы';
        });
      } else {
        await KeyManager.loadUserKeys();
        setState(() {
          _statusMessage = 'Ключи загружены';
        });
      }
      
      // Получаем информацию о пользователе
      _userId = await KeyManager.getUserId();
      
      final encryptionKey = await KeyManager.getEncryptionPublicKey();
      _encryptionPublicKey = await KeyManager.publicKeyToString(encryptionKey);
      
      final signingKey = await KeyManager.getSigningPublicKey();
      _signingPublicKey = await KeyManager.publicKeyToString(signingKey);
      
      setState(() {
        _statusMessage = 'Готов к работе';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _encryptMessage() async {
    if (_messageController.text.isEmpty || _recipientKeyController.text.isEmpty) {
      _showSnackBar('Введите сообщение и ключ получателя');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Шифрование...';
    });
    
    try {
      // Конвертируем строку ключа получателя в PublicKey
      final recipientKey = await KeyManager.publicKeyFromString(
        _recipientKeyController.text,
        isEncryption: true,
      );
      
      // Шифруем сообщение
      final encryptedMessage = await CryptoEngine.encryptMessage(
        _messageController.text,
        recipientKey,
      );
      
      // Конвертируем в JSON для отображения
      final encryptedJson = encryptedMessage.toJson();
      _encryptedController.text = encryptedJson.toString();
      
      setState(() {
        _statusMessage = 'Сообщение зашифровано';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка шифрования: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _decryptMessage() async {
    if (_encryptedController.text.isEmpty) {
      _showSnackBar('Введите зашифрованное сообщение');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Расшифровка...';
    });
    
    try {
      // Для демонстрации используем наши собственные ключи как ключи отправителя
      final senderEncryptionKey = await KeyManager.getEncryptionPublicKey();
      final senderSigningKey = await KeyManager.getSigningPublicKey();
      
      // Парсим зашифрованное сообщение (упрощенный парсинг)
      final encryptedText = _encryptedController.text;
      
      // В реальном приложении здесь был бы правильный JSON парсинг
      // Для демонстрации создаем фиктивное зашифрованное сообщение
      _showSnackBar('Для полной демонстрации нужен второй пользователь');
      
      setState(() {
        _statusMessage = 'Для расшифровки нужны ключи отправителя';
        _decryptedController.text = 'Демо: расшифровка требует ключи отправителя';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка расшифровки: $e';
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
      _statusMessage = 'Генерация новых ключей...';
    });
    
    try {
      await KeyManager.deleteUserKeys();
      await _initializeKeys();
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка генерации ключей: $e';
      });
    }
  }
  
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('$label скопирован в буфер обмена');
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
        title: const Text('Тест криптографии'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Информация о пользователе
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Информация о пользователе',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('ID пользователя: $_userId'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Ключ шифрования: ${_encryptionPublicKey.substring(0, 20)}...',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copyToClipboard(
                                  _encryptionPublicKey,
                                  'Ключ шифрования',
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Ключ подписи: ${_signingPublicKey.substring(0, 20)}...',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copyToClipboard(
                                  _signingPublicKey,
                                  'Ключ подписи',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Шифрование
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Шифрование сообщения',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              labelText: 'Сообщение для шифрования',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _recipientKeyController,
                            decoration: const InputDecoration(
                              labelText: 'Публичный ключ получателя (для шифрования)',
                              border: OutlineInputBorder(),
                              hintText: 'Вставьте ключ шифрования получателя',
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _encryptMessage,
                            child: const Text('Зашифровать'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _encryptedController,
                            decoration: const InputDecoration(
                              labelText: 'Зашифрованное сообщение',
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
                  
                  // Расшифровка
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Расшифровка сообщения',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _decryptMessage,
                            child: const Text('Расшифровать'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _decryptedController,
                            decoration: const InputDecoration(
                              labelText: 'Расшифрованное сообщение',
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
                  
                  // Статус и управление
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Статус: $_statusMessage',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _generateNewKeys,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text('Сгенерировать новые ключи'),
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