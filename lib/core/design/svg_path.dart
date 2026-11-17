import 'dart:ui';

/// Minimal SVG path parser for the commands the prototype actually uses:
/// `M`, `L`, `H`, `V`, `Z` and their relative forms.
///
/// Keeping the prototype's path strings verbatim (instead of redrawing them as
/// `CustomPainter` code) is what lets a test diff the artwork against the HTML.
/// Anything outside the supported subset throws rather than rendering wrongly.
Path parseSvgPath(String data) {
  final Path path = Path();
  final List<String> tokens = RegExp(r'[A-Za-z]|-?\d*\.?\d+')
      .allMatches(data)
      .map((RegExpMatch m) => m.group(0)!)
      .toList();

  double x = 0;
  double y = 0;
  double startX = 0;
  double startY = 0;
  String command = '';
  int i = 0;

  double number() {
    if (i >= tokens.length) {
      throw FormatException('SVG path ended early', data);
    }
    return double.parse(tokens[i++]);
  }

  while (i < tokens.length) {
    final String token = tokens[i];

    if (RegExp(r'^[A-Za-z]$').hasMatch(token)) {
      command = token;
      i++;
      if (command == 'Z' || command == 'z') {
        path.close();
        x = startX;
        y = startY;
      }
      continue;
    }

    switch (command) {
      case 'M':
        x = number();
        y = number();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Subsequent coordinate pairs are implicit lineto commands.
        command = 'L';
      case 'm':
        x += number();
        y += number();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        command = 'l';
      case 'L':
        x = number();
        y = number();
        path.lineTo(x, y);
      case 'l':
        x += number();
        y += number();
        path.lineTo(x, y);
      case 'H':
        x = number();
        path.lineTo(x, y);
      case 'h':
        x += number();
        path.lineTo(x, y);
      case 'V':
        y = number();
        path.lineTo(x, y);
      case 'v':
        y += number();
        path.lineTo(x, y);
      default:
        throw FormatException('Unsupported SVG command "$command"', data);
    }
  }

  return path;
}
