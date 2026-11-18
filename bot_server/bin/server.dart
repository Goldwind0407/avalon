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
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../lib/features/solo/bot_service.dart';

const maxBody = 2 * 1024 * 1024;

/// A request whose body has not all arrived by then is turned away, so a
/// slow or stalled caller holds up nobody but itself.
const bodyTimeout = Duration(seconds: 10);

Future<void> main() async {
  final secret = Platform.environment['BOT_SERVER_SECRET'] ?? '';
  if (secret.length < 16) {
    stderr.writeln('BOT_SERVER_SECRET must be set (16 characters or more).');
    exit(64);
  }
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final service = BotService();
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  server.idleTimeout = const Duration(seconds: 30);
  stdout.writeln('Computer players listening on :$port');
  // Each request is handled on its own: one that is slow to arrive does
  // not hold up the others. The thinking itself (service.step) is
  // synchronous, so two requests about one table never interleave.
  await for (final request in server) {
    unawaited(handle(request, service, secret));
  }
}

Future<void> handle(
    HttpRequest request, BotService service, String secret) async {
  Future<void> reply(int status, Object body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close().timeout(bodyTimeout);
  }

  try {
    if (request.uri.path == '/healthz') {
      return await reply(200, {'ok': true, 'tables': service.tables});
    }
    final path = request.uri.path;
    if (request.method != 'POST' || (path != '/step' && path != '/speech')) {
      return await reply(404, {'error': 'not found'});
    }
    if (!_same(request.headers.value('x-bot-secret') ?? '', secret)) {
      return await reply(401, {'error': 'unauthorized'});
    }
    final bytes = <int>[];
    try {
      await for (final chunk in request.timeout(bodyTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBody) {
          return await reply(413, {'error': 'too large'});
        }
      }
    } on TimeoutException {
      return await reply(408, {'error': 'request body too slow'});
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return await reply(400, {'error': 'not JSON'});
    }
    if (body is! Map) return await reply(400, {'error': 'not an object'});
    try {
      return await reply(
          200, path == '/speech' ? ladyClaimsIn(body) : service.step(body));
    } on BotRequestError catch (e) {
      return await reply(400, {'error': e.message});
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
