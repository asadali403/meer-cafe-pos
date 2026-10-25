import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meer_cafe_pos/models/app_settings.dart';
import 'package:meer_cafe_pos/services/escpos.dart';

Uint8List image(int w, int h, bool Function(int x, int y) black) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final v = black(x, y) ? 0 : 255;
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
      px[i + 3] = 255;
    }
  }
  return px;
}

void main() {
  test('print head widths', () {
    expect(EscPos.dotsFor(PaperSize.mm80), 576);
    expect(EscPos.dotsFor(PaperSize.mm58), 384);
  });

  test('raster becomes GS v 0 with correct bits', () {
    // 10 px wide, first row: x=0 and x=9 black; 2 rows of ink then white rows.
    final px = image(10, 20, (x, y) => y < 2 && (x == 0 || x == 9));
    final out = EscPos.encodeRaster(10, 20, px, maxDots: 576);
    expect(out.sublist(0, 4), [0x1D, 0x76, 0x30, 0x00]);
    expect(out[4] | (out[5] << 8), 2, reason: '2 bytes per row');
    final rows = out[6] | (out[7] << 8);
    expect(rows, 9, reason: 'rows 0..1 inked + 7 blank rows margin; rest trimmed');
    expect(out[8], 0x80); // x=0
    expect(out[9], 0x40); // x=9 -> bit 1 of second byte
  });

  test('wide images are clipped to the print head and banded', () {
    final px = image(700, 300, (x, y) => true);
    final out = EscPos.encodeRaster(700, 300, px, maxDots: 576, band: 96);
    expect(out[4] | (out[5] << 8), 72); // 576 / 8
    // 300 rows -> bands of 96,96,96,12
    var i = 0, bands = 0, total = 0;
    while (i < out.length) {
      final h = out[i + 6] | (out[i + 7] << 8);
      total += h;
      bands++;
      i += 8 + 72 * h;
    }
    expect(bands, 4);
    expect(total, 300);
  });

  test('blank page produces no raster data', () {
    expect(EscPos.encodeRaster(50, 50, image(50, 50, (_, _) => false), maxDots: 576), isEmpty);
  });
}
