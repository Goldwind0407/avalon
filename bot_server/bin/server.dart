// The computer players' server: the online referee (Cloud Functions) asks
// it what the computer seats of a table do next. The reasoning is the
// app's own (../../lib/features/solo), shared by path so there is one copy.
//
//   PORT               port to listen on (8080)
//   BOT_SERVER_SECRET  shared with the Cloud Functions; every request must
//                      carry it in the x-bot-secret header
//
// Run locally:  dart run bot_server/bin/server.dart
// Runs the same on Cloud Run and on a Raspberry Pi (see ../Dockerfile).
import 'dart:convert';
import 'dart:io';
import '../../lib/features/solo/bot_service.dart';

const maxBody = 2 * 1024 * 1024;

Future<void> main() async {
  final secret = Platform.environment['BOT_SERVER_SECRET'] ?? '';
  if (secret.length < 16) {
    stderr.writeln('BOT_SERVER_SECRET must be set (16 characters or more).');
    exit(64);
  }
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final service = BotService();
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Computer players listening on :$port');
  await for (final request in server) {
    // one at a time: a table's computers think in turn
    await _handle(request, service, secret);
  }
}

Future<void> _handle(
    HttpRequest request, BotService service, String secret) async {
  Future<void> reply(int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  try {
    if (request.uri.path == '/healthz') {
      return reply(200, {'ok': true, 'tables': service.tables});
    }
    if (request.method != 'POST' || request.uri.path != '/step') {
      return reply(404, {'error': 'not found'});
    }
    if (!_same(request.headers.value('x-bot-secret') ?? '', secret)) {
      return reply(401, {'error': 'unauthorized'});
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBody) return reply(413, {'error': 'too large'});
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return reply(400, {'error': 'not JSON'});
    }
    if (body is! Map) return reply(400, {'error': 'not an object'});
    try {
      return reply(200, service.step(body));
    } on BotRequestError catch (e) {
      return reply(400, {'error': e.message});
    }
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    try {
      await reply(500, {'error': 'internal'});
    } catch (_) {/* the connection is gone */}
  }
}

/// Compares without stopping at the first difference.
bool _same(String a, String b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
