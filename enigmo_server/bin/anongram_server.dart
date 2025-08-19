import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/websocket_handler.dart';

void main(List<String> arguments) async {
  // Настройка логирования
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
    if (record.error != null) {
      print('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('Stack trace: ${record.stackTrace}');
    }
  });

  final logger = Logger('AnogramServer');

  // Парсинг аргументов командной строки
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Порт сервера')
    ..addOption('host', abbr: 'h', defaultsTo: 'localhost', help: 'Хост сервера')
    ..addFlag('help', negatable: false, help: 'Показать справку');

  final argResults = parser.parse(arguments);

  if (argResults['help'] as bool) {
    print('Anongram Bootstrap Server');
    print('Использование: dart run bin/anongram_server.dart [опции]');
    print(parser.usage);
    return;
  }

  final port = int.tryParse(argResults['port'] as String) ?? 8080;
  final host = argResults['host'] as String;

  // Инициализация сервисов
  final userManager = UserManager();
  final messageManager = MessageManager(userManager);
  final webSocketHandler = WebSocketHandler(userManager, messageManager);

  // Настройка маршрутов
  final router = Router();

  // WebSocket endpoint
  router.get('/ws', webSocketHandler.handler);

  // REST API endpoints
  router.get('/api/health', (Request request) {
    return Response.ok('{"status": "ok", "timestamp": "${DateTime.now().toIso8601String()}"}',
        headers: {'Content-Type': 'application/json'});
  });

  router.get('/api/stats', (Request request) {
    final userStats = userManager.getStats();
    final messageStats = messageManager.getMessageStats();
    
    final stats = {
      'server': {
        'uptime': DateTime.now().toIso8601String(),
        'version': '1.0.0',
      },
      'users': userStats,
      'messages': messageStats,
    };
    
    return Response.ok(
      jsonEncode(stats),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Обработчик для неизвестных маршрутов
  router.all('/<ignored|.*>', (Request request) {
    return Response.notFound('Маршрут не найден: ${request.url.path}');
  });

  // Middleware для CORS и логирования
  final handler = Pipeline()
      .addMiddleware(corsHeaders())
      .addMiddleware(logRequests())
      .addHandler(router);

  // Запуск сервера
  try {
    final server = await serve(handler, host, port);
    logger.info('Anongram Bootstrap Server запущен на http://${server.address.host}:${server.port}');
    logger.info('WebSocket endpoint: ws://${server.address.host}:${server.port}/ws');
    logger.info('Health check: http://${server.address.host}:${server.port}/api/health');
    logger.info('Statistics: http://${server.address.host}:${server.port}/api/stats');
    
    // Обработка сигналов завершения
    ProcessSignal.sigint.watch().listen((signal) {
      logger.info('Получен сигнал завершения, останавливаем сервер...');
      server.close(force: true);
      exit(0);
    });
    
  } catch (e, stackTrace) {
    logger.severe('Ошибка запуска сервера: $e', e, stackTrace);
    exit(1);
  }
}
