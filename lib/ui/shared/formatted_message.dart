import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../telegram/client/td_client.dart';

/// TDLib entity offsets/lengths use UTF-16 code units, just like Dart strings.
class FormattedMessage extends StatefulWidget {
  const FormattedMessage({super.key, required this.text});
  final Json text;
  @override
  State<FormattedMessage> createState() => _FormattedMessageState();
}

class _FormattedMessageState extends State<FormattedMessage> {
  final recognizers = <TapGestureRecognizer>[];
  @override
  void dispose() {
    for (final r in recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in recognizers) {
      r.dispose();
    }
    recognizers.clear();
    final text = widget.text['text'] as String? ?? '';
    final entities = List<Json>.from(widget.text['entities'] ?? [])
        .where(
          (e) =>
              e['offset'] is int &&
              e['length'] is int &&
              e['offset'] >= 0 &&
              e['length'] > 0 &&
              e['offset'] + e['length'] <= text.length,
        )
        .toList();
    final boundaries = <int>{0, text.length};
    for (final e in entities) {
      boundaries.add(e['offset']);
      boundaries.add(e['offset'] + e['length']);
    }
    final positions = boundaries.toList()..sort();
    final spans = <TextSpan>[];
    for (var i = 0; i < positions.length - 1; i++) {
      final start = positions[i], end = positions[i + 1];
      var style = const TextStyle();
      String? url;
      for (final entity in entities.where(
        (e) => e['offset'] <= start && e['offset'] + e['length'] >= end,
      )) {
        final type = entity['type'] as Json;
        switch (type['@type']) {
          case 'textEntityTypeBold':
            style = style.copyWith(fontWeight: FontWeight.bold);
          case 'textEntityTypeItalic':
            style = style.copyWith(fontStyle: FontStyle.italic);
          case 'textEntityTypeUnderline':
            style = style.copyWith(decoration: TextDecoration.underline);
          case 'textEntityTypeStrikethrough':
            style = style.copyWith(decoration: TextDecoration.lineThrough);
          case 'textEntityTypeCode':
          case 'textEntityTypePre':
          case 'textEntityTypePreCode':
            style = style.copyWith(fontFamily: 'monospace');
          case 'textEntityTypeTextUrl':
            url = type['url'] as String?;
          case 'textEntityTypeUrl':
            url = text.substring(
              entity['offset'],
              entity['offset'] + entity['length'],
            );
        }
      }
      TapGestureRecognizer? recognizer;
      if (url != null) {
        final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
        if (uri != null && ['https', 'http', 'tg'].contains(uri.scheme)) {
          style = style.copyWith(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          );
          recognizer = TapGestureRecognizer()
            ..onTap = () {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            };
          recognizers.add(recognizer);
        }
      }
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: style,
          recognizer: recognizer,
        ),
      );
    }
    return SelectableText.rich(TextSpan(children: spans));
  }
}
