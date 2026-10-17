import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef DirectorCall = Future<Map<String, dynamic>> Function({
  required String step,
  required String instruction,
  Map<String, dynamic>? schema,
  bool search,
});

/// Director calls. The worker is deployed from the backend repo
/// (`cloudflare/gemini_worker`) as kala-gemini-director.
class GeminiDirector {
  GeminiDirector({
    this.endpoint = const String.fromEnvironment(
      'GEMINI_WORKER_URL',
      defaultValue: 'https://kala-gemini-director.pavanalur3.workers.dev/v1/generate',
    ),
    this.model = 'gemini-3.5-flash-lite',
    this.override,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String endpoint;
  final String model;
  final DirectorCall? override;
  final http.Client _client;

  Future<Map<String, dynamic>> generate({
    required String step,
    required String instruction,
    Map<String, dynamic>? schema,
    bool search = false,
  }) async {
    if (override != null) {
      return override!(step: step, instruction: instruction, schema: schema, search: search);
    }
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to write this film.');
    }
    final body = <String, dynamic>{
      'step': step,
      'model': model,
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': instruction},
          ],
        },
      ],
      if (schema != null) 'responseSchema': schema,
      if (search) 'tools': [
        {'google_search': <String, dynamic>{}},
      ],
    };
    final resp = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode == 401) {
      throw StateError('Sign in to write this film.');
    }
    if (resp.statusCode >= 400) {
      debugPrint('Director step $step failed (${resp.statusCode})');
      throw StateError('The writing step failed. Try it again.');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('The writing step returned nothing.');
    }
    return _jsonFromGemini(decoded);
  }

  Map<String, dynamic> _jsonFromGemini(Map<String, dynamic> body) {
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      const direct = ['findings', 'angles', 'shots', 'failures', 'lines', 'plan', 'lock', 'assets'];
      if (direct.any(body.containsKey)) return body;
      throw StateError('The writing step returned nothing.');
    }
    final parts = ((candidates.first as Map)['content'] as Map?)?['parts'];
    final text = parts is List
        ? parts.map((p) => (p as Map)['text'] ?? '').join('\n')
        : '';
    final cleaned = text.trim().replaceFirst(RegExp(r'^```json'), '').replaceFirst(RegExp(r'```$'), '').trim();
    final parsed = jsonDecode(cleaned);
    if (parsed is Map<String, dynamic>) return parsed;
    throw StateError('The writing step was not usable.');
  }
}
