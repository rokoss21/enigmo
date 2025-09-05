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

/// Main class for the Anongram server
class AnogramServer {
  final Logger _logger = Logger('AnogramServer');
  late final UserManager _userManager;
  late final MessageManager _messageManager;
  late final WebSocketHandler _webSocketHandler;
  late final HttpServer _server;
  late final DateTime _startTime;
  
  /// Initializes the server
  Future<void> initialize({
    String host = 'localhost',
    int port = 8080,
  }) async {
    try {
      // Initialize services
      _userManager = UserManager();
      _messageManager = MessageManager(_userManager);
      _webSocketHandler = WebSocketHandler(_userManager, _messageManager);

      // Configure routes
      final router = Router();

      // WebSocket endpoint
      router.get('/ws', _webSocketHandler.handler);

      // REST API endpoints
      router.get('/api/health', _handleHealthCheck);
      router.get('/api/stats', _handleStats);

      // Handler for unknown routes
      router.all('/<ignored|.*>', _handleNotFound);

      // Middleware for CORS and logging
      final handler = Pipeline()
          .addMiddleware(corsHeaders())
          .addMiddleware(logRequests())
          .addHandler(router);

      // Start server
      _startTime = DateTime.now();
      _server = await serve(handler, host, port);
      
      _logger.info('Anongram Bootstrap Server started at http://${_server.address.host}:${_server.port}');
      _logger.info('WebSocket endpoint: ws://${_server.address.host}:${_server.port}/ws');
      _logger.info('Health check: http://${_server.address.host}:${_server.port}/api/health');
      _logger.info('Statistics: http://${_server.address.host}:${_server.port}/api/stats');
      
    } catch (e, stackTrace) {
      _logger.severe('Server initialization error: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Health check handler
  Response _handleHealthCheck(Request request) {
    final uptime = DateTime.now().difference(_startTime).inSeconds;
    final healthData = {
      'status': 'ok',
      'timestamp': DateTime.now().toIso8601String(),
      'version': '1.0.0',
      'uptime': uptime,
    };
    
    return Response.ok(
      jsonEncode(healthData),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Server statistics handler
  Response _handleStats(Request request) {
    try {
      final userStats = _userManager.getUserStats();
      final messageStats = _messageManager.getMessageStats();

      final uptime = DateTime.now().difference(_startTime).inSeconds;
      final stats = {
        'server': {
          'uptime': uptime,
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
      _logger.warning('Failed to get statistics: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get statistics'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Handler for unknown routes
  Response _handleNotFound(Request request) {
    return Response.notFound(
      jsonEncode({'error': 'Route not found: ${request.url.path}'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Stops the server
  Future<void> stop({bool force = false}) async {
    try {
      _logger.info('Stopping server...');
      await _server.close(force: force);
      _logger.info('Server stopped');
    } catch (e) {
      _logger.severe('Server stop error: $e');
    }
  }

  /// Returns the server address
  InternetAddress get address => _server.address;
  
  /// Returns the server port
  int get port => _server.port;
}
