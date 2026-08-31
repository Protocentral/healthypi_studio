import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/waveform_models.dart';
import 'package:healthypi_studio/theme/app_theme.dart';
import 'package:healthypi_studio/widgets/hpi/hpi_wave.dart';

/// `ChannelController` deliberately does not notify on every sample, so a trace
/// that repainted only when its parent rebuilt advanced at whatever rate some
/// unrelated widget happened to change — about 1 Hz with no device attached.
/// These tests pin the trace's independence: samples in, pixels out, with the
/// widget tree held completely still.
void main() {
  final boundary = GlobalKey();
  var builds = 0;

  ChannelData channel() => ChannelData(
        config: ChannelConfiguration(
          id: 'ecg1',
          label: 'Lead I',
          unit: 'mV',
          autoScale: false,
          minValue: -100,
          maxValue: 100,
        ),
        samplingRate: 500,
      );

  void feed(ChannelData data, int count, double Function(int) shape) {
    for (var i = 0; i < count; i++) {
      data.addDataPoint(DataPoint(
        value: shape(i),
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 2),
        sampleIndex: i,
      ));
    }
  }

  Future<Uint8List> pixels(WidgetTester tester) async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  Future<void> mount(WidgetTester tester, ChannelData data) async {
    builds = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: 240,
              height: 120,
              // Nothing above the trace ever rebuilds: no controller listener,
              // no provider, no ticker but the trace's own.
              child: Builder(builder: (context) {
                builds++;
                return HpiWaveTrace(
                  data: data,
                  windowSeconds: 2,
                  color: const Color(0xFFE8A33D),
                );
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('new samples repaint the trace without a parent rebuild',
      (tester) async {
    final data = channel();
    await mount(tester, data);
    final buildsAfterMount = builds;

    feed(data, 400, (i) => 0);
    await tester.pump(const Duration(milliseconds: 16));
    final flat = await pixels(tester);

    feed(data, 400, (i) => 80 * math.sin(i / 12));
    await tester.pump(const Duration(milliseconds: 16));
    final wave = await pixels(tester);

    expect(wave, isNot(equals(flat)),
        reason: 'the trace did not repaint when samples landed');
    expect(builds, buildsAfterMount,
        reason: 'the repaint must not come from rebuilding the widget');
  });

  testWidgets('a still buffer does not repaint', (tester) async {
    final data = channel();
    await mount(tester, data);

    feed(data, 400, (i) => 80 * math.sin(i / 12));
    await tester.pump(const Duration(milliseconds: 16));
    final first = await pixels(tester);

    // Several frames with no new samples — a frozen or paused acquisition.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final second = await pixels(tester);

    expect(second, equals(first));
  });
}
