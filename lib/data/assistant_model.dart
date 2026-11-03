import 'package:firebase_ai/firebase_ai.dart';

import '../domain/assistant_conversation.dart';

/// [AssistantModel] on Firebase AI Logic (Gemini Developer API backend,
/// App Check token attached automatically by the SDK — ADR-029). Stateless:
/// every call sends the system instruction, the kept history and the new
/// question, which is what a chat session sends anyway.
class FirebaseAssistantModel implements AssistantModel {
  const FirebaseAssistantModel();

  @override
  Future<String?> generate({
    required String model,
    required String instruction,
    required List<AssistantTurn> history,
    required String prompt,
  }) async {
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
