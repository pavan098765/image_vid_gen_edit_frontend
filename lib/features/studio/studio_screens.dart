import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/app_menu_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/state/editor_providers.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/video_editor_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'asset_use.dart';
import 'studio_assembler.dart';
import 'studio_intake.dart';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const KalaTabAppBar(),
      body: workflows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: workflows.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 14 : 10),
              itemBuilder: (context, index) {
                if (index == 0) return const _StudioIntro();
                final film = workflows[index - 1];
                return _FilmRow(
                  film: film,
                  tint: _tints[(index - 1) % _tints.length],
                  onTap: () => _openFilm(context, film),
                );
              },
            ),
    );
  }
}

Future<void> _openFilm(BuildContext context, WorkflowSpec film) async {
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
}

class _StudioIntro extends StatelessWidget {
  const _StudioIntro();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What will you make?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick a film. Kala writes the shots, then you review them.',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
        ),
      ],
    );
  }
}

class _FilmRow extends StatelessWidget {
  const _FilmRow({required this.film, required this.tint, required this.onTap});
  final WorkflowSpec film;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final length = _lengthLabel(film.defaultLength);
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_filmIcon(film.id), color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      film.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      film.blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.25, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$length · ${film.defaultAspect}',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _filmIcon(String id) {
  switch (id) {
    case 'narrated_story':
      return LucideIcons.bookOpen;
    case 'explainer':
      return LucideIcons.lightbulb;
    case 'podcast':
      return LucideIcons.headphones;
    case 'what_if_diary':
      return LucideIcons.notebookPen;
    case 'time_travel_pov':
      return LucideIcons.clock;
    case 'body':
      return LucideIcons.heartPulse;
    case 'fpv':
      return LucideIcons.plane;
    case 'creature_eye':
      return LucideIcons.eye;
    case 'cut_my_clips':
      return LucideIcons.scissors;
    case 'countdown':
      return LucideIcons.listOrdered;
    case 'song_video':
      return LucideIcons.music;
    default:
      return LucideIcons.clapperboard;
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
  String _finish = 'balanced';
  String _weather = 'Day';
  bool _seeded = false;
  bool _showEngine = false;
  final List<_Brought> _files = [];
  final _voice = TextEditingController();
  final _musicFeel = TextEditingController();
  final _detail = TextEditingController();
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
        final role = spec.requiresFiles ? 'footage' : null;
        _files.addAll(pending.map((path) => _Brought(path, role: role, slot: spec.requiresFiles ? 'Video' : null)));
      }
    }
  }

  @override
  void dispose() {
    _topic.dispose();
    _voice.dispose();
    _musicFeel.dispose();
    _detail.dispose();
    for (final file in _files) {
      file.label.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = StudioScope.of(context);
    final spec = session.spec!;
    final intake = intakeFor(spec);
    final cs = Theme.of(context).colorScheme;
    final files = _fileSection(intake);
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                  if (intake.filesFirst) ...[
                    const SizedBox(height: 18),
                    files,
                  ],
                  const SizedBox(height: 20),
                  _SectionTitle(intake.topicLabel, intake.topicHint),
                  const SizedBox(height: 10),
                  _SoftField(
                    controller: _topic,
                    hint: intake.topicHint,
                    note: _promptNote,
                    onChanged: (_) {
                      if (_promptNote != null) setState(() => _promptNote = null);
                    },
                  ),
                  if (intake.detailKind.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _SectionTitle(intake.detailLabel, intake.detailHint),
                    const SizedBox(height: 10),
                    _SoftField(
                      controller: _detail,
                      hint: intake.detailHint,
                      lines: intake.detailLines,
                    ),
                  ],
                  if (intake.weather) ...[
                    const SizedBox(height: 18),
                    const _SectionTitle('Weather', 'One light for the whole flight.'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final light in const ['Dawn', 'Day', 'Dusk', 'Night', 'Storm'])
                          ChoiceChip(
                            label: Text(light),
                            selected: _weather == light,
                            onSelected: (_) => setState(() => _weather = light),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  _SectionTitle('How long', intake.lengthNote),
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
                  if (spec.aspects.length < 2)
                    _PictureCard(
                      title: spec.aspects.first == '9:16' ? 'Vertical' : 'Wide',
                      body: spec.aspects.first == '9:16'
                          ? 'This film is vertical, so it fills a phone.'
                          : 'This film is wide, for a screen.',
                    )
                  else ...[
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
                  ],
                  if (intake.showLanguage) ...[
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
                  ],
                  if (intake.showVoice && (spec.speech != 'optional' || _narrator)) ...[
                    const SizedBox(height: 18),
                    _SectionTitle('Voice', intake.voiceHint),
                    const SizedBox(height: 10),
                    _SoftField(controller: _voice, hint: intake.voiceHint),
                  ],
                  if (intake.showCaptions || intake.showMusic || intake.showNarrator) ...[
                    const SizedBox(height: 18),
                    _SoundGroup(
                      captions: intake.showCaptions ? _captions : null,
                      music: intake.showMusic ? _music : null,
                      narrator: intake.showNarrator ? _narrator : null,
                      onCaptions: (v) => setState(() => _captions = v),
                      onMusic: (v) => setState(() => _music = v),
                      onNarrator: (v) => setState(() => _narrator = v),
                    ),
                  ],
                  if (intake.showMusic && _music && intake.detailKind != 'lyrics') ...[
                    const SizedBox(height: 12),
                    _SoftField(
                      controller: _musicFeel,
                      hint: 'Music under the film. Sparse, no vocals.',
                      lines: 2,
                    ),
                  ],
                  const SizedBox(height: 18),
                  _PictureCard(title: 'How it is shot', body: intake.picture),
                  if (!spec.skips('generate')) ...[
                    const SizedBox(height: 18),
                    const _SectionTitle('Finish', 'The fine pass costs more and holds detail longer.'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Balanced'),
                          selected: _finish == 'balanced',
                          onSelected: (_) => setState(() => _finish = 'balanced'),
                        ),
                        ChoiceChip(
                          label: const Text('Finest'),
                          selected: _finish == 'finest',
                          onSelected: (_) => setState(() => _finish = 'finest'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _finish == 'finest'
                          ? 'Every shot takes the long refine.'
                          : 'The opening, the turn, and the ending take the long refine. The shots between stay on the faster refine.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.3),
                    ),
                  ],
                  if (!intake.filesFirst && intake.slots.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    files,
                  ],
                  if (intake.allowEngine && !spec.skips('generate')) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showEngine = !_showEngine),
                        icon: Icon(_showEngine ? LucideIcons.chevronUp : LucideIcons.clapperboard, size: 16),
                        label: Text(_showEngine ? 'Hide the camera choice' : 'Use one camera for every shot'),
                      ),
                    ),
                    if (_showEngine)
                      _MotionChoice(
                        engine: _engine,
                        onSelected: (engine) => setState(() => _engine = engine),
                      ),
                  ],
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
                final detail = _detail.text.trim();
                if (topic.isEmpty && detail.isEmpty && !spec.requiresFiles) {
                  setState(() => _promptNote = 'One sentence is enough to begin.');
                  return;
                }
                if (spec.requiresFiles && !_files.any((file) => isVideoAssetPath(file.path))) {
                  setState(() => _promptNote = 'Add a video to cut. A photo can come along as the look.');
                  return;
                }
                final voiceOn = spec.speech != 'none' && (spec.speech != 'optional' || _narrator);
                final speakers = intake.detailKind == 'speakers' ? detail : '';
                final object = intake.detailKind == 'object' ? detail : '';
                final lockBits = <String>[
                  if (intake.weather) 'Weather: $_weather. One lens, one height. No face.',
                  if (object.isNotEmpty) 'The modern object is $object. It stays recognizable.',
                ];
                await session.begin(
                  topic: [topic, if (speakers.isNotEmpty) 'Speakers: $speakers'].where((s) => s.isNotEmpty).join('\n'),
                  durationSeconds: _length,
                  aspect: _aspect,
                  language: intake.showLanguage ? _language : 'English',
                  captions: intake.showCaptions && _captions,
                  music: intake.showMusic && _music,
                  narratorOn: spec.speech == 'optional' ? _narrator : spec.speech != 'none',
                  files: _files.map((file) => file.path).toList(),
                  labeledFiles: [
                    for (final file in _files)
                      (
                        path: file.path,
                        role: file.role ?? '',
                        label: file.label.text.trim(),
                      ),
                  ],
                  carryLock: lockBits.join(' '),
                  musicNote: intake.showMusic && _music ? _musicFeel.text : '',
                  lyrics: intake.detailKind == 'lyrics' ? detail : '',
                  voiceHint: !voiceOn
                      ? ''
                      : speakers.isNotEmpty
                          ? speakers
                          : _voice.text,
                  videoEngine: intake.allowEngine ? _engine : 'auto',
                  finish: _finish,
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

  Widget _fileSection(ProductIntake intake) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(intake.filesTitle, intake.filesNote),
        const SizedBox(height: 8),
        for (final slot in intake.slots) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      slot.hint,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: () => _addLabeled(slot.role, slot.title), child: const Text('Add')),
            ],
          ),
          for (final file in _files.where((item) => item.slot == slot.title))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: file.label,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: slot.role == 'character' ? 'Name' : 'What this is',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      file.label.dispose();
                      setState(() => _files.remove(file));
                    },
                    icon: const Icon(LucideIcons.x, size: 16),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _addLabeled(String role, String slot) async {
    final picker = ImagePicker();
    final video = role == 'footage';
    final file = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() {
      _files.add(_Brought(file.path, role: role, slot: slot));
      _promptNote = null;
    });
  }
}

