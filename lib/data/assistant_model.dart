import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../domain/assistant_conversation.dart';
import 'firebase_bootstrap.dart';

/// [AssistantModel] on Firebase AI Logic (Gemini Developer API backend,
/// App Check token attached automatically by the SDK — ADR-029). Stateless:
/// every call sends the system instruction, the kept history and the new
/// question, which is what a chat session sends anyway.
class FirebaseAssistantModel implements AssistantModel {
  const FirebaseAssistantModel();

  /// Mints the App Check token now (reCAPTCHA Enterprise on web can take a
  /// few seconds the first time), so the first question does not race it.
  @override
  Future<void> warmUp() async {
    await ensureAppCheckActivated();
    try {
      await FirebaseAppCheck.instance.getToken().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Assistant: App Check warm-up failed: $e');
    }
  }

  @override
  Future<String?> generate({
    required String model,
    required String instruction,
    required List<AssistantTurn> history,
    required String prompt,
  }) async {
    await ensureAppCheckActivated();
    final m = FirebaseAI.googleAI().generativeModel(
      model: model,
      systemInstruction: Content.system(instruction),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        // Room for the (short) answer plus any default thinking tokens.
        maxOutputTokens: 1024,
      ),
    );
    final r = await m
        .generateContent([
          for (final t in history) t.user ? Content.text(t.text) : Content.model([TextPart(t.text)]),
          Content.text(prompt),
        ])
        .timeout(const Duration(seconds: 45));
    return r.text;
  }
}
