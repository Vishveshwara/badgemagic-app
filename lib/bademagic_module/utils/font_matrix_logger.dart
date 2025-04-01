import 'dart:io';
import 'package:flutter/material.dart';
import 'package:badgemagic/providers/font_provider.dart';
import 'package:badgemagic/bademagic_module/utils/converters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:get_it/get_it.dart';

class FontMatrixLogger {
  static const List<String> _chars = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '!',
    '@',
    '#',
    '\$',
    '%',
    '^',
    '&',
    '*',
    '(',
    ')',
    '-',
    '_',
    '+',
    '=',
    '{',
    '}',
    '[',
    ']',
    '|',
    '\\',
    ':',
    ';',
    '"',
    '\'',
    '<',
    '>',
    ',',
    '.',
    '?',
    '/',
    '~',
    '`',
    ' ',
  ];

  static Future<List<String>> getSaveLocations() async {
    List<String> locations = [];

    // Add the specific fontcache.txt location for Windows
    locations.add(path.join('C:', 'Users', 'fontcache.txt'));

    // Add the platform-specific BadgeMagic directory location
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final badgeMagicDir = Directory(path.join(dir.path, 'BadgeMagic'));
        if (!await badgeMagicDir.exists()) {
          await badgeMagicDir.create(recursive: true);
        }
        locations.add(badgeMagicDir.path);
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final badgeMagicDir = Directory(path.join(dir.path, 'BadgeMagic'));
      if (!await badgeMagicDir.exists()) {
        await badgeMagicDir.create(recursive: true);
      }
      locations.add(badgeMagicDir.path);
    }

    return locations;
  }

  static void logAllMatrices(Converters converters) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final buffer = StringBuffer();
      buffer.writeln('Font Matrix Cache - Generated ${DateTime.now()}\n');
      buffer.writeln(
          'const Map<String, Map<String, List<List<bool>>>> fontCache = {');

      final fontProvider = GetIt.instance<FontProvider>();

      // Then process all other fonts

      await _processFont(fontProvider, converters, buffer);

      buffer.writeln('};');

      // Save to all file locations
      try {
        final locations = await getSaveLocations();
        final content = buffer.toString();

        for (final location in locations) {
          if (location.endsWith('.txt')) {
            // For the specific fontcache.txt file
            final file = File(location);
            await file.writeAsString(content);
            print('Font matrices saved to: ${file.path}');
          } else {
            // For the BadgeMagic directory
            final fileName =
                'font_matrices_${DateTime.now().millisecondsSinceEpoch}.txt';
            final filePath = path.join(location, fileName);
            final file = File(filePath);
            await file.writeAsString(content);
            print('Font matrices saved to: ${file.path}');
          }
        }
      } catch (e) {
        print('Error saving font matrices: $e');
      }
    });
  }

  static Future<void> _processFont(FontProvider fontProvider,
      Converters converters, StringBuffer buffer) async {
    await Future.delayed(const Duration(milliseconds: 2));

    final style = fontProvider.selectedTextStyle;
    final fontKey = _createFontKey(
      fontProvider.selectedTextStyle.fontFamily ?? 'Default',
      style.fontSize ?? 12,
      style.fontWeight ?? FontWeight.normal,
      style.fontStyle == FontStyle.italic,
    );

    buffer.writeln("  '$fontKey': {");
    print(
        'Processing font: ${fontProvider.selectedTextStyle.fontFamily ?? "Default"}');

    for (final char in _chars) {
      try {
        final result = await converters.renderTextToMatrix(
          char,
          fontProvider.selectedTextStyle,
          rows: 11,
          hasDescender: _hasDescender(char),
        );

        buffer.writeln("    '$char': [");
        for (final row in result['matrix']!) {
          buffer.writeln('      ${row.map((b) => b.toString()).toList()},');
        }
        buffer.writeln('    ],');
        print(
            'Processed char: $char for font: ${fontProvider.selectedTextStyle.fontFamily ?? "Default"}');
      } catch (e) {
        print(
            'Error rendering $char for font ${fontProvider.selectedTextStyle.fontFamily ?? "Default"}: $e');
      }
    }

    buffer.writeln('  },');
  }

  static String _createFontKey(
      String fontFamily, double fontSize, FontWeight weight, bool italic) {
    return '$fontFamily-${fontSize.round()}-${weight.index}-$italic';
  }

  static bool _hasDescender(String char) {
    return char == 'g' ||
        char == 'j' ||
        char == 'p' ||
        char == 'q' ||
        char == 'y';
  }
}
