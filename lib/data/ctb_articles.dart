import 'dart:convert';

const String ctbOfficialUrl =
    'https://www.planalto.gov.br/ccivil_03/leis/l9503compilado.htm';

class CtbArticle {
  final String number;
  final String title;
  final String summary;
  final String fullText;

  const CtbArticle({
    required this.number,
    required this.title,
    required this.summary,
    required this.fullText,
  });

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'title': title,
      'summary': summary,
      'fullText': fullText,
    };
  }

  factory CtbArticle.fromMap(Map<String, dynamic> map) {
    return CtbArticle(
      number: map['number']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      summary: map['summary']?.toString() ?? '',
      fullText: map['fullText']?.toString() ?? '',
    );
  }
}

const List<CtbArticle> fallbackCtbArticles = [
  CtbArticle(
    number: 'Art. 1',
    title: 'Disposicoes preliminares',
    summary:
        'O transito nas vias terrestres abertas a circulacao rege-se pelo Codigo de Transito Brasileiro.',
    fullText:
        'Art. 1 O transito de qualquer natureza nas vias terrestres do territorio nacional, abertas a circulacao, rege-se por este Codigo.',
  ),
  CtbArticle(
    number: 'Art. 2',
    title: 'Conceito de vias terrestres',
    summary:
        'As regras do CTB valem para vias urbanas e rurais, incluindo ruas, avenidas, estradas e rodovias.',
    fullText:
        'Art. 2 Sao vias terrestres urbanas e rurais as ruas, avenidas, logradouros, caminhos, passagens, estradas e rodovias.',
  ),
  CtbArticle(
    number: 'Art. 28',
    title: 'Conducao com atencao',
    summary:
        'O condutor deve ter dominio do veiculo e dirigir com atencao e cuidados indispensaveis a seguranca.',
    fullText:
        'Art. 28 O condutor devera, a todo momento, ter dominio de seu veiculo, dirigindo-o com atencao e cuidados indispensaveis a seguranca do transito.',
  ),
  CtbArticle(
    number: 'Art. 44',
    title: 'Cruzamentos',
    summary:
        'Ao se aproximar de cruzamento, o condutor deve demonstrar prudencia especial e reduzir a velocidade.',
    fullText:
        'Art. 44 Ao aproximar-se de qualquer tipo de cruzamento, o condutor do veiculo deve demonstrar prudencia especial, transitando em velocidade moderada.',
  ),
  CtbArticle(
    number: 'Art. 61',
    title: 'Velocidade maxima',
    summary:
        'A velocidade deve respeitar limites legais e sinalizacao da via, observadas as regras do CTB.',
    fullText:
        'Art. 61 A velocidade maxima permitida para a via sera indicada por meio de sinalizacao, obedecidas suas caracteristicas tecnicas e as condicoes de transito.',
  ),
  CtbArticle(
    number: 'Art. 165',
    title: 'Alcool e direcao',
    summary:
        'Dirigir sob influencia de alcool ou outra substancia psicoativa e infracao gravissima.',
    fullText:
        'Art. 165 Dirigir sob a influencia de alcool ou de qualquer outra substancia psicoativa que determine dependencia.',
  ),
];

String encodeCtbArticles(List<CtbArticle> articles) {
  final serialized = articles.map((item) => item.toMap()).toList();
  return jsonEncode(serialized);
}

