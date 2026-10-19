import 'workflow_models.dart';

class IntakeSlot {
  const IntakeSlot({
    required this.role,
    required this.title,
    required this.hint,
    this.video = false,
  });

  final String role;
  final String title;
  final String hint;
  final bool video;
}

/// What the setup screen asks, per film. The worker can hold a face
/// (up to four references) or carry a camera from one frame to the next.
class ProductIntake {
  const ProductIntake({
    required this.topicLabel,
    required this.topicHint,
    required this.lengthNote,
    required this.picture,
    required this.filesTitle,
    required this.filesNote,
    this.showLanguage = true,
    this.showCaptions = true,
    this.showMusic = true,
    this.showNarrator = false,
    this.showVoice = false,
    this.allowEngine = false,
    this.weather = false,
    this.filesFirst = false,
    this.detailKind = '',
    this.detailLabel = '',
    this.detailHint = '',
    this.detailLines = 2,
    this.voiceHint = 'Same age and accent in every chapter.',
    this.slots = const [],
  });

  final String topicLabel;
  final String topicHint;
  final String lengthNote;
  final String picture;
  final String filesTitle;
  final String filesNote;
  final bool showLanguage;
  final bool showCaptions;
  final bool showMusic;
  final bool showNarrator;
  final bool showVoice;
  final bool allowEngine;
  final bool weather;
  final bool filesFirst;
  final String detailKind;
  final String detailLabel;
  final String detailHint;
  final int detailLines;
  final String voiceHint;
  final List<IntakeSlot> slots;
}

