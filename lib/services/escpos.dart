import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../models/app_settings.dart';
import 'receipt_builder.dart';

/// Converts receipt PDFs into ESC/POS commands for 58/80 mm thermal printers.
/// Each PDF page (kitchen ticket, customer receipt) is rendered at the printer's
/// resolution, sent as a monochrome raster image, then the paper is fed and cut.
/// This works with practically every thermal receipt printer, even when Windows
/// only has the "Generic / Text Only" driver for it.
class EscPos {
  EscPos._();

  /// Printable dots per line (203 dpi heads).
  static int dotsFor(PaperSize paper) => paper == PaperSize.mm58 ? 384 : 576;

  static const _init = [0x1B, 0x40]; // ESC @
  static const _feedAndCut = [0x1B, 0x64, 0x04, 0x1D, 0x56, 0x42, 0x00]; // ESC d 4, GS V 66 0

  /// Renders every page of [pdf] and returns the printer byte stream.
  static Future<Uint8List> fromPdf(Uint8List pdf, PaperSize paper) async {
    final dots = dotsFor(paper);
    final pageWidthPt = ReceiptBuilder.formatFor(paper).width;
    final dpi = dots * 72 / pageWidthPt - 0.05; // page width maps onto the print head
    final out = BytesBuilder()..add(_init);
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      out.add(encodeRaster(page.width, page.height, page.pixels, maxDots: dots));
      out.add(_feedAndCut);
    }
    return out.takeBytes();
  }

  /// RGBA pixels -> GS v 0 raster commands (black where the pixel is dark).
  /// Trailing blank rows are dropped; bands of [band] rows keep printer buffers small.
  static Uint8List encodeRaster(int width, int height, Uint8List rgba,
      {required int maxDots, int threshold = 128, int band = 96}) {
    final w = width > maxDots ? maxDots : width;
    final bytesPerRow = (w + 7) ~/ 8;
    final bits = Uint8List(bytesPerRow * height);
    var lastInked = -1;
    for (var y = 0; y < height; y++) {
      var rowInk = false;
      final rowBase = y * width * 4;
      for (var x = 0; x < w; x++) {
        final i = rowBase + x * 4;
        final a = rgba[i + 3];
        final lum = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        final onWhite = 255 - (a * (255 - lum)) ~/ 255; // composite over white paper
        if (onWhite < threshold) {
          bits[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
          rowInk = true;
        }
      }
      if (rowInk) lastInked = y;
    }
    final rows = lastInked < 0 ? 0 : (lastInked + 8).clamp(0, height);
    final out = BytesBuilder();
    for (var y0 = 0; y0 < rows; y0 += band) {
      final h = (rows - y0) < band ? rows - y0 : band;
      out.add([0x1D, 0x76, 0x30, 0x00, bytesPerRow & 0xFF, bytesPerRow >> 8, h & 0xFF, h >> 8]);
      out.add(Uint8List.sublistView(bits, y0 * bytesPerRow, (y0 + h) * bytesPerRow));
    }
    return out.takeBytes();
  }
}
