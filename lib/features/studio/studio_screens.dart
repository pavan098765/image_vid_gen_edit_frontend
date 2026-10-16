import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/state/editor_providers.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/video_editor_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'asset_use.dart';
import 'studio_assembler.dart';
import 'studio_session.dart';
import 'studio_store.dart';
import 'workflow_models.dart';
import 'workflow_quote.dart';

class StudioScope extends InheritedNotifier<StudioSession> {
  const StudioScope({
    super.key,
    required StudioSession session,
    required super.child,
  }) : super(notifier: session);

  static StudioSession of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<StudioScope>()!.notifier!;
  }
}

class StudioShelf extends StatelessWidget {
  const StudioShelf({super.key, required this.workflows});

  final List<WorkflowSpec> workflows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'What will you make?',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final film = workflows[index];
                    return _FilmCard(
                      film: film,
                      tint: _tints[index % _tints.length],
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        final session = StudioScope.of(context);
                        session.open(film);
                        final saved = await StudioDraftStore().latestFor(film.id);
                        if (!context.mounted) return;
                        if (saved != null && saved.stage != 'intake' && saved.stage != 'research') {
                          session.restore(saved);
                          final page = saved.stage == 'angles'
                              ? const StudioAnglesPage()
                              : saved.stage == 'generating'
                                  ? const StudioMakingPage()
                                  : const StudioOutlinePage();
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const StudioSetupPage()),
                        );
                      },
                    );
                  },
                  childCount: workflows.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilmCard extends StatelessWidget {
  const _FilmCard({required this.film, required this.tint, required this.onTap});
  final WorkflowSpec film;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tint.withValues(alpha: 0.95), cs.surface],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(film.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    film.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.25),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _tints = [
  Color(0xFF3D4A7A),
  Color(0xFF6B3A4A),
  Color(0xFF2F5D50),
  Color(0xFF5C4A2E),
  Color(0xFF3A3F66),
  Color(0xFF4A3048),
  Color(0xFF1E4D5C),
  Color(0xFF3E4A32),
  Color(0xFF4A3B32),
  Color(0xFF2C3E5A),
];

class StudioSetupPage extends StatefulWidget {
  const StudioSetupPage({super.key});

  @override
  State<StudioSetupPage> createState() => _StudioSetupPageState();
}