ProductIntake intakeFor(WorkflowSpec spec) {
  switch (spec.id) {
    case 'explainer':
      return const ProductIntake(
        topicLabel: 'The question',
        topicHint: 'What should someone understand by the end?',
        lengthNote: 'Long enough to teach one idea, and no longer.',
        picture:
            'Each point is a moving shot of a few seconds. A person is held to a face sheet. A diagram or a place is a camera move. The word on screen is the term, not the sentence.',
        filesTitle: 'Show something real',
        filesNote: 'Optional. A diagram, a place, or an object the film returns to.',
        showVoice: true,
        voiceHint: 'One clear voice. Same pace in every chapter.',
        allowEngine: true,
        slots: [
          IntakeSlot(role: 'background', title: 'Place or diagram', hint: 'The picture the point comes back to.'),
          IntakeSlot(role: 'product', title: 'Object', hint: 'Kept recognizable when it is the subject.'),
        ],
      );
    case 'podcast':
      return const ProductIntake(
        topicLabel: 'The episode',
        topicHint: 'What are the two of you talking about?',
        lengthNote: 'A conversation you can hear in one sitting.',
        picture:
            'The opening and the ending move. The middle holds on the two faces. Nobody talks to the camera, so the mouth is never asked to sync.',
        filesTitle: 'The two faces',
        filesNote: 'Optional photos. Without them, we draw both people and keep those drawings.',
        showVoice: false,
        detailKind: 'speakers',
        detailLabel: 'Who is talking',
        detailHint: 'Maya, warm and quick. Arun, dry and short.',
        detailLines: 2,
        slots: [
          IntakeSlot(role: 'character', title: 'First speaker', hint: 'One face, used whenever they are on screen.'),
          IntakeSlot(role: 'character', title: 'Second speaker', hint: 'A different face.'),
        ],
      );
    case 'what_if_diary':
      return const ProductIntake(
        topicLabel: 'The what-if',
        topicHint: 'What if you kept the thing you are not supposed to keep?',
        lengthNote: 'Three days and the bill. Short enough to feel like one sitting.',
        picture:
            'One person, held to one face, in moving shots. Day one, day two, day three, then the cost.',
        filesTitle: 'You',
        filesNote: 'Optional. A photo of the person this happens to.',
        showVoice: true,
        voiceHint: 'Close, second person, steady.',
        allowEngine: true,
        slots: [
          IntakeSlot(role: 'character', title: 'The person', hint: 'The same face on every day.'),
        ],
      );
    case 'time_travel_pov':
      return const ProductIntake(
        topicLabel: 'The era',
        topicHint: 'Where do you wake up, and in what year?',
        lengthNote: 'A walk you can watch without sitting down for it.',
        picture:
            'You stay one person. The camera walks, and each shot lands on the next frame. One modern object stays in the picture.',
        filesTitle: 'The object you brought',
        filesNote: 'Optional photo. It has to stay recognizable.',
        showVoice: true,
        voiceHint: 'You, close to the lens, same accent.',
        detailKind: 'object',
        detailLabel: 'The modern object',
        detailHint: 'A phone, a plastic bottle, a house key.',
        slots: [
          IntakeSlot(role: 'product', title: 'Object photo', hint: 'Three angles are better than one.'),
        ],
      );
    case 'body':
      return const ProductIntake(
        topicLabel: 'The process',
        topicHint: 'What happens inside you, from the first second?',
        lengthNote: 'One mechanism. Start, change, too far, then failure.',
        picture:
            'The camera stays inside the body and lands on the next beat. Sound is breath, pulse, and impact. No face.',
        filesTitle: '',
        filesNote: '',
        showVoice: true,
        voiceHint: 'A documentary voice, unhurried.',
      );
    case 'fpv':
      return const ProductIntake(
        topicLabel: 'The route',
        topicHint: 'Where does the camera fly, from the first move to the last?',
        lengthNote: 'One pass. Wind and motor stay louder than the music.',
        picture:
            'CineReal only. One height, one lens, one weather. No face. Each shot is flown from its own frame and lands on the next.',
        filesTitle: '',
        filesNote: '',
        showLanguage: false,
        showCaptions: false,
        weather: true,
      );
    case 'creature_eye':
      return const ProductIntake(
        topicLabel: 'The animal',
        topicHint: 'Which animal, and what is it doing?',
        lengthNote: 'A few behaviors, seen from the ground they stand on.',
        picture:
            'The camera stays at the animal’s eye. Each shot is one real behavior. No human face. A photo keeps the same animal.',
        filesTitle: 'The animal',
        filesNote: 'Optional. A photo, so every shot is that animal and not a new one.',
        showNarrator: true,
        showVoice: true,
        voiceHint: 'A quiet voice, or leave this blank and let the place speak.',
        allowEngine: true,
        slots: [
          IntakeSlot(role: 'character', title: 'Animal photo', hint: 'The same creature in every shot.'),
        ],
      );
    case 'cut_my_clips':
      return const ProductIntake(
        topicLabel: 'The feeling',
        topicHint: 'What should these clips feel like when they are cut together?',
        lengthNote: 'The cut should be watchable in one sitting.',
        picture: 'Nothing is generated. The film is only the footage you add.',
        filesTitle: 'The footage',
        filesNote: 'Add at least one video. A photo can set a face or a place.',
        showNarrator: true,
        showVoice: true,
        voiceHint: 'Only used if the narrator is on.',
        filesFirst: true,
        slots: [
          IntakeSlot(role: 'footage', title: 'Video', hint: 'Cut in as it is.', video: true),
          IntakeSlot(role: 'character', title: 'Face', hint: 'Optional. A person the cut returns to.'),
          IntakeSlot(role: 'background', title: 'Place', hint: 'Optional.'),
        ],
      );
    case 'countdown':
      return const ProductIntake(
        topicLabel: 'The list',
        topicHint: 'What are we counting, and why does the order matter?',
        lengthNote: 'The best item is last. Give it room.',
        picture:
            'Every rank is a short moving shot. The last rank is the one people remember, so it gets the finer pass.',
        filesTitle: 'A thing to recognize',
        filesNote: 'Optional. An object or a place that appears in more than one rank.',
        showVoice: true,
        voiceHint: 'One host. Same energy, then a lift on the last rank.',
        allowEngine: true,
        slots: [
          IntakeSlot(role: 'product', title: 'Object', hint: 'Kept recognizable when a rank shows it.'),
        ],
      );
    case 'song_video':
      return const ProductIntake(
        topicLabel: 'The song',
        topicHint: 'A sentence about what the song is. The lines go below.',
        lengthNote: 'The song is written first. Scenes are cut to its lines.',
        picture:
            'The vocal is made before the pictures. A face in the song is held to a sheet. Scenes are 4 to 10 seconds and follow the lines.',
        filesTitle: 'Who is in the song',
        filesNote: 'Optional. A face the verses come back to.',
        showCaptions: true,
        showVoice: false,
        allowEngine: true,
        detailKind: 'lyrics',
        detailLabel: 'Lines, or the feeling of the lines',
        detailHint: 'A verse is enough. We write the rest in this voice.',
        detailLines: 5,
        slots: [
          IntakeSlot(role: 'character', title: 'Singer or subject', hint: 'The same face when the song looks at them.'),
        ],
      );
    case 'narrated_story':
    default:
      return const ProductIntake(
        topicLabel: 'The story',
        topicHint: 'One sentence. Who it is about, and what changes.',
        lengthNote: 'A length you can watch in one sitting.',
        picture:
            'Every shot moves. A face or a line said on screen is acted and held to a sheet. A journey, a crowd, or a landscape is a camera move. We choose that per shot.',
        filesTitle: 'Who and where',
        filesNote: 'Optional. A face and a place you want kept. Skip this and we design them.',
        showVoice: true,
        voiceHint: 'Unhurried. The same age and accent in every chapter.',
        allowEngine: true,
        slots: [
          IntakeSlot(role: 'character', title: 'A face', hint: 'The person the story returns to.'),
          IntakeSlot(role: 'background', title: 'A place', hint: 'The set the story returns to.'),
          IntakeSlot(role: 'product', title: 'An object', hint: 'Only if it has to stay recognizable.'),
        ],
      );
  }
}