List<CtbArticle> decodeCtbArticles(String raw) {
  if (raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => CtbArticle.fromMap(Map<String, dynamic>.from(item)))
        .where((item) =>
            item.number.isNotEmpty &&
            item.summary.isNotEmpty &&
            item.fullText.isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
}

List<CtbArticle> parseCtbArticlesFromHtml(String html) {
  final paragraphPattern = RegExp(
    r'<p[^>]*>(.*?)</p>',
    caseSensitive: false,
    dotAll: true,
  );
  final rawParagraphs = paragraphPattern
      .allMatches(html)
      .map((match) => _htmlFragmentToPlainText(match.group(1) ?? ''))
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();

  if (rawParagraphs.isEmpty) return [];

  final articleStartPattern = RegExp(
    '^Art\\.\\s*(\\d+)\\s*(?:\\u00BA|\\u00B0|o)?\\s*(?:-\\s*([A-Za-z]))?\\s*(?:[^\\w\\s])?\\s*(.*)\$',
    caseSensitive: false,
  );

  final startEntries = <MapEntry<int, RegExpMatch>>[];
  for (var i = 0; i < rawParagraphs.length; i++) {
    final match = articleStartPattern.firstMatch(rawParagraphs[i]);
    if (match != null) {
      startEntries.add(MapEntry(i, match));
    }
  }

  if (startEntries.isEmpty) return [];

  final seenNumbers = <String>{};
  final parsed = <CtbArticle>[];

  for (var i = 0; i < startEntries.length; i++) {
    final current = startEntries[i];
    final nextIndex =
        i + 1 < startEntries.length ? startEntries[i + 1].key : rawParagraphs.length;
    final baseNumber = current.value.group(1)?.trim() ?? '';
    final suffix = (current.value.group(2) ?? '').trim().toUpperCase();
    final rawNumber = suffix.isEmpty ? baseNumber : '$baseNumber-$suffix';
    final normalizedNumber = _normalizeArticleNumber(rawNumber);

    if (normalizedNumber.isEmpty || seenNumbers.contains(normalizedNumber)) {
      continue;
    }

    final firstLineBody = (current.value.group(3) ?? '').trim();
    final title = _firstSentence(firstLineBody, maxChars: 84);
    final summary = _firstSentence(firstLineBody, maxChars: 220);
    if (summary.isEmpty) continue;

    final blockLines = rawParagraphs
        .sublist(current.key, nextIndex)
        .map(_cleanArticleBlock)
        .where((line) => line.isNotEmpty)
        .toList();
    if (blockLines.isEmpty) continue;

    final fullText = blockLines.join('\n').trim();
    parsed.add(
      CtbArticle(
        number: 'Art. $normalizedNumber',
        title: title.isEmpty ? 'Texto legal' : title,
        summary: summary,
        fullText: fullText,
      ),
    );
    seenNumbers.add(normalizedNumber);
  }

  return parsed;
}

String _normalizeArticleNumber(String raw) {
  return raw
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('--', '-');
}

String _firstSentence(String raw, {required int maxChars}) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';
  final endPunctuation = RegExp(r'[.;:!?]');
  final hit = endPunctuation.firstMatch(normalized);
  final sentence = hit == null ? normalized : normalized.substring(0, hit.end);
  if (sentence.length <= maxChars) return sentence;
  return '${sentence.substring(0, maxChars).trimRight()}...';
}

String _cleanArticleBlock(String raw) {
  var text = raw.replaceAll(RegExp(r'\r'), '');
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r' *\n *'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String _htmlFragmentToPlainText(String htmlFragment) {
  var text = htmlFragment;
  text = text.replaceAll(
    RegExp(
      r'<br\s*/?>',
      caseSensitive: false,
    ),
    '\n',
  );
  text = text.replaceAll(
    RegExp(
      r'<[^>]+>',
      caseSensitive: false,
      dotAll: true,
    ),
    ' ',
  );
  text = _decodeHtmlEntities(text);
  text = text.replaceAll(RegExp(r'[ \t\f]+'), ' ');
  text = text.replaceAll(RegExp(r' *\n *'), ' ');
  text = text.replaceAll(RegExp(r'\s{2,}'), ' ');
  return text.trim();
}

String _decodeHtmlEntities(String input) {
  var text = input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&ordm;', 'o')
      .replaceAll('&ordf;', 'a');

  text = text.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) {
      final code = int.tryParse(match.group(1) ?? '');
      if (code == null) return '';
      return String.fromCharCode(code);
    },
  );

  text = text.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]+);'),
    (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      if (code == null) return '';
      return String.fromCharCode(code);
    },
  );

  return text;
}
