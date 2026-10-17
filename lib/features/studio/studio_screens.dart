import 'dart:io';

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
  String? _promptNote;

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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _BackHeader(
                    eyebrow: 'Start here',
                    title: spec.title,
                    subtitle: spec.blurb,
                  ),
                  const SizedBox(height: 20),
                  _SoftField(
                    controller: _topic,
                    hint: _topicHint(spec),
                    note: _promptNote,
                    onChanged: (_) {
                      if (_promptNote != null) setState(() => _promptNote = null);
                    },
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle('How long', 'Pick a length you can watch in one sitting.'),
                  const SizedBox(height: 10),
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
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle('Frame', 'Vertical for a phone. Wide for a screen.'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final shape in spec.aspects) ...[
                        Expanded(
                          child: _ShapeCard(
                            label: shape == '9:16' ? 'Vertical' : 'Wide',
                            ratio: shape,
                            selected: _aspect == shape,
                            onTap: () => setState(() => _aspect = shape),
                          ),
                        ),
                        if (shape != spec.aspects.last) const SizedBox(width: 10),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle('Language', 'The words on screen and in the voice.'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final lang in const ['English', 'Hindi', 'Spanish'])
                        ChoiceChip(
                          label: Text(lang),
                          selected: _language == lang,
                          onSelected: (_) => setState(() => _language = lang),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SwitchCard(
                    icon: LucideIcons.captions,
                    title: 'Captions',
                    subtitle: 'Words sit on the picture.',
                    value: _captions,
                    onChanged: (v) => setState(() => _captions = v),
                  ),
                  _SwitchCard(
                    icon: LucideIcons.music,
                    title: 'Music',
                    subtitle: 'A bed under the film.',
                    value: _music,
                    onChanged: (v) => setState(() => _music = v),
                  ),
                  if (spec.speech == 'optional')
                    _SwitchCard(
                      icon: LucideIcons.mic,
                      title: 'Narrator',
                      subtitle: 'A voice walks the viewer through.',
                      value: _narrator,
                      onChanged: (v) => setState(() => _narrator = v),
                    ),
                  if (!spec.skips('generate')) ...[
                    const SizedBox(height: 8),
                    const _SectionTitle('Motion', 'How the camera should feel.'),
                    const SizedBox(height: 10),
                    _MotionChoice(
                      engine: _engine,
                      onSelected: (engine) => setState(() => _engine = engine),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _SectionTitle(
                    'Bring something with you',
                    spec.requiresFiles
                        ? 'Add a video to cut. A photo can set the face or the place.'
                        : 'Optional. A photo becomes the face or the place. A video is cut in as footage.',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 112,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _files.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _AssetTile(
                              path: _files[i],
                              onRemove: () => setState(() => _files.removeAt(i)),
                            ),
                          ),
                        _AddAssetTile(onTap: _addFile),
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
                final topic = _topic.text.trim();
                if (topic.isEmpty && !spec.requiresFiles) {
                  setState(() => _promptNote = 'One sentence is enough to begin.');
                  return;
                }
                if (spec.requiresFiles && !_files.any(isVideoAssetPath)) {
                  setState(() => _promptNote = 'Add a video to cut. A photo can come along as the look.');
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
    final picker = ImagePicker();
    try {
      final picked = await picker.pickMultipleMedia();
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _files.addAll(picked.map((file) => file.path));
        _promptNote = null;
      });
    } catch (_) {
      if (!mounted) return;
      final kind = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => const _MediaKindSheet(),
      );
      if (!mounted || kind == null) return;
      final file = kind == 'video'
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery);
      if (!mounted || file == null) return;
      setState(() {
        _files.add(file.path);
        _promptNote = null;
      });
    }
  }
}

