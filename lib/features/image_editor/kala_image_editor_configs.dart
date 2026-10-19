import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pro_image_editor/pro_image_editor.dart';

/// Kala-branded ProImageEditor 14.x configs: crop ratios, fonts, stickers,
/// paint, Looks, helper lines, and plain tool names.
ProImageEditorConfigs kalaImageEditorConfigs(
  BuildContext context, {
  File? stickerSeed,
  ImportStateHistory? initStateHistory,
  List<HelperGuideLine> frameGuides = const [],
  mui.TextStyle? textStyle,
}) {
  return ProImageEditorConfigs(
    theme: mui.ThemeData(
      brightness: mui.Brightness.dark,
      colorScheme: const mui.ColorScheme.dark(
        primary: mui.Color(0xFF7B5EFF),
        secondary: mui.Color(0xFF00D4FF),
        surface: mui.Color(0xFF1A1A2E),
      ),
    ),
    designMode: ImageEditorDesignMode.material,
    helperLines: HelperLineConfigs(
      showVerticalLine: true,
      showHorizontalLine: true,
      showRotateLine: true,
      showLayerAlignLine: true,
      enableEdgeSnapping: true,
      enableSmartAlignment: true,
      customGuides: frameGuides,
    ),
    layerInteraction: const LayerInteractionConfigs(
      selectable: LayerInteractionSelectable.enabled,
      initialSelected: true,
      enableKeyboardMultiSelection: true,
      enableLongPressMultiSelection: true,
    ),
    stateHistory: StateHistoryConfigs(
      stateHistoryLimit: 80,
      initStateHistory: initStateHistory,
    ),
    i18n: const I18n(
      cancel: 'Cancel',
      undo: 'Undo',
      redo: 'Redo',
      done: 'Done',
      paintEditor: I18nPaintEditor(
        bottomNavigationBarText: 'Draw',
        freestyle: 'Freehand',
        arrow: 'Arrow',
        rectangle: 'Rectangle',
        circle: 'Circle',
        blur: 'Blur',
        pixelate: 'Pixelate',
      ),
      textEditor: I18nTextEditor(
        bottomNavigationBarText: 'Text',
        inputHintText: 'Type here',
        backgroundMode: 'Background',
      ),
      cropRotateEditor: I18nCropRotateEditor(
        bottomNavigationBarText: 'Crop',
        rotate: 'Rotate',
        flip: 'Flip',
        ratio: 'Shape',
      ),
      tuneEditor: I18nTuneEditor(bottomNavigationBarText: 'Looks'),
      filterEditor: I18nFilterEditor(bottomNavigationBarText: 'Looks'),
      blurEditor: I18nBlurEditor(bottomNavigationBarText: 'Blur'),
      stickerEditor: I18nStickerEditor(bottomNavigationBarText: 'Sticker'),
      emojiEditor: I18nEmojiEditor(bottomNavigationBarText: 'Emoji'),
    ),
    mainEditor: MainEditorConfigs(
      captureLayersOnDone: true,
      tools: const [
        SubEditorMode.paint,
        SubEditorMode.text,
        SubEditorMode.cropRotate,
        SubEditorMode.tune,
        SubEditorMode.filter,
        SubEditorMode.blur,
        SubEditorMode.emoji,
        SubEditorMode.sticker,
      ],
      // After an edit the package shows "Close Image Editor?" and then calls
      // onCloseEditor, which asks again. Confirm once in that callback.
      widgets: MainEditorWidgets(
        closeWarningDialog: (_) async => true,
      ),
    ),
    cropRotateEditor: const CropRotateEditorConfigs(
      initAspectRatio: -1,
      aspectRatios: [
        AspectRatioItem(text: 'Free', value: -1),
        AspectRatioItem(text: '1:1', value: 1),
        AspectRatioItem(text: '4:5', value: 4 / 5),
        AspectRatioItem(text: '9:16', value: 9 / 16),
        AspectRatioItem(text: '16:9', value: 16 / 9),
        AspectRatioItem(text: '4:3', value: 4 / 3),
      ],
    ),
    textEditor: TextEditorConfigs(
      showSelectFontStyleBottomBar: true,
      showBackgroundModeButton: true,
      initialBackgroundColorMode: LayerBackgroundMode.onlyColor,
      defaultTextStyle: textStyle ??
          const mui.TextStyle(fontFamily: 'Inter', fontSize: 24),
      customTextStyles: const [
        mui.TextStyle(fontFamily: 'Inter', fontSize: 24),
        mui.TextStyle(fontFamily: 'Roboto', fontSize: 24),
        mui.TextStyle(fontFamily: 'Poppins', fontSize: 24),
        mui.TextStyle(fontFamily: 'Montserrat', fontSize: 24),
        mui.TextStyle(fontFamily: 'Oswald', fontSize: 24),
      ],
    ),
    paintEditor: const PaintEditorConfigs(
      tools: [
        PaintMode.freeStyle,
        PaintMode.arrow,
        PaintMode.rect,
        PaintMode.circle,
        PaintMode.blur,
        PaintMode.pixelate,
        PaintMode.eraser,
      ],
    ),
    filterEditor: FilterEditorConfigs(
      filterList: [
        FilterModel(name: 'Clean', filters: PresetFilters.none.filters),
        FilterModel(name: 'Film', filters: PresetFilters.amaro.filters),
        FilterModel(name: 'Night', filters: PresetFilters.moon.filters),
        FilterModel(name: 'Poster', filters: PresetFilters.juno.filters),
        FilterModel(name: 'Soft', filters: PresetFilters.gingham.filters),
        FilterModel(name: 'Punch', filters: PresetFilters.clarendon.filters),
      ],
    ),
    blurEditor: const BlurEditorConfigs(),
    stickerEditor: StickerEditorConfigs(
      initWidth: 160,
      builder: (setLayer, scrollController) {
        return _KalaStickerSheet(
          setLayer: setLayer,
          scrollController: scrollController,
          seed: stickerSeed,
        );
      },
    ),
  );
}

