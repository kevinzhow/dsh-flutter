import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain output is one plain span per line', () {
    final lines = parseAnsiLines('a\nb c\n');
    expect(lines.length, 3);
    expect(lines[0].single.text, 'a');
    expect(lines[0].single.plain, isTrue);
    expect(lines[1].single.text, 'b c');
    expect(lines[2], isEmpty);
  });

  test('basic colours map to theme tokens, bold and reset apply', () {
    final line = parseAnsiLines('\u001b[1;31mfail\u001b[0m ok')[0];
    expect(line.map((s) => s.text), ['fail', ' ok']);
    expect(line[0].bold, isTrue);
    expect(ansiTokenFor(line[0].fg!.rgb!), '--dsw-alias-state-error-primary');
    expect(line[1].plain, isTrue);
  });

  test('256-colour and truecolor are literal', () {
    final line = parseAnsiLines('\u001b[38;5;196mred\u001b[38;2;1;2;3mrgb')[0];
    expect(line[0].fg!.rgb, 0xff0000);
    expect(line[1].fg!.rgb, 0x010203);
  });

  test('a colour carries across lines until reset', () {
    final lines = parseAnsiLines('\u001b[32mone\ntwo\u001b[0m\nthree');
    expect(lines[0][0].fg, isNotNull);
    expect(lines[1][0].fg, isNotNull);
    expect(lines[2][0].plain, isTrue);
  });

  test('carriage return redraws the line like a terminal', () {
    expect(parseAnsiLines('10%\r100%')[0].map((s) => s.text).join(), '100%');
    expect(
      parseAnsiLines('abcdef\r\u001b[Kxy')[0].map((s) => s.text).join(),
      'xy',
    );
  });

  test('operating-system commands and control bytes are dropped', () {
    final text = parseAnsiLines(
      '\u001b]0;title\u0007hello\u0001 world',
    )[0].map((s) => s.text).join();
    expect(text, 'hello world');
  });
}
