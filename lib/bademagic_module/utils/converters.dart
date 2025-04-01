import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:badgemagic/bademagic_module/utils/byte_array_utils.dart';
import 'package:badgemagic/bademagic_module/utils/data_to_bytearray_converter.dart';
import 'package:badgemagic/bademagic_module/utils/file_helper.dart';
import 'package:badgemagic/bademagic_module/utils/font_cache.dart';
import 'package:badgemagic/bademagic_module/utils/image_utils.dart';
import 'package:badgemagic/providers/font_provider.dart';
import 'package:badgemagic/providers/imageprovider.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

String getFontKey(
    String fontFamily, double fontSize, FontWeight weight, bool italic) {
  return '$fontFamily-${fontSize.round()}-${weight.index}-$italic';
}

class Converters {
  InlineImageProvider controllerData =
      GetIt.instance.get<InlineImageProvider>();
  DataToByteArrayConverter converter = DataToByteArrayConverter();
  ImageUtils imageUtils = ImageUtils();
  FileHelper fileHelper = FileHelper();

  List<String> _matrixToHex(List<List<bool>> matrix) {
    return List.generate(matrix.length, (i) {
      final binary = matrix[i].map((b) => b ? '1' : '0').join();
      return int.parse(binary, radix: 2).toRadixString(16).padLeft(2, '0');
    });
  }