class _Brought {
  _Brought(this.path, {this.role, this.slot}) : label = TextEditingController();

  final String path;
  final String? role;
  final String? slot;
  final TextEditingController label;
}

class StudioAnglesPage extends StatelessWidget {
  const StudioAnglesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = StudioScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final angles = session.draft?.angles ?? const [];
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                        color: Colors.transparent,
                        child: Ink(
                          decoration: session.pickedAngle == i
                              ? BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.45),
                                  ),
                                )
                              : kalaGlassDecoration(isDark: isDark, radius: 20),
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
      backgroundColor: Colors.transparent,
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
                    subtitle: 'Tap a spoken line to rewrite it. Remove a shot you do not want.',
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
                  if (session.spec != null && session.spec!.skips('generate') != true) ...[
                    const SizedBox(height: 8),
                    _PictureCard(title: 'How it is shot', body: intakeFor(session.spec!).picture),
                    if (intakeFor(session.spec!).allowEngine) ...[
                      const SizedBox(height: 8),
                      _MotionChoice(
                        engine: film?.videoEngine ?? 'auto',
                        onSelected: session.setVideoEngine,
                      ),
                    ],
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
      backgroundColor: Colors.transparent,
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
      return 'Object';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const choices = [
      ('auto', 'Auto', 'We pick the feel of each shot.'),
      ('minimax_h3', 'Cinemotion Pro', 'Follows the acting.'),
      ('ltx25_int8_t2v', 'CineReal', 'Follows the camera.'),
    ];
    final selected = choices.firstWhere((choice) => choice.$1 == engine, orElse: () => choices.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: engine == choices[i].$1
                        ? BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.primary),
                          )
                        : kalaGlassDecoration(isDark: isDark, radius: 14),
                    child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelected(choices[i].$1);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Text(
                        choices[i].$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: engine == choices[i].$1 ? cs.onPrimaryContainer : cs.onSurface,
                        ),
                      ),
                    ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(selected.$3, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.3)),
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