List<HelperGuideLine> kalaFrameGuides(String id) {
  switch (id) {
    case '9:16':
      return const [
        HelperGuideLine(
            axis: Axis.vertical, position: 0.05, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.vertical, position: 0.95, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.horizontal, position: 0.08, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.horizontal, position: 0.92, positionMode: HelperGuidePositionMode.normalized),
      ];
    case '4:5':
      return const [
        HelperGuideLine(
            axis: Axis.vertical, position: 0.06, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.vertical, position: 0.94, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.horizontal, position: 0.06, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.horizontal, position: 0.94, positionMode: HelperGuidePositionMode.normalized),
      ];
    case '1:1':
      return const [
        HelperGuideLine(
            axis: Axis.vertical, position: 0.08, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.vertical, position: 0.92, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.horizontal, position: 0.08, positionMode: HelperGuidePositionMode.normalized),
        HelperGuideLine(
            axis: Axis.horizontal, position: 0.92, positionMode: HelperGuidePositionMode.normalized),
      ];
    default:
      return const [];
  }
}

class _KalaStickerSheet extends StatefulWidget {
  final void Function(WidgetLayer layer) setLayer;
  final ScrollController scrollController;
  final File? seed;

  const _KalaStickerSheet({
    required this.setLayer,
    required this.scrollController,
    this.seed,
  });

  @override
  State<_KalaStickerSheet> createState() => _KalaStickerSheetState();
}

class _KalaStickerSheetState extends State<_KalaStickerSheet> {
  final List<File> _picked = [];

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null && seed.existsSync()) {
      _picked.add(seed);
    }
  }

  Future<void> _pickGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      File? file;
      if (result != null &&
          result.files.isNotEmpty &&
          result.files.first.path != null) {
        file = File(result.files.first.path!);
      } else {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (x != null) file = File(x.path);
      }
      if (file == null || !file.existsSync()) return;
      setState(() => _picked.add(file!));
      _apply(file);
    } catch (_) {}
  }

  void _apply(File file) {
    widget.setLayer(
      WidgetLayer(
        widget: Image.file(file, fit: BoxFit.contain),
        exportConfigs: WidgetLayerExportConfigs(id: file.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Sticker',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Place a photo or a cutout on this picture.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _tile(
              cs,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, color: KalaColors.cyan),
                  SizedBox(height: 6),
                  Text('Gallery', style: TextStyle(fontSize: 12)),
                ],
              ),
              onTap: _pickGallery,
            ),
            for (final f in _picked)
              _tile(
                cs,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(f, fit: BoxFit.cover),
                ),
                onTap: () => _apply(f),
              ),
          ],
        ),
      ],
    );
  }

  Widget _tile(ColorScheme cs, {required Widget child, required VoidCallback onTap}) {
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 96, height: 96, child: child),
      ),
    );
  }
}