class _StudioSetupPageState extends State<StudioSetupPage> {
  final _topic = TextEditingController();
  int _length = 60;
  String _aspect = '9:16';
  String _language = 'English';
  bool _captions = true;
  bool _music = true;
  bool _narrator = false;
  String _engine = 'auto';
  bool _seeded = false;
  final List<String> _files = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spec = StudioScope.of(context).spec;
    if (spec != null && !_seeded) {
      _seeded = true;
      _length = spec.defaultLength;
      _aspect = spec.defaultAspect;
      _music = spec.music;
      _narrator = spec.speech == 'optional';
      final pending = StudioScope.of(context).pendingFiles;
      if (pending.isNotEmpty && _files.isEmpty) {
        _files.addAll(pending);
      }
    }
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = StudioScope.of(context);
    final spec = session.spec!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  IconButton(
                    alignment: Alignment.centerLeft,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.arrowLeft),
                  ),
                  Text(spec.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(spec.blurb, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _topic,
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 22, height: 1.3),
                    decoration: const InputDecoration(
                      hintText: 'What is this film about?',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final seconds in spec.lengths)
                        ChoiceChip(
                          label: Text(_lengthLabel(seconds)),
                          selected: _length == seconds,
                          onSelected: (_) => setState(() => _length = seconds),
                        ),
                      for (final shape in spec.aspects)
                        ChoiceChip(
                          label: Text(shape == '9:16' ? 'Vertical' : 'Wide'),
                          selected: _aspect == shape,
                          onSelected: (_) => setState(() => _aspect = shape),
                        ),
                      for (final lang in const ['English', 'Hindi', 'Spanish'])
                        ChoiceChip(
                          label: Text(lang),
                          selected: _language == lang,
                          onSelected: (_) => setState(() => _language = lang),
                        ),
                      FilterChip(
                        label: const Text('Captions'),
                        selected: _captions,
                        onSelected: (v) => setState(() => _captions = v),
                      ),
                      if (spec.speech == 'optional')
                        FilterChip(
                          label: const Text('Narrator'),
                          selected: _narrator,
                          onSelected: (v) => setState(() => _narrator = v),
                        ),
                    ],
                  ),
                  if (!spec.skips('generate')) ...[
                    const SizedBox(height: 16),
                    Text('Motion', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 8),
                    _MotionChoice(
                      engine: _engine,
                      onSelected: (engine) => setState(() => _engine = engine),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final path in _files)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Tooltip(
                              message: classifyAsset(path).note.isEmpty
                                  ? path.split(RegExp(r'[/\\]')).last
                                  : classifyAsset(path).note,
                              child: Container(
                              width: 88,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(LucideIcons.fileVideo),
                                  const SizedBox(height: 4),
                                  Text(
                                    _assetLabel(classifyAsset(path).role),
                                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            ),
                          ),
                        InkWell(
                          onTap: _addFile,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 72,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: const Icon(LucideIcons.plus),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (session.message != null) ...[
                    const SizedBox(height: 12),
                    Text(session.message!, style: TextStyle(color: cs.error)),
                  ],
                ],
              ),
            ),
            _PrimaryBar(
              label: session.busy ? 'Working' : 'Continue',
              enabled: !session.busy,
              onPressed: () async {
                if (_topic.text.trim().isEmpty && !spec.requiresFiles) {
                  setState(() {});
                  return;
                }
                await session.begin(
                  topic: _topic.text,
                  durationSeconds: _length,
                  aspect: _aspect,
                  language: _language,
                  captions: _captions,
                  music: _music,
                  narratorOn: spec.speech == 'optional' ? _narrator : spec.speech != 'none',
                  files: _files,
                  videoEngine: _engine,
                );
                if (!context.mounted || session.draft == null) return;
                final stage = session.draft!.stage;
                if (stage != 'angles' && stage != 'outline') return;
                final next = stage == 'angles' ? const StudioAnglesPage() : const StudioOutlinePage();
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => next));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFile() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _files.add(file.path));
  }
}