class _PictureCard extends StatelessWidget {
  const _PictureCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: kalaGlassDecoration(isDark: isDark, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(height: 1.35, color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _SoftField extends StatelessWidget {
  const _SoftField({
    required this.controller,
    required this.hint,
    this.note,
    this.onChanged,
    this.lines = 3,
  });

  final TextEditingController controller;
  final String hint;
  final String? note;
  final ValueChanged<String>? onChanged;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: kalaGlassDecoration(isDark: isDark, radius: 20),
          child: TextField(
            controller: controller,
            minLines: lines,
            maxLines: lines < 3 ? lines : 6,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vertical = ratio == '9:16';
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: selected
            ? BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
              )
            : kalaGlassDecoration(isDark: isDark, radius: 16),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: kalaGlassDecoration(isDark: isDark, radius: 16),
          child: SwitchListTile(
          secondary: Icon(icon, size: 18, color: cs.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          value: value,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ),
    );
  }
}

class _SoundGroup extends StatelessWidget {
  const _SoundGroup({
    required this.captions,
    required this.music,
    required this.narrator,
    required this.onCaptions,
    required this.onMusic,
    required this.onNarrator,
  });

  final bool? captions;
  final bool? music;
  final bool? narrator;
  final ValueChanged<bool> onCaptions;
  final ValueChanged<bool> onMusic;
  final ValueChanged<bool> onNarrator;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[
      if (captions != null)
        _soundRow(cs, LucideIcons.captions, 'Captions', 'Words sit on the picture.', captions!, onCaptions),
      if (music != null)
        _soundRow(cs, LucideIcons.music, 'Music', 'A bed under the film. The shot keeps its own sound.', music!, onMusic),
      if (narrator != null)
        _soundRow(cs, LucideIcons.mic, 'Narrator', 'A voice walks the viewer through.', narrator!, onNarrator),
    ];
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: cs.outlineVariant),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _soundRow(
    ColorScheme cs,
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      secondary: Icon(icon, size: 18, color: cs.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
