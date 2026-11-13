import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../domain/assistant_conversation.dart';
import 'assistant_usage_store.dart';

/// Android (and other non-web) assistant. The sideloaded release APK cannot
/// get a Play Integrity token, so the question goes to the Cloudflare Worker
/// (`POST /assistant`) which calls the Gemini Developer API. The page still
/// runs [AssistantConversation], so the per-device Cairo-day limit and the
/// per-minute limit are checked before this is called.
class WorkerAssistantModel implements AssistantModel {
  const WorkerAssistantModel();

  @override
  Future<void> warmUp() async {}

  @override
  Future<String?> generate({
    required String model,
    required String instruction,
    required List<AssistantTurn> history,
    required String prompt,
  }) async {
    final url = AppConfig.assistantWorkerUrl.trim();
    if (url.isEmpty) throw StateError('ASSISTANT_WORKER_URL is not set');
    final store = await PrefsUsageStore.load();
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url)).timeout(const Duration(seconds: 45));
      req.headers.set('content-type', 'application/json; charset=utf-8');
      req.headers.set('x-church-app', 'church-portal-android');
      req.headers.set('x-church-device', store.deviceId);
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'instruction': instruction,
        'history': [
          for (final t in history) {'user': t.user, 'text': t.text},
        ],
        'prompt': prompt,
      })));
      final res = await req.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode != 200) {
        final code = _workerErrorCode(body);
        debugPrint('Assistant worker HTTP ${res.statusCode}${code.isEmpty ? '' : ' $code'}');
        throw Exception('assistant worker ${res.statusCode}${code.isEmpty ? '' : ' $code'}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['text'] is! String) return null;
      return decoded['text'] as String;
    } finally {
      client.close(force: true);
    }
  }
}

AssistantModel createAssistantModel() => const WorkerAssistantModel();

/// Short Worker error code only (`bad_request`, `device_cap`). Never the body.
String _workerErrorCode(String body) {
  try {
    final decoded = jsonDecode(body);
    final code = decoded is Map ? decoded['error'] : null;
    if (code is String && RegExp(r'^[a-z_]{1,40}$').hasMatch(code)) return code;
  } catch (_) {}
  return '';
}
