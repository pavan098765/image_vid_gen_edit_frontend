import 'gemini_client.dart';

class CreativePass {
  final Map<String, dynamic> json;
  final List<String> failures;
  final bool handedToUser;

  const CreativePass({
    required this.json,
    required this.failures,
    required this.handedToUser,
  });
}

List<String> criticFailures(Map<String, dynamic> body) {
  final raw = body['failures'];
  if (raw is! List) return const [];
  return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
}

/// Writer, critic, one revision, then a local check. Three failed checks
/// stop and hand the last draft to the user.
class CreativeSteps {
  CreativeSteps(this.director);

  final GeminiDirector director;

  Future<CreativePass> run({
    required String step,
    required String instruction,
    required String rubric,
    required List<String> Function(Map<String, dynamic> json) hardCheck,
    Map<String, dynamic>? schema,
    bool search = false,
  }) async {
    var last = <String, dynamic>{};
    var lastHard = <String>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      final writerInstruction = attempt == 0
          ? instruction
          : '$instruction\nFix these problems and keep everything that already works:\n${lastHard.join('\n')}';
      var written = await director.generate(
        step: step,
        instruction: writerInstruction,
        schema: schema,
        search: search && attempt == 0,
      );
      final critic = await director.generate(
        step: '${step}_critic',
        instruction: 'Rubric:\n$rubric\nDraft:\n$written\n'
            'Return {"failures":[]}. An empty list means the draft passes. '
            'Name only concrete failures from the rubric.',
      );
      final soft = criticFailures(critic);
      if (soft.isNotEmpty) {
        written = await director.generate(
          step: step,
          instruction: '$writerInstruction\nA review rejected this draft:\n${soft.join('\n')}\nRevise it once.',
          schema: schema,
        );
      }
      last = written;
      lastHard = hardCheck(written);
      if (lastHard.isEmpty) {
        return CreativePass(json: written, failures: const [], handedToUser: false);
      }
    }
    return CreativePass(json: last, failures: lastHard, handedToUser: true);
  }
}