  Future<Map<String, dynamic>> renderTextToMatrix(
    String message,
    TextStyle textStyle, {
    int rows = 11,
    required bool hasDescender, // for characters like j, g, p, q, y
  }) async {
    // Generate font key for cache lookup
    final fontKey = getFontKey(
      textStyle.fontFamily ?? 'default',
      textStyle.fontSize ?? 14.0,
      textStyle.fontWeight ?? FontWeight.normal,
      textStyle.fontStyle == FontStyle.italic,
    );
    //print('fontkey: $fontKey');

    // Check cache first
    if (fontCache.containsKey(fontKey)) {
      final cachedFont = fontCache[fontKey]!;
      if (cachedFont.containsKey(message)) {
        return {
          'matrix': cachedFont[message]!,
        };
      }
    }
    int cols = 1;
    int scale = 1;
    // Calculate canvas size
    TextPainter widthCheckPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: textStyle.copyWith(
            color: Colors.black, fontSize: (textStyle.fontSize ?? 14) * scale),
      ),
      textDirection: TextDirection.ltr,
    );
    widthCheckPainter.layout();
    final rawWidth = widthCheckPainter.width;
    // Check if character needs more width

    // Dynamic column calculation
    final actualCols = (rawWidth / scale).ceil().clamp(1, 16);

    //print("Actual cols: $actualCols");
    cols = actualCols;

    // Calculate final dimensions
    final int width = cols * scale;
    final int height = rows * scale;

    // Create single PictureRecorder and Canvas
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
        recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    // Fill background
    final Paint bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bgPaint);

    // Create text painter with final dimensions
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: textStyle.copyWith(
            color: Colors.black, fontSize: (textStyle.fontSize ?? 14) * scale),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: width.toDouble());
    Offset offset;
    if (hasDescender) {
      // For descender characters, align so descender can use bottom row
      final baselinePosition = height - 2; // Leave 1 unit at bottom
      offset = Offset(
        0,
        baselinePosition -
            textPainter
                .computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
    } else {
      // For normal characters, ensure bottom padding of 1 unit
      offset = Offset(
        0,
        (height - 1) - // Leave 1 unit at bottom
            textPainter
                .computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
    }

    //print("height: $height, offset: $offset");

    textPainter.paint(canvas, offset);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) {
      throw Exception("Failed to convert image to byte data.");
    }
    final Uint8List data = byteData.buffer.asUint8List();

    List<List<bool>> matrix =
        List.generate(rows, (_) => List.generate(cols, (_) => false));
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        int sum = 0;
        int count = 0;
        for (int y = 0; y < scale; y++) {
          for (int x = 0; x < scale; x++) {
            int pixelX = col * scale + x;
            int pixelY = row * scale + y;
            int index =
                (pixelY * width + pixelX) * 4; // 4 bytes per pixel (RGBA)
            if (index + 3 < data.length) {
              // Calculate brightness using average of R, G, B channels.
              int r = data[index];
              int g = data[index + 1];
              int b = data[index + 2];
              int brightness = ((r + g + b) / 3).round();
              sum += brightness;
              count++;
            }
          }
        }
        double avgBrightness = sum / count;
        matrix[row][col] = avgBrightness < 128;
      }
    }
    return {'matrix': matrix};
  }

  Future<List<String>> _processCustomFontMessage(
      String text, TextStyle style) async {
    try {
      List<Map<String, dynamic>> segments = [];
      // Parse text into segments
      String currentText = '';
      int i = 0;
      while (i < text.length) {
        if (text[i] == '<' && i + 5 < text.length && text[i + 5] == '>') {
          if (currentText.isNotEmpty) {
            segments.add({'type': 'text', 'content': currentText});
            currentText = '';
          }
          segments.add(
              {'type': 'image', 'index': int.parse(text[i + 2] + text[i + 3])});
          i += 6;
        } else {
          currentText += text[i];
          i++;
        }
      }
      if (currentText.isNotEmpty) {
        segments.add({'type': 'text', 'content': currentText});
      }

      List<List<bool>> combinedMatrix = List.generate(11, (_) => []);

      // Process each segment
      for (var segment in segments) {
        if (segment['type'] == 'text') {
          String text = segment['content'];
          for (int i = 0; i < text.length; i++) {
            String char = text[i];
            List<List<bool>> charMatrix;

            bool hasDescender = "ypgqj".contains(char);
            final matrix = await renderTextToMatrix(char, style,
                rows: 11, hasDescender: hasDescender);
            charMatrix = matrix['matrix'];

            // Add character matrix to combined matrix
            for (int row = 0; row < 11; row++) {
              combinedMatrix[row].addAll(charMatrix[row]);
            }
          }
        } else if (segment['type'] == 'image') {
          // Process bitmap
          int index = segment['index'];
          var key = controllerData.imageCache.keys.toList()[index];
          if (key is List) {
            String filename = key[0];
            List<dynamic>? decodedData =
                await fileHelper.readFromFile(filename);
            final List<List<dynamic>> image =
                decodedData!.cast<List<dynamic>>();
            List<List<int>> imageData =
                image.map((list) => list.cast<int>()).toList();
            var hexStrings = convertBitmapToLEDHex(imageData, true);

            // Convert hex strings back to bool matrix and add to combined matrix
            for (var hex in hexStrings) {
              List<List<bool>> segmentMatrix =
                  List.generate(11, (_) => List.filled(8, false));
              for (int i = 0; i < 11; i++) {
                String hexByte = hex.substring(i * 2, (i * 2) + 2);
                int value = int.parse(hexByte, radix: 16);
                for (int bit = 0; bit < 8; bit++) {
                  segmentMatrix[i][bit] = ((value >> (7 - bit)) & 1) == 1;
                }
              }
              // Add segment to combined matrix
              for (int row = 0; row < 11; row++) {
                combinedMatrix[row].addAll(segmentMatrix[row]);
              }
            }
          } else {
            var hexStrings =
                await imageUtils.generateLedHex(controllerData.vectors[index]);
            for (var hex in hexStrings) {
              List<List<bool>> segmentMatrix =
                  List.generate(11, (_) => List.filled(8, false));
              for (int i = 0; i < 11; i++) {
                String hexByte = hex.substring(i * 2, (i * 2) + 2);
                int value = int.parse(hexByte, radix: 16);
                for (int bit = 0; bit < 8; bit++) {
                  segmentMatrix[i][bit] = ((value >> (7 - bit)) & 1) == 1;
                }
              }
              // Add segment to combined matrix
              for (int row = 0; row < 11; row++) {
                combinedMatrix[row].addAll(segmentMatrix[row]);
              }
            }
          }
        }
      }

      // Add final padding to make total columns divisible by 8
      int totalColumns = combinedMatrix[0].length;
      if (totalColumns % 8 != 0) {
        int paddingNeeded = 8 - (totalColumns % 8);
        final padding = List.filled(paddingNeeded, false);
        for (var row in combinedMatrix) {
          row.addAll(padding);
        }
      }

      // Convert to hex in 8-column segments
      List<String> allHexStrings = [];
      int segmentss = combinedMatrix[0].length ~/ 8;

      for (int seg = 0; seg < segmentss; seg++) {
        final startCol = seg * 8;
        final segmentMatrix = List.generate(
            11, (row) => combinedMatrix[row].sublist(startCol, startCol + 8));
        allHexStrings.addAll(_matrixToHex(segmentMatrix));
      }

      return allHexStrings;
    } catch (e) {
      logger.e("Error processing segments", error: e);
      return [];
    }
  }

  Future<List<String>> messageTohex(String message, bool isInverted) async {
    if (message.isEmpty) return [];

    final fontProvider = GetIt.instance<FontProvider>();
    final usingCustomFont = fontProvider.selectedFont != null;

    // Process message in custom font mode or default mode
    List<String> hexStrings = usingCustomFont
        ? await _processCustomFontMessage(
            message, fontProvider.selectedTextStyle)
        : await _processDefaultFont(message);

    if (isInverted) {
      return _processInversion(hexStrings);
    }

    return hexStrings;
  }

  Future<List<String>> _processDefaultFont(String text) async {
    List<Map<String, dynamic>> segments = [];
    String currentText = '';

    int i = 0;
    while (i < text.length) {
      if (text[i] == '<' && i + 5 < text.length && text[i + 5] == '>') {
        if (currentText.isNotEmpty) {
          segments.add({'type': 'text', 'content': currentText});
          currentText = '';
        }
        segments.add(
            {'type': 'image', 'index': int.parse(text[i + 2] + text[i + 3])});
        i += 6;
      } else {
        currentText += text[i];
        i++;
      }
    }
    if (currentText.isNotEmpty) {
      segments.add({'type': 'text', 'content': currentText});
    }

    List<String> hexStrings = [];
    for (var segment in segments) {
      if (segment['type'] == 'text') {
        String text = segment['content'];
        hexStrings.addAll(text
            .split('')
            .where((char) => converter.charCodes.containsKey(char))
            .map((char) => converter.charCodes[char]!)
            .toList());
      } else if (segment['type'] == 'image') {
        int index = segment['index'];
        var key = controllerData.imageCache.keys.toList()[index];
        if (key is List) {
          String filename = key[0];
          List<dynamic>? decodedData = await fileHelper.readFromFile(filename);
          final List<List<dynamic>> image = decodedData!.cast<List<dynamic>>();
          List<List<int>> imageData =
              image.map((list) => list.cast<int>()).toList();
          hexStrings.addAll(convertBitmapToLEDHex(imageData, true));
        } else {
          hexStrings.addAll(
              await imageUtils.generateLedHex(controllerData.vectors[index]));
        }
      }
    }
    return hexStrings;
  }

  List<String> _processInversion(List<String> hexStrings) {
    final inverted = invertHex(hexStrings.join()).split('');
    return padHexString(inverted);
  }

  static List<String> convertBitmapToLEDHex(List<List<int>> image, bool trim) {
    int height = image.length;
    int width = image.isNotEmpty ? image[0].length : 0;

    // Initialize variables to calculate padding and offsets
    int finalSum = 0;

    // Calculate and adjust for right-side padding
    for (int j = 0; j < width; j++) {
      int sum = 0;
      for (int i = 0; i < height; i++) {
        sum += image[i][j]; // Sum up pixel values in each column
      }
      if (sum == 0 && trim) {
        // If column sum is zero, mark all pixels in that column as -1
        for (int i = 0; i < height; i++) {
          image[i][j] = -1;
        }
      } else {
        // Otherwise, update finalSum and exit loop
        finalSum += j;
        break;
      }
    }

    // Calculate and adjust for left-side padding
    for (int j = width - 1; j >= 0; j--) {
      int sum = 0;
      for (int i = 0; i < height; i++) {
        sum += image[i][j];
      }
      if (sum == 0 && trim) {
        // If column sum is zero, mark all pixels in that column as -1
        for (int i = 0; i < height; i++) {
          image[i][j] = -1;
        }
      } else {
        // Otherwise, update finalSum and exit loop
        finalSum += (height - j - 1);
        break;
      }
    }

    int diff = 0;
    if ((height - finalSum) % 8 > 0) {
      diff = 8 - (height - finalSum) % 8;
    }

    int rOff = (diff / 2).floor();
    int lOff = (diff / 2).ceil();

    List<List<int>> list =
        List.generate(height, (i) => List.filled(width + rOff + lOff, 0));

    for (int i = 0; i < height; i++) {
      int k = 0;
      for (int j = 0; j < rOff; j++) {
        list[i][k++] = 0;
      }
      for (int j = 0; j < width; j++) {
        if (image[i][j] != -1) {
          list[i][k++] = image[i][j];
        }
      }
      for (int j = 0; j < lOff; j++) {
        list[i][k++] = 0;
      }
    }

    logger.d("Padded image: $list");

    List<String> allHexs = [];
    for (int i = 0; i < list[0].length ~/ 8; i++) {
      StringBuffer lineHex = StringBuffer();

      for (int k = 0; k < height; k++) {
        StringBuffer stBuilder = StringBuffer();

        for (int j = i * 8; j < i * 8 + 8; j++) {
          stBuilder.write(list[k][j]);
        }

        String hex = int.parse(stBuilder.toString(), radix: 2)
            .toRadixString(16)
            .padLeft(2, '0');
        lineHex.write(hex);
      }

      allHexs.add(lineHex.toString());
    }
    return allHexs;
  }

  static String invertHex(String hex) {
    StringBuffer invertedHex = StringBuffer();
    for (int i = 0; i < hex.length; i++) {
      String invertedHexDigit =
          (~int.parse(hex[i], radix: 16) & 0xF).toRadixString(16).toUpperCase();
      invertedHex.write(invertedHexDigit);
    }
    return invertedHex.toString();
  }

  List<String> padHexString(List<String> hexString) {
    List<List<int>> hexArray = hexStringToBool(hexString.join()).map((e) {
      return e.map((e) => e ? 1 : 0).toList();
    }).toList();

    for (int i = 0; i < hexArray.length; i++) {
      hexArray[i].insert(0, 1);
      hexArray[i].add(1);
    }

    return convertBitmapToLEDHex(hexArray, true);
  }
}
