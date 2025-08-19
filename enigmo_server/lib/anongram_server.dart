import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'services/user_manager.dart';
import 'services/message_manager.dart';
import 'services/websocket_handler.dart';
import 'utils/logger.dart' as custom_logger;

/// Основной класс сервера Anongram
class AnogramServer {
  final Logger _logger = Logger('AnogramServer');
  late final UserManager _userManager;
  late final MessageManager _messageManager;
  late final WebSocketHandler _webSocketHandler;
  late final HttpServer _server;
  
  /// Инициализирует сервер
  Future<void> initialize({
    String host = 'localhost',
    int port = 8080,
  }) async {
    try {
      // Инициализация сервисов
      _userManager = UserManager();
      _messageManager = MessageManager(_userManager);
      _webSocketHandler = WebSocketHandler(_userManager, _messageManager);

      // Настройка маршрутов
      final router = Router();

      // WebSocket endpoint
      router.get('/ws', _webSocketHandler.handler);

      // REST API endpoints
      router.get('/api/health', _handleHealthCheck);
      router.get('/api/stats', _handleStats);

      // Обработчик для неизвестных маршрутов
      router.all('/<ignored|.*>', _handleNotFound);

      // Middleware для CORS и логирования
      final handler = Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(router);

      // Запуск сервера
      _server = await serve(handler, host, port);
      
      _logger.info('Anongram Bootstrap Server запущен на http://${_server.address.host}:${_server.port}');
      _logger.info('WebSocket endpoint: ws://${_server.address.host}:${_server.port}/ws');
      _logger.info('Health check: http://${_server.address.host}:${_server.port}/api/health');
      _logger.info('Statistics: http://${_server.address.host}:${_server.port}/api/stats');
      
    } catch (e, stackTrace) {
      _logger.severe('Ошибка инициализации сервера: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Обработчик проверки состояния сервера
  Response _handleHealthCheck(Request request) {
    final healthData = {
      'status': 'ok',
      'timestamp': DateTime.now().toIso8601String(),
      'version': '1.0.0',
      'uptime': DateTime.now().toIso8601String(),
    };
    
    return Response.ok(
      jsonEncode(healthData),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Обработчик статистики сервера
  Response _handleStats(Request request) {
    try {
      final userStats = _userManager.getUserStats();
      final messageStats = _messageManager.getMessageStats();
      
      final stats = {
        'server': {
          'uptime': DateTime.now().toIso8601String(),
          'version': '1.0.0',
          'status': 'running',
        },
        'users': userStats,
        'messages': messageStats,
      };
      
      return Response.ok(
        jsonEncode(stats),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      _logger.warning('Ошибка получения статистики: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Ошибка получения статистики'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Обработчик для неизвестных маршрутов
  Response _handleNotFound(Request request) {
    return Response.notFound(
      jsonEncode({'error': 'Маршрут не найден: ${request.url.path}'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Останавливает сервер
  Future<void> stop({bool force = false}) async {
    try {
      _logger.info('Остановка сервера...');
      await _server.close(force: force);
      _logger.info('Сервер остановлен');
    } catch (e) {
      _logger.severe('Ошибка остановки сервера: $e');
    }
  }

  /// Возвращает адрес сервера
  InternetAddress get address => _server.address;
  
  /// Возвращает порт сервера
  int get port => _server.port;
}
