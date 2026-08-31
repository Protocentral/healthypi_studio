import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/filter_models.dart';
import 'package:healthypi_studio/services/digital_filter.dart';
import 'package:healthypi_studio/services/filter_preset_manager.dart';
import 'dart:math';

void main() {
  group('FilterDesign Validation', () {
    test('Valid lowpass filter design', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      expect(design.validate(), isNull);
    });

    test('Invalid filter order (odd)', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 3, // Odd order
        samplingRate: 500,
      );

      expect(design.validate(), isNotNull);
      expect(design.validate(), contains('even'));
    });

    test('Cutoff frequency exceeds Nyquist', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 300, // > 250 Hz (Nyquist)
        order: 4,
        samplingRate: 500,
      );

      expect(design.validate(), isNotNull);
    });

    test('Bandpass with invalid frequency range', () {
      final design = FilterDesign(
        type: FilterType.bandpass,
        cutoffLow: 40,
        cutoffHigh: 20, // High < Low
        order: 4,
        samplingRate: 500,
      );

      expect(design.validate(), isNotNull);
      expect(design.validate(), contains('greater'));
    });

    test('Notch filter with zero Q-factor', () {
      final design = FilterDesign(
        type: FilterType.notch,
        cutoffLow: 50,
        order: 4,
        samplingRate: 500,
        qFactor: 0, // Invalid
      );

      expect(design.validate(), isNotNull);
    });
  });

  group('FilterDesign Coefficients', () {
    test('Lowpass filter coefficients generation', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();

      expect(coeffs.sos, isNotEmpty);
      expect(coeffs.sos.length, equals(2)); // Order 4 = 2 second-order sections
      expect(coeffs.gain, isPositive);

      // Each SOS should have 6 coefficients [b0, b1, b2, a0, a1, a2]
      for (final section in coeffs.sos) {
        expect(section.length, equals(6));
      }
    });

    test('Highpass filter coefficients generation', () {
      final design = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();
      expect(coeffs.sos.isNotEmpty, true);
      expect(coeffs.sos.length, equals(2));
    });

    test('Bandpass filter coefficients generation', () {
      final design = FilterDesign(
        type: FilterType.bandpass,
        cutoffLow: 0.5,
        cutoffHigh: 40,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();
      expect(coeffs.sos.isNotEmpty, true);
    });

    test('Notch filter coefficients generation', () {
      final design = FilterDesign(
        type: FilterType.notch,
        cutoffLow: 50,
        order: 4,
        samplingRate: 500,
        qFactor: 30,
      );

      final coeffs = design.designFilter();
      expect(coeffs.sos.isNotEmpty, true);
      expect(coeffs.type, equals(FilterType.notch));
    });
  });

  group('Real-Time Digital Filter', () {
    test('Single sample processing', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filter = DigitalFilter(design.designFilter());
      final output = filter.processSample(1.0);

      expect(output.isFinite, true);
    });

    test('Batch processing', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filter = DigitalFilter(design.designFilter());
      final input = List<double>.filled(100, 1.0);
      final output = filter.processBatch(input);

      expect(output.length, equals(100));
      expect(output.every((v) => v.isFinite), true);
    });

    test('Filter state management', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filter = DigitalFilter(design.designFilter());
      filter.processSample(1.0);
      filter.processSample(2.0);

      final state = filter.getState();
      expect(state.length, greaterThan(0));

      filter.reset();
      final resetState = filter.getState();
      for (final s in resetState) {
        expect(s.every((v) => v == 0.0), true);
      }
    });

    test('Lowpass passes DC at unity gain', () {
      // Replaces a stale TODO that claimed the Butterworth gain calculation was
      // unnormalized and needed fixing in `ButterworthDesigner._calculateGain()`
      // — a method that does not exist. The bilinear-transform sections are in
      // fact correctly normalized: summing the biquad numerator and denominator
      // gives H(1) = 4*wc^2 / 4*wc^2 = 1 exactly, for every section and every Q.
      // Verified analytically and by simulation on 2026-08-31. The old test only
      // asserted `returnsNormally`, so it could not have caught a gain error
      // either way.
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filter = DigitalFilter(design.designFilter());

      double out = 0;
      for (int i = 0; i < 4000; i++) {
        out = filter.processSample(1.0);
      }

      // A lowpass fed a DC step must settle at the input amplitude.
      expect(out, closeTo(1.0, 1e-6));
      expect(out.isFinite, isTrue);
    });

    test('Highpass rejects DC', () {
      final design = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      final filter = DigitalFilter(design.designFilter());

      double out = 0;
      for (int i = 0; i < 8000; i++) {
        out = filter.processSample(1.0);
      }

      expect(out, closeTo(0.0, 1e-3));
    });
  });

  group('Filter Chain', () {
    test('Multiple filters in series', () {
      final design1 = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      final design2 = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filter1 = DigitalFilter(design1.designFilter());
      final filter2 = DigitalFilter(design2.designFilter());
      final chain = FilterChain([filter1, filter2]);

      final output = chain.processSample(1.0);
      expect(output.isFinite, true);
    });

    test('Filter chain reset', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filter1 = DigitalFilter(design.designFilter());
      final filter2 = DigitalFilter(design.designFilter());
      final chain = FilterChain([filter1, filter2]);

      chain.processSample(1.0);
      chain.reset();

      // All filters should be reset
      expect(filter1.getState().every((s) => s.every((v) => v == 0.0)), true);
      expect(filter2.getState().every((s) => s.every((v) => v == 0.0)), true);
    });
  });

  group('Offline Filtering', () {
    test('Forward-only offline filtering', () {
      final data = List<double>.filled(100, 1.0);

      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filtered = OfflineFilter.apply(data, design, zeroPhase: false);

      expect(filtered.length, equals(100));
      expect(filtered.every((v) => v.isFinite), true);
    });

    test('Zero-phase offline filtering', () {
      // Create test signal with DC offset
      final data = List<double>.generate(100, (i) => 1.0 + 0.1 * sin(2 * pi * i / 20));

      final design = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      final filtered = OfflineFilter.apply(data, design, zeroPhase: true);

      expect(filtered.length, equals(100));
      expect(filtered.every((v) => v.isFinite), true);
    });

    test('Filter chain offline', () {
      final data = List<double>.generate(100, (i) => sin(2 * pi * 10 * i / 500));

      final designs = [
        FilterDesign(
          type: FilterType.highpass,
          cutoffLow: 0.5,
          order: 4,
          samplingRate: 500,
        ),
        FilterDesign(
          type: FilterType.lowpass,
          cutoffLow: 40,
          order: 4,
          samplingRate: 500,
        ),
      ];

      final filtered = OfflineFilter.applyFilterChain(data, designs);

      expect(filtered.length, equals(100));
      expect(filtered.every((v) => v.isFinite), true);
    });

    test('Offline filtering with padding', () {
      final data = List<double>.filled(50, 1.0);

      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filtered = OfflineFilter.applyWithPadding(data, design, padLength: 20);

      expect(filtered.length, equals(50));
      expect(filtered.every((v) => v.isFinite), true);
    });
  });

  group('Frequency Response', () {
    test('Evaluate frequency response', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();
      final frequencies = [1.0, 10.0, 40.0, 100.0, 200.0];
      final response = coeffs.evaluateFrequencyResponse(frequencies);

      expect(response.frequencies.length, equals(5));
      expect(response.magnitudes.length, equals(5));
      expect(response.phases.length, equals(5));

      // All magnitudes should be positive
      expect(response.magnitudes.every((m) => m > 0), true);
    });

    test('Magnitude response in dB', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();
      final frequencies = [1.0, 10.0, 40.0, 100.0, 200.0];
      final response = coeffs.evaluateFrequencyResponse(frequencies);
      final magnitudesDB = response.getMagnitudesDB();

      expect(magnitudesDB.length, equals(5));
      expect(magnitudesDB.every((m) => m < 0), true); // Should be mostly negative dB
    });

    test('Lowpass filter frequency response shape', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();
      final frequencies = List<double>.generate(10, (i) => (i + 1) * 20);
      final response = coeffs.evaluateFrequencyResponse(frequencies);
      final magnitudesDB = response.getMagnitudesDB();

      // Lowpass should have decreasing magnitude response at higher frequencies
      for (int i = 0; i < magnitudesDB.length - 1; i++) {
        expect(magnitudesDB[i], greaterThanOrEqualTo(magnitudesDB[i + 1]));
      }
    });

    test('Highpass filter frequency response shape', () {
      final design = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      final coeffs = design.designFilter();
      final frequencies = [0.1, 0.5, 1.0, 5.0, 10.0];
      final response = coeffs.evaluateFrequencyResponse(frequencies.cast<double>());
      final magnitudesDB = response.getMagnitudesDB();

      // Highpass should have increasing magnitude response at higher frequencies
      for (int i = 0; i < magnitudesDB.length - 1; i++) {
        expect(magnitudesDB[i], lessThanOrEqualTo(magnitudesDB[i + 1]));
      }
    });
  });

  group('Filter Presets', () {
    test('Get all presets', () {
      final presets = FilterPresetManager.getAllPresets();
      expect(presets.isNotEmpty, true);
    });

    test('Get presets by category', () {
      final ecgPresets = FilterPresetManager.getPresetsByCategory('ECG');
      expect(ecgPresets.isNotEmpty, true);

      for (final preset in ecgPresets) {
        expect(preset.category, equals('ECG'));
      }
    });

    test('Find preset by name', () {
      final preset = FilterPresetManager.findPreset('ECG Cleanup');
      expect(preset, isNotNull);
      expect(preset!.name, equals('ECG Cleanup'));
      expect(preset.filters.isNotEmpty, true);
    });

    test('Create custom preset', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final preset = FilterPresetManager.createCustomPreset(
        name: 'My Custom Filter',
        filter: design,
        description: 'Test custom preset',
      );

      expect(preset.name, equals('My Custom Filter'));
      expect(preset.isCustom, true);
      expect(preset.filters.length, equals(1));
    });

    test('Create custom chain preset', () {
      final designs = [
        FilterDesign(
          type: FilterType.highpass,
          cutoffLow: 0.5,
          order: 4,
          samplingRate: 500,
        ),
        FilterDesign(
          type: FilterType.lowpass,
          cutoffLow: 40,
          order: 4,
          samplingRate: 500,
        ),
      ];

      final preset = FilterPresetManager.createCustomChainPreset(
        name: 'Custom Chain',
        filters: designs,
      );

      expect(preset.filters.length, equals(2));
      expect(preset.isCustom, true);
    });

    test('Get unique categories', () {
      final categories = FilterPresetManager.getCategories();
      expect(categories.isNotEmpty, true);
      expect(categories, contains('ECG'));
      expect(categories, contains('EMG'));
      expect(categories, contains('EEG'));
    });

    test('ECG Cleanup preset validity', () {
      final preset = FilterPresetManager.findPreset('ECG Cleanup');
      expect(preset, isNotNull);

      // All filters in preset should be valid
      for (final filter in preset!.filters) {
        expect(filter.validate(), isNull);
      }
    });

    test('EMG preset validity', () {
      final preset = FilterPresetManager.findPreset('EMG Noise Reduction');
      expect(preset, isNotNull);

      for (final filter in preset!.filters) {
        expect(filter.validate(), isNull);
      }
    });

    test('EEG preset validity', () {
      final preset = FilterPresetManager.findPreset('EEG Standard');
      expect(preset, isNotNull);

      for (final filter in preset!.filters) {
        expect(filter.validate(), isNull);
      }
    });
  });

  group('Adaptive Filter', () {
    test('Initial filter design', () {
      final initialDesign = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final adaptiveFilter = AdaptiveFilter(
        initialDesign: initialDesign,
        samplingRate: 500,
      );

      expect(adaptiveFilter.currentDesign.type, equals(FilterType.lowpass));
    });

    test('Update filter design', () {
      final initialDesign = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final adaptiveFilter = AdaptiveFilter(
        initialDesign: initialDesign,
        samplingRate: 500,
      );

      final newDesign = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      adaptiveFilter.updateDesign(newDesign);
      expect(adaptiveFilter.currentDesign.type, equals(FilterType.highpass));
    });

    test('Update design callback', () {
      var callbackCalled = false;

      final initialDesign = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final adaptiveFilter = AdaptiveFilter(
        initialDesign: initialDesign,
        samplingRate: 500,
        onDesignChanged: (design) {
          callbackCalled = true;
        },
      );

      final newDesign = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.5,
        order: 4,
        samplingRate: 500,
      );

      adaptiveFilter.updateDesign(newDesign);
      expect(callbackCalled, true);
    });
  });

  group('Edge Cases', () {
    test('Empty data handling', () {
      final data = <double>[];
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filtered = OfflineFilter.apply(data, design);
      expect(filtered.isEmpty, true);
    });

    test('Single sample data', () {
      final data = [1.0];
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 4,
        samplingRate: 500,
      );

      final filtered = OfflineFilter.apply(data, design);
      expect(filtered.length, equals(1));
      expect(filtered[0].isFinite, true);
    });

    test('Very small filter cutoff', () {
      final design = FilterDesign(
        type: FilterType.highpass,
        cutoffLow: 0.01,
        order: 4,
        samplingRate: 500,
      );

      expect(design.validate(), isNull);
      final coeffs = design.designFilter();
      expect(coeffs.sos.isNotEmpty, true);
    });

    test('High-order filter', () {
      final design = FilterDesign(
        type: FilterType.lowpass,
        cutoffLow: 40,
        order: 8,
        samplingRate: 500,
      );

      final filter = DigitalFilter(design.designFilter());
      final output = filter.processSample(1.0);
      expect(output.isFinite, true);
    });
  });
}
