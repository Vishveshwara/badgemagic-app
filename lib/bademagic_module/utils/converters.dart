import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:badgemagic/bademagic_module/utils/byte_array_utils.dart';
import 'package:badgemagic/bademagic_module/utils/data_to_bytearray_converter.dart';
import 'package:badgemagic/bademagic_module/utils/file_helper.dart';
import 'package:badgemagic/bademagic_module/utils/image_utils.dart';
import 'package:badgemagic/providers/font_provider.dart';
import 'package:badgemagic/providers/imageprovider.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

class Converters {
  InlineImageProvider controllerData =
      GetIt.instance.get<InlineImageProvider>();
  DataToByteArrayConverter converter = DataToByteArrayConverter();
  ImageUtils imageUtils = ImageUtils();
  FileHelper fileHelper = FileHelper();

  List<String> _matrixToHex(List<List<bool>> matrix) {
    return matrix.map((row) {
      String binary = row.map((b) => b ? '1' : '0').join();
      return int.parse(binary, radix: 2).toRadixString(16).padLeft(2, '0');
    }).toList();
  }

  Future<Map<String, dynamic>> renderTextToMatrix(
    String message,
    TextStyle textStyle, {
    int cols = 8,
    int rows = 11,
    int scale = 1,
    required bool hasDescender, // for characters like j, g, p, q, y
  }) async {
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
    final bool isWide = widthCheckPainter.width > cols * scale;
    // Adjust columns if wide
    if (isWide) cols = 16;

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
      // Adjust position for characters with descenders
      final baselinePosition = height * 0.8;
      offset = Offset(
        0,
        baselinePosition -
            textPainter
                .computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
    } else {
      // Center text for normal characters
      offset = Offset(
        (width - textPainter.width) / 2,
        (height - textPainter.height) / 2,
      );
    }

    textPainter.paint(canvas, offset);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) {
      throw Exception("Failed to convert image to byte data.");
    }
    final Uint8List data = byteData.buffer.asUint8List();

    // Downsample: For each cell (scale x scale block) compute average brightness.
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
        // Use a threshold of 128 to decide if the LED is on (true) or off (false)
        matrix[row][col] = avgBrightness < 128;
      }
    }
    //print(matrix);
    return {'matrix': matrix, 'isWide': isWide};
  }

  Future<List<String>> _processCustomFontChar(
      String char, TextStyle style) async {
    try {
      bool hasDescender = false;
      if (char == "y" ||
          char == "g" ||
          char == "p" ||
          char == "q" ||
          char == "j") {
        hasDescender = true;
      }
      final matrix = await renderTextToMatrix(char, style,
          cols: 8, // Match original character width
          rows: 11, // Match original character height
          scale: 1,
          hasDescender: hasDescender);
      if (matrix['isWide']) {
        final List<List<bool>> matrix1 = [];
        final List<List<bool>> matrix2 = [];
        for (var row in matrix['matrix']) {
          // Get the first 8 columns.
          matrix1.add(row.sublist(0, 8));
          // Get the remaining 8 columns.
          matrix2.add(row.sublist(8, 16));
        }
        var x = _matrixToHex(matrix1);
        var y = _matrixToHex(matrix2);
        x.addAll(y);
        return x;
      } else {
        return _matrixToHex(matrix['matrix']);
      }
    } catch (e) {
      logger.e("Error rendering character '$char'", error: e);
      return [];
    }
  }

  int controllerLength = 0;

  Future<List<String>> messageTohex(String message, bool isInverted) async {
    final fontProvider = GetIt.instance<FontProvider>();
    final usingCustomFont = fontProvider.selectedFont != null;
    List<String> hexStrings = [];
    for (int x = 0; x < message.length; x++) {
      if (message[x] == '<' && message[min(x + 5, message.length - 1)] == '>') {
        int index = int.parse(message[x + 2] + message[x + 3]);
        var key = controllerData.imageCache.keys.toList()[index];
        if (key is List) {
          String filename = key[0];
          List<dynamic>? decodedData = await fileHelper.readFromFile(filename);
          final List<List<dynamic>> image = decodedData!.cast<List<dynamic>>();
          List<List<int>> imageData =
              image.map((list) => list.cast<int>()).toList();
          hexStrings += convertBitmapToLEDHex(imageData, true);
          x += 5;
        } else {
          List<String> hs =
              await imageUtils.generateLedHex(controllerData.vectors[index]);
          hexStrings.addAll(hs);
          x += 5;
        }
      } else {
        if (usingCustomFont) {
          // Handle custom font rendering
          final charHex = await _processCustomFontChar(
            message[x],
            fontProvider.selectedTextStyle,
          );
          //print("charhex - $charHex");
          hexStrings.addAll(charHex);
        } else {
          // Original character handling
          if (converter.charCodes.containsKey(message[x])) {
            hexStrings.add(converter.charCodes[message[x]]!);
          }
        }
      }
    }

    if (isInverted) {
      hexStrings = invertHex(hexStrings.join()).split('');
      hexStrings = padHexString(hexStrings);
    }
    logger.d("Hex strings: $hexStrings");
    return hexStrings;
  }

  //function to convert the bitmap to the LED hex format
  //it takes the 2D list of pixels and converts it to the LED hex format
  static List<String> convertBitmapToLEDHex(List<List<int>> image, bool trim) {
    // Determine the height and width of the image
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
        sum += image[i]
            [j]; // Sum up pixel values in each column (from right to left)
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

    // Calculate padding difference to align height to a multiple of 8
    int diff = 0;
    if ((height - finalSum) % 8 > 0) {
      diff = 8 - (height - finalSum) % 8;
    }

    // Calculate left and right offsets for padding
    int rOff = (diff / 2).floor();
    int lOff = (diff / 2).ceil();

    // Initialize a new list to accommodate the padded image
    List<List<int>> list =
        List.generate(height, (i) => List.filled(width + rOff + lOff, 0));

    // Fill the new list with the padded image data
    for (int i = 0; i < height; i++) {
      int k = 0;
      for (int j = 0; j < rOff; j++) {
        list[i][k++] = 0; // Fill right-side padding
      }
      for (int j = 0; j < width; j++) {
        if (image[i][j] != -1) {
          list[i][k++] = image[i][j]; // Copy non-padded pixels
        }
      }
      for (int j = 0; j < lOff; j++) {
        list[i][k++] = 0; // Fill left-side padding
      }
    }

    logger.d("Padded image: $list");

    // Convert each 8-bit segment into hexadecimal strings
    List<String> allHexs = [];
    for (int i = 0; i < list[0].length ~/ 8; i++) {
      StringBuffer lineHex = StringBuffer();

      for (int k = 0; k < height; k++) {
        StringBuffer stBuilder = StringBuffer();

        // Construct 8-bit segments for each row
        for (int j = i * 8; j < i * 8 + 8; j++) {
          stBuilder.write(list[k][j]);
        }

        // Convert binary string to hexadecimal
        String hex = int.parse(stBuilder.toString(), radix: 2)
            .toRadixString(16)
            .padLeft(2, '0');
        lineHex.write(hex); // Append hexadecimal to line
      }

      allHexs.add(lineHex.toString()); // Store completed hexadecimal line
    }
    return allHexs; // Return list of hexadecimal strings
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

    //add 1 at the satrt and end of each row in the 2D list
    for (int i = 0; i < hexArray.length; i++) {
      hexArray[i].insert(0, 1);
      hexArray[i].add(1);
    }

    return convertBitmapToLEDHex(hexArray, true);
  }
}
