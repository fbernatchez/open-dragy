import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/logger_tags.dart';

/// Invisible sentinel so soft-keyboard backspace fires when the draft looks empty.
const _kDraftSentinel = '\u200B';

/// Tags field: completed tags become chips when a comma is typed.
class LoggerTagsInput extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onTagsChanged;
  final bool enabled;
  final String? hintText;

  const LoggerTagsInput({
    super.key,
    required this.tags,
    required this.onTagsChanged,
    this.enabled = true,
    this.hintText,
  });

  @override
  State<LoggerTagsInput> createState() => _LoggerTagsInputState();
}

class _LoggerTagsInputState extends State<LoggerTagsInput> {
  final TextEditingController _draft = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  String get _plainDraft => _draft.text.replaceAll(_kDraftSentinel, '');

  @override
  void initState() {
    super.initState();
    _ensureSentinel();
  }

  @override
  void didUpdateWidget(covariant LoggerTagsInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tags.isEmpty != widget.tags.isEmpty) {
      _ensureSentinel();
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ensureSentinel() {
    if (widget.tags.isEmpty) {
      if (_draft.text == _kDraftSentinel) {
        _draft.clear();
      }
      return;
    }
    if (!_draft.text.startsWith(_kDraftSentinel)) {
      final plain = _plainDraft;
      _draft.value = TextEditingValue(
        text: '$_kDraftSentinel$plain',
        selection: TextSelection.collapsed(
          offset: _kDraftSentinel.length + plain.length,
        ),
      );
    }
  }

  void _commitDraft() {
    final next = _plainDraft.trim();
    _draft.clear();
    _ensureSentinel();
    if (next.isEmpty) return;
    final tags = List<String>.from(widget.tags);
    if (tags.any((t) => t.toLowerCase() == next.toLowerCase())) return;
    tags.add(next);
    widget.onTagsChanged(tags);
  }

  void _onDraftChanged(String value) {
    // Soft keyboard: deleting the sentinel while "empty" removes last chip.
    if (widget.tags.isNotEmpty &&
        !value.contains(_kDraftSentinel) &&
        value.trim().isEmpty) {
      _removeLastTag();
      _draft.value = const TextEditingValue(
        text: _kDraftSentinel,
        selection: TextSelection.collapsed(offset: _kDraftSentinel.length),
      );
      return;
    }

    final plain = value.replaceAll(_kDraftSentinel, '');
    if (!plain.contains(',')) {
      _ensureSentinel();
      return;
    }

    final parts = plain.split(',');
    final tags = List<String>.from(widget.tags);
    for (var i = 0; i < parts.length - 1; i++) {
      final tag = parts[i].trim();
      if (tag.isEmpty) continue;
      if (!tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        tags.add(tag);
      }
    }
    final rest = parts.last;
    final nextText = widget.tags.isNotEmpty || tags.isNotEmpty
        ? '$_kDraftSentinel$rest'
        : rest;
    _draft.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    widget.onTagsChanged(tags);
  }

  void _removeTag(String tag) {
    final tags = widget.tags
        .where((t) => t.toLowerCase() != tag.toLowerCase())
        .toList();
    widget.onTagsChanged(tags);
  }

  void _removeLastTag() {
    if (widget.tags.isEmpty) return;
    final tags = List<String>.from(widget.tags)..removeLast();
    widget.onTagsChanged(tags);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    // Hardware / some soft keyboards: empty draft → delete last chip.
    if (_plainDraft.isEmpty && widget.tags.isNotEmpty) {
      _removeLastTag();
      _ensureSentinel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Tags',
        labelStyle: GoogleFonts.roboto(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in widget.tags)
            InputChip(
              label: Text(
                tag,
                style: GoogleFonts.roboto(
                  color: const Color(0xFFFFBF00),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: const Color(0xFFFFBF00).withOpacity(0.12),
              side: const BorderSide(color: Color(0xFFFFBF00)),
              deleteIconColor: const Color(0xFFFFBF00),
              onDeleted: widget.enabled ? () => _removeTag(tag) : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 220),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _draft,
              builder: (context, value, child) {
                final plainEmpty =
                    value.text.replaceAll(_kDraftSentinel, '').isEmpty;
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (widget.tags.isNotEmpty && plainEmpty)
                      IgnorePointer(
                        child: Text(
                          'add tag…',
                          style: GoogleFonts.roboto(
                            color: Colors.white24,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    child!,
                  ],
                );
              },
              child: TextField(
                enabled: widget.enabled,
                controller: _draft,
                focusNode: _focus,
                onChanged: _onDraftChanged,
                onSubmitted: (_) => _commitDraft(),
                onEditingComplete: _commitDraft,
                style: GoogleFonts.roboto(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.tags.isEmpty
                      ? (widget.hintText ?? '98, Velocity Stack')
                      : null,
                  hintStyle: GoogleFonts.roboto(
                    color: Colors.white24,
                    fontSize: 13,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience: sync chip list back to comma-separated storage string.
String tagsListToStorage(List<String> tags) => formatLoggerTags(tags);
