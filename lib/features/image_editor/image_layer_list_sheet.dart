import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

Future<void> showImageLayerListSheet(
  BuildContext context,
  GlobalKey<ProImageEditorState> editorKey,
) async {
  final state = editorKey.currentState;
  if (state == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return _ImageLayerList(editor: state);
    },
  );
}

class _ImageLayerList extends StatefulWidget {
  final ProImageEditorState editor;
  const _ImageLayerList({required this.editor});

  @override
  State<_ImageLayerList> createState() => _ImageLayerListState();
}

class _ImageLayerListState extends State<_ImageLayerList> {
  String _label(Layer layer) {
    if (layer is TextLayer) {
      final t = layer.text.trim();
      return t.isEmpty ? 'Text' : (t.length > 28 ? '${t.substring(0, 28)}…' : t);
    }
    if (layer is EmojiLayer) return layer.emoji;
    if (layer is WidgetLayer) return 'Sticker';
    if (layer is PaintLayer) return 'Draw';
    return 'Layer';
  }

  @override
  Widget build(BuildContext context) {
    final layers = widget.editor.activeLayers.reversed.toList();
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Layers',
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (layers.isEmpty)
              Text('No layers yet.',
                  style: TextStyle(color: cs.onSurfaceVariant))
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: layers.length,
                  onReorder: (oldIndex, newIndex) {
                    final visual = layers;
                    if (newIndex > oldIndex) newIndex -= 1;
                    final fromLayer = visual[oldIndex];
                    final toLayer = visual[newIndex];
                    final realOld = widget.editor.activeLayers.indexOf(fromLayer);
                    final realNew = widget.editor.activeLayers.indexOf(toLayer);
                    widget.editor.moveLayerListPosition(
                      oldIndex: realOld,
                      newIndex: realNew,
                    );
                    setState(() {});
                  },
                  itemBuilder: (context, i) {
                    final layer = layers[i];
                    final locked = !layer.interaction.enableMove;
                    final hidden = layer.opacity < 0.05;
                    return ListTile(
                      key: ValueKey(layer.id),
                      title: Text(_label(layer)),
                      leading: Icon(
                        hidden ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: hidden ? 'Show' : 'Hide',
                            icon: Icon(hidden
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () {
                              final idx =
                                  widget.editor.activeLayers.indexOf(layer);
                              if (idx < 0) return;
                              widget.editor.replaceLayer(
                                index: idx,
                                layer: layer.copyWith(
                                  opacity: hidden ? 1 : 0,
                                ),
                              );
                              setState(() {});
                            },
                          ),
                          IconButton(
                            tooltip: locked ? 'Unlock' : 'Lock',
                            icon: Icon(locked ? Icons.lock : Icons.lock_open),
                            onPressed: () {
                              final idx =
                                  widget.editor.activeLayers.indexOf(layer);
                              if (idx < 0) return;
                              widget.editor.replaceLayer(
                                index: idx,
                                layer: layer.copyWith(
                                  interaction: layer.interaction.copyWith(
                                    enableMove: locked,
                                    enableScale: locked,
                                    enableRotate: locked,
                                    enableSelection: true,
                                    enableEdit: locked,
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              widget.editor.removeLayer(layer);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