class StudioAnglesPage extends StatelessWidget {
  const StudioAnglesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = StudioScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final angles = session.draft?.angles ?? const [];
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  Text('Three ways in', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    session.busy ? session.draft?.topic ?? '' : 'Pick the film you want written.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  if (session.busy) const LinearProgressIndicator(),
                  for (var i = 0; i < angles.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: session.pickedAngle == i ? cs.secondaryContainer : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: session.busy ? null : () => session.selectAngle(i),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (angles[i]['hook'] as String?) ?? 'Angle ${i + 1}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text((angles[i]['ending'] as String?) ?? ''),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (session.message != null)
                    Text(session.message!, style: TextStyle(color: cs.error)),
                ],
              ),
            ),
            _PrimaryBar(
              label: 'Write this one',
              enabled: !session.busy && session.pickedAngle != null,
              onPressed: () async {
                await session.chooseAngle(session.pickedAngle!);
                if (!context.mounted || session.draft?.stage != 'outline') return;
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudioOutlinePage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class StudioOutlinePage extends StatelessWidget {
  const StudioOutlinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = StudioScope.of(context);
    final film = session.draft;
    final cs = Theme.of(context).colorScheme;
    final quote = session.quote;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  Text('Outline', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (session.message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(session.message!, style: TextStyle(color: cs.error)),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('With music'),
                    value: film?.music ?? false,
                    onChanged: session.setMusic,
                  ),
                  if (session.spec?.skips('generate') != true) ...[
                    const SizedBox(height: 4),
                    Text('Motion', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 8),
                    _MotionChoice(
                      engine: film?.videoEngine ?? 'auto',
                      onSelected: session.setVideoEngine,
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final shot in film?.shots ?? const [])
                    if (!shot.dropped)
                      Card(
                        elevation: 0,
                        color: cs.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(shot.chapter, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(shot.action),
                              if ((shot.referenceRole ?? '').isNotEmpty)
                                Text(
                                  (shot.referencePath ?? '').startsWith('look:')
                                      ? 'Uses the ${_assetLabel(shot.referenceRole!)}'
                                      : 'Uses your ${_assetLabel(shot.referenceRole!)}',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                                ),
                              if (shot.line.isNotEmpty)
                                TextButton(
                                  onPressed: () => _editLine(context, session, shot.id, shot.line),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(shot.line),
                                  ),
                                ),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text('${shot.durationSeconds}s'),
                                  if (shot.kind != 'user')
                                    ChoiceChip(
                                      label: Text(shot.kind == 'video' ? 'Video' : 'Still'),
                                      selected: shot.kind == 'video',
                                      onSelected: (_) => session.flipKind(shot.id),
                                    ),
                                  TextButton(
                                    onPressed: () => session.dropShot(shot.id),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  for (final line in quote?.lines ?? const [])
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text('${line.label} ${line.gems}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ),
                  const Spacer(),
                  Text('${quote?.total ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
            ),
            _PrimaryBar(
              label: 'Make it',
              enabled: !session.busy && (quote?.total ?? 0) >= 0 && film != null,
              onPressed: () async {
                await session.make();
                if (!context.mounted) return;
                if (session.draft?.stage == 'generating') {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StudioMakingPage()),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLine(BuildContext context, StudioSession session, String id, String line) async {
    final controller = TextEditingController(text: line);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Line'),
        content: TextField(controller: controller, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (next != null) session.editLine(id, next);
  }
}

class StudioMakingPage extends ConsumerWidget {
  const StudioMakingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = StudioScope.of(context);
    final film = session.draft;
    final cs = Theme.of(context).colorScheme;
    final ready = film?.shots.any((s) => (s.localPath ?? '').isNotEmpty) ?? false;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Making your film', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(film?.topic ?? '', style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  for (final asset in film?.assets.where((a) => a.isMade) ?? const <UserAsset>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${_lookTitle(session, asset)} · ${(asset.r2Key ?? '').isEmpty ? 'Making' : 'Ready'}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  for (final shot in film?.shots.where((s) => !s.dropped) ?? const <ShotCard>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MakingCard(
                        shot: shot,
                        gems: _shotGems(session, shot),
                        onAgain: shot.kind == 'user' ? null : () => session.regenerateShot(shot.id),
                      ),
                    ),
                  if (film != null && film.jobs.keys.any((k) => k.startsWith('voice')))
                    ListTile(
                      dense: true,
                      title: const Text('Voice'),
                      subtitle: Text(film.files.keys.any((k) => k.startsWith('voice')) ? 'Ready' : 'On its way'),
                      trailing: TextButton(
                        onPressed: session.busy ? null : () => session.regenerateVoice(),
                        child: Text('Again · ${session.costs.speechCost}'),
                      ),
                    ),
                  if (film != null && film.jobs.keys.any((k) => k.startsWith('music')))
                    ListTile(
                      dense: true,
                      title: const Text('Music'),
                      subtitle: Text(film.files.containsKey('music') ? 'Ready' : 'On its way'),
                    ),
                  if (film != null && (film.lock.isNotEmpty))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: session.busy
                            ? null
                            : () async {
                                final premise = await _askPremise(context, film.topic);
                                if (premise == null || premise.trim().isEmpty) return;
                                await session.partTwo(premise.trim());
                                if (!context.mounted) return;
                                final stage = session.draft?.stage;
                                if (stage != 'angles' && stage != 'outline') return;
                                final page = stage == 'angles' ? const StudioAnglesPage() : const StudioOutlinePage();
                                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
                              },
                        child: const Text('Part 2'),
                      ),
                    ),
                  if (session.message != null)
                    Text(session.message!, style: TextStyle(color: cs.error)),
                ],
              ),
            ),
            _PrimaryBar(
              label: 'Open in editor',
              enabled: ready,
              onPressed: () {
                final spec = session.spec!;
                final voiceByChapter = <String, String>{
                  for (final entry in film!.files.entries)
                    if (entry.key.startsWith('voice:')) entry.key.substring(6): entry.value,
                };
                final assembled = assembleFilm(
                  draft: film,
                  spec: spec,
                  mediaPaths: {
                    for (final shot in film.shots)
                      if ((shot.localPath ?? '').isNotEmpty) shot.id: shot.localPath!,
                  },
                  voiceByChapter: voiceByChapter,
                  musicPath: film.files['music'],
                );
                ref.read(projectProvider.notifier).replaceProject(assembled.project);
                final first = film.shots.map((s) => s.localPath).whereType<String>().firstWhere((p) => p.isNotEmpty, orElse: () => '');
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VideoEditorPage(
                      initialVideoPath: first.isEmpty ? null : first,
                      useExistingProject: true,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MakingCard extends StatefulWidget {
  const _MakingCard({required this.shot, required this.gems, this.onAgain});
  final ShotCard shot;
  final int gems;
  final VoidCallback? onAgain;

  @override
  State<_MakingCard> createState() => _MakingCardState();
}

class _MakingCardState extends State<_MakingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = (widget.shot.localPath ?? '').isNotEmpty;
    return FadeTransition(
      opacity: done ? const AlwaysStoppedAnimation(1) : Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 72,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.shot.action)),
            if (!done)
              Text('${widget.gems}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))
            else if (widget.onAgain != null)
              TextButton(
                onPressed: widget.onAgain,
                child: Text('Again · ${widget.gems}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryBar extends StatelessWidget {
  const _PrimaryBar({required this.label, required this.onPressed, required this.enabled});
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

String _lookTitle(StudioSession session, UserAsset asset) {
  if (asset.role == 'character') {
    return session.spec?.id == 'creature_eye' ? 'Creature sheet' : 'Character sheet';
  }
  return 'Set';
}

String _assetLabel(String role) {
  switch (role) {
    case 'character':
      return 'Character';
    case 'background':
      return 'Set';
    case 'product':
      return 'Product';
    case 'footage':
      return 'Footage';
    case 'reference':
      return 'Look';
    default:
      return 'File';
  }
}

int _shotGems(StudioSession session, ShotCard shot) {
  if (shot.kind != 'video') return session.costs.imageCost;
  final base = shot.model.startsWith('ltx') ? session.costs.ltxBase5 : session.costs.h3Base5;
  return session.costs.imageCost + videoGems(base, shot.durationSeconds);
}

Future<String?> _askPremise(BuildContext context, String topic) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Part 2'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: InputDecoration(hintText: topic.isEmpty ? 'A new premise' : 'After $topic'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Continue')),
      ],
    ),
  );
}

String _lengthLabel(int seconds) {
  if (seconds < 90) return '${seconds}s';
  final minutes = seconds / 60;
  if (minutes == minutes.roundToDouble()) return '${minutes.round()} min';
  return '${minutes.toStringAsFixed(1)} min';
}

class _MotionChoice extends StatelessWidget {
  const _MotionChoice({required this.engine, required this.onSelected});
  final String engine;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const choices = [
      ('auto', 'Auto'),
      ('minimax_h3', 'Cinemotion Pro'),
      ('ltx25_int8_t2v', 'CineReal'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              ChoiceChip(
                label: Text(choice.$2),
                selected: engine == choice.$1,
                onSelected: (_) => onSelected(choice.$1),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Auto picks per shot. Cinemotion Pro follows acting. CineReal follows the camera.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}
