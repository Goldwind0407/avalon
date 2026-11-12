import 'package:flutter/material.dart';
import 'notebook_model.dart';
import 'notebook_painter.dart';

/// Owns the text controller until the dialog's closing transition finishes.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.title, required this.initialText});
  final String title, initialText;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _controller = TextEditingController(text: widget.initialText);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
      backgroundColor: const Color(0xFFF1E1B8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            color: notebookInk,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                        key: const ValueKey('notebookEditor'),
                        controller: _controller,
                        autofocus: true,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: GameNotebook.maxLength,
                        style:
                            const TextStyle(color: notebookInk, fontSize: 16),
                        cursorColor: notebookInk,
                        decoration: const InputDecoration(
                            hintText: '寫下觀察、推理或待確認的線索…',
                            hintStyle: TextStyle(color: Color(0xFF8C7758)),
                            counterStyle: TextStyle(color: notebookGold),
                            fillColor: Color(0xFFE6D3A5))),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                              foregroundColor: notebookInk),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      FilledButton(
                          key: const ValueKey('saveNotebookNote'),
                          onPressed: () =>
                              Navigator.pop(context, _controller.text),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF735333),
                              foregroundColor: const Color(0xFFFFF2CC)),
                          child: const Text('儲存')),
                    ]),
                  ]))));
}