String _topicHint(WorkflowSpec spec) {
  switch (spec.id) {
    case 'cut_my_clips':
      return 'What should these clips feel like?';
    case 'explainer':
      return 'What should people understand?';
    case 'podcast':
      return 'What are you talking about?';
    case 'countdown':
      return 'What are we counting toward?';
    default:
      return 'A sentence is enough. What is this film about?';
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const _BackHeader(
                    eyebrow: 'Choose a way in',
                    title: 'Three openings',
                    subtitle: 'Same story, three different first moments. Pick the one you want written.',
                  ),
                  const SizedBox(height: 18),
                  if ((session.draft?.topic ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        session.draft!.topic,
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                      ),
                    ),
                  if (session.busy) const LinearProgressIndicator(),
                  for (var i = 0; i < angles.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: session.pickedAngle == i ? cs.secondaryContainer : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: session.busy
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  session.selectAngle(i);
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Way ${i + 1}',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (angles[i]['hook'] as String?) ?? 'Angle ${i + 1}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.25),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  (angles[i]['ending'] as String?) ?? '',
                                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                                ),
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
              label: 'Write this opening',
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  const _BackHeader(
                    eyebrow: 'Before we make it',
                    title: 'Your film, shot by shot',
                    subtitle: 'Tap a spoken line to rewrite it. Still or video is your call.',
                  ),
                  const SizedBox(height: 16),
                  if (session.message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(session.message!, style: TextStyle(color: cs.error)),
                    ),
                  _SwitchCard(
                    icon: LucideIcons.music,
                    title: 'Music',
                    subtitle: 'Keep a bed under the picture.',
                    value: film?.music ?? false,
                    onChanged: session.setMusic,
                  ),
                  if (session.spec?.skips('generate') != true) ...[
                    const SizedBox(height: 8),
                    const _SectionTitle('Motion', 'Change it if a shot should feel different.'),
                    const SizedBox(height: 10),
                    _MotionChoice(
                      engine: film?.videoEngine ?? 'auto',
                      onSelected: session.setVideoEngine,
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (final shot in film?.shots ?? const [])
                    if (!shot.dropped)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shot.chapter,
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(shot.action, style: const TextStyle(height: 1.35)),
                                if ((shot.referenceRole ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    (shot.referencePath ?? '').startsWith('look:')
                                        ? 'Uses the ${_assetLabel(shot.referenceRole!)} we make'
                                        : 'Uses your ${_assetLabel(shot.referenceRole!).toLowerCase()}',
                                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                                  ),
                                ],
                                if (shot.line.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => _editLine(context, session, shot.id, shot.line),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: cs.surface,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          shot.line,
                                          style: const TextStyle(height: 1.35, fontStyle: FontStyle.italic),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${shot.durationSeconds}s',
                                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                                    ),
                                    const SizedBox(width: 8),
                                    if (shot.kind != 'user')
                                      ChoiceChip(
                                        label: Text(shot.kind == 'video' ? 'Video' : 'Still'),
                                        selected: shot.kind == 'video',
                                        onSelected: (_) => session.flipKind(shot.id),
                                      ),
                                    const Spacer(),
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
              label: 'Make the film',
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
      builder: (context) => _NoteDialog(
        title: 'Rewrite this line',
        hint: 'Say it the way you would out loud.',
        controller: controller,
        action: 'Keep this',
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
                  const _BackHeader(
                    eyebrow: 'In progress',
                    title: 'Making your film',
                    subtitle: 'Each piece lands here. You can redo a shot when it is ready.',
                  ),
                  if ((film?.topic ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(film!.topic, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
                  ],
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
    builder: (context) => _NoteDialog(
      title: 'What happens next?',
      hint: topic.isEmpty ? 'A new premise' : 'After $topic',
      controller: controller,
      action: 'Continue',
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
      ('auto', 'Auto', 'We pick the feel of each shot.'),
      ('minimax_h3', 'Cinemotion Pro', 'Follows the acting.'),
      ('ltx25_int8_t2v', 'CineReal', 'Follows the camera.'),
    ];
    return Column(
      children: [
        for (final choice in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: engine == choice.$1 ? cs.secondaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(choice.$1);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        engine == choice.$1 ? LucideIcons.circleCheck : LucideIcons.circle,
                        size: 18,
                        color: engine == choice.$1 ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(choice.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              choice.$3,
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.eyebrow, required this.title, required this.subtitle});

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(LucideIcons.arrowLeft),
        ),
        Text(
          eyebrow,
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.3)),
      ],
    );
  }
}

class _SoftField extends StatelessWidget {
  const _SoftField({
    required this.controller,
    required this.hint,
    this.note,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String? note;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: 18,
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              border: InputBorder.none,
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _ShapeCard extends StatelessWidget {
  const _ShapeCard({
    required this.label,
    required this.ratio,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String ratio;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vertical = ratio == '9:16';
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Container(
                width: vertical ? 28 : 44,
                height: vertical ? 44 : 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    width: selected ? 2 : 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: SwitchListTile(
          secondary: Icon(icon, size: 18, color: cs.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final asset = classifyAsset(path);
    final video = isVideoAssetPath(path);
    return Tooltip(
      message: asset.note.isEmpty ? path.split(RegExp(r'[/\\]')).last : asset.note,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: video
                          ? ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(LucideIcons.clapperboard, color: cs.primary),
                            )
                          : Image.file(
                              File(path),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(LucideIcons.image, color: cs.primary),
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onRemove,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(LucideIcons.x, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _assetLabel(asset.role),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAssetTile extends StatelessWidget {
  const _AddAssetTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Expanded(
            child: Material(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.imagePlus, color: cs.primary),
                    const SizedBox(height: 6),
                    Text(
                      'Photo or\nvideo',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, height: 1.2, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _MediaKindSheet extends StatelessWidget {
  const _MediaKindSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Photo'),
              subtitle: const Text('A face, a product, or a place'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.clapperboard),
              title: const Text('Video'),
              subtitle: const Text('Footage to cut into the film'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatelessWidget {
  const _NoteDialog({
    required this.title,
    required this.hint,
    required this.controller,
    required this.action,
  });

  final String title;
  final String hint;
  final TextEditingController controller;
  final String action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 4,
        autofocus: true,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(action),
        ),
      ],
    );
  }
}
