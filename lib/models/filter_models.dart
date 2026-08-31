import 'dart:math';

/// Filter type enumeration
enum FilterType {
  highpass,
  lowpass,
  bandpass,
  notch,
}

/// Filter configuration for signal processing
class FilterDesign {
  final FilterType type;
  final double cutoffLow; // Hz
  final double? cutoffHigh; // Hz (for bandpass)
  final int order; // 2, 4, 6, 8, etc
  final double samplingRate; // Hz
  final double? qFactor; // For notch filter (default: 30)

  const FilterDesign({
    required this.type,
    required this.cutoffLow,
    this.cutoffHigh,
    this.order = 4,
    required this.samplingRate,
    this.qFactor,
  });

  /// Validate filter parameters
  String? validate() {
    if (order < 2 || order % 2 != 0) {
      return 'Filter order must be even (2, 4, 6, 8, ...)';
    }

    if (samplingRate <= 0) {
      return 'Sampling rate must be positive';
    }

    if (cutoffLow <= 0 || cutoffLow >= samplingRate / 2) {
      return 'Cutoff frequency must be between 0 and ${samplingRate / 2} Hz';
    }

    if (type == FilterType.bandpass && cutoffHigh != null) {
      if (cutoffHigh! <= cutoffLow) {
        return 'High cutoff must be greater than low cutoff';
      }
      if (cutoffHigh! >= samplingRate / 2) {
        return 'High cutoff must be below Nyquist frequency (${samplingRate / 2} Hz)';
      }
    }

    if (type == FilterType.notch) {
      final q = qFactor ?? 30.0;
      if (q <= 0) {
        return 'Q-factor must be positive';
      }
    }

    return null;
  }

  /// Get normalized cutoff frequencies (0 to 1)
  List<double> getNormalizedCutoffs() {
    final nyquist = samplingRate / 2;
    final wn = <double>[cutoffLow / nyquist];
    if (cutoffHigh != null) {
      wn.add(cutoffHigh! / nyquist);
    }
    return wn;
  }

  /// Design filter coefficients
  FilterCoefficients designFilter() {
    final error = validate();
    if (error != null) {
      throw ArgumentError(error);
    }

    final designer = ButterworthDesigner(this);
    return designer.designFilter();
  }

  @override
  String toString() {
    final highStr = cutoffHigh != null ? '-$cutoffHigh' : '';
    return 'FilterDesign($type, order=$order, cutoff=$cutoffLow$highStr Hz @ $samplingRate Hz)';
  }
}

/// Filter coefficients in second-order sections form (SOS)
class FilterCoefficients {
  /// Second-order sections: List of [b0, b1, b2, a0, a1, a2]
  final List<List<double>> sos;
  final double gain;
  final FilterType type;
  final double samplingRate;

  const FilterCoefficients({
    required this.sos,
    this.gain = 1.0,
    required this.type,
    required this.samplingRate,
  });

  int get numSections => sos.length;
  int get order => sos.length * 2;

  /// Evaluate frequency response at a single frequency
  FrequencyResponse evaluateFrequency(double frequency) {
    return evaluateFrequencyResponse([frequency]);
  }

  /// Evaluate frequency response at given frequencies
  FrequencyResponse evaluateFrequencyResponse(List<double> frequencies) {
    final magnitudes = <double>[];
    final phases = <double>[];

    for (final f in frequencies) {
      final w = 2 * pi * f / samplingRate;
      var realSum = gain;
      var imagSum = 0.0;

      for (final section in sos) {
        final b0 = section[0];
        final b1 = section[1];
        final b2 = section[2];
        final a0 = section[3];
        final a1 = section[4];
        final a2 = section[5];

        final cosW = cos(w);
        final sinW = sin(w);
        final cos2W = cos(2 * w);
        final sin2W = sin(2 * w);

        final numReal = b0 + b1 * cosW + b2 * cos2W;
        final numImag = -b1 * sinW - b2 * sin2W;

        final denomReal = a0 + a1 * cosW + a2 * cos2W;
        final denomImag = -a1 * sinW - a2 * sin2W;

        final denomMagnitudeSq =
            denomReal * denomReal + denomImag * denomImag;
        final sectionReal =
            (numReal * denomReal + numImag * denomImag) / denomMagnitudeSq;
        final sectionImag =
            (numImag * denomReal - numReal * denomImag) / denomMagnitudeSq;

        final newReal = realSum * sectionReal - imagSum * sectionImag;
        final newImag = realSum * sectionImag + imagSum * sectionReal;
        realSum = newReal;
        imagSum = newImag;
      }

      magnitudes.add(sqrt(realSum * realSum + imagSum * imagSum));
      phases.add(atan2(imagSum, realSum));
    }

    return FrequencyResponse(
      frequencies: frequencies,
      magnitudes: magnitudes,
      phases: phases,
    );
  }

  @override
  String toString() => 'FilterCoefficients(order=$order, sections=${sos.length})';
}

/// Frequency response data
class FrequencyResponse {
  final List<double> frequencies;
  final List<double> magnitudes;
  final List<double> phases;

  const FrequencyResponse({
    required this.frequencies,
    required this.magnitudes,
    required this.phases,
  });

  List<double> getMagnitudesDB() {
    return magnitudes
        .map((m) => 20 * log10(m.clamp(1e-10, double.infinity)))
        .toList();
  }

  List<double> getPhasesDegrees() {
    return phases.map((p) => p * 180 / pi).toList();
  }

  static double log10(double value) => log(value) / log(10);
}

/// State of a second-order section
class SecondOrderState {
  double x1 = 0.0;
  double x2 = 0.0;
  double y1 = 0.0;
  double y2 = 0.0;

  void reset() {
    x1 = 0.0;
    x2 = 0.0;
    y1 = 0.0;
    y2 = 0.0;
  }

  @override
  String toString() => 'SecondOrderState(x1=$x1, x2=$x2, y1=$y1, y2=$y2)';
}

/// Complex number helper
class ComplexNum {
  final double real;
  final double imag;

  ComplexNum(this.real, this.imag);

  ComplexNum scaleBy(double s) => ComplexNum(real * s, imag * s);
  ComplexNum add(ComplexNum o) => ComplexNum(real + o.real, imag + o.imag);
  ComplexNum multiply(ComplexNum o) => ComplexNum(
        real * o.real - imag * o.imag,
        real * o.imag + imag * o.real,
      );

  ComplexNum inverse() {
    final denom = real * real + imag * imag;
    return ComplexNum(real / denom, -imag / denom);
  }

  double get magnitude => sqrt(real * real + imag * imag);
  double get phase => atan2(imag, real);
}

/// Analog pole representation
class AnalogPole {
  final double realPart;
  final double imagPart;
  final FilterType type;

  AnalogPole({
    required this.realPart,
    required this.imagPart,
    required this.type,
  });
}

/// Butterworth filter designer
/// Implements proper bilinear transform from analog to digital domain
class ButterworthDesigner {
  final FilterDesign design;

  ButterworthDesigner(this.design);

  FilterCoefficients designFilter() {
    switch (design.type) {
      case FilterType.lowpass:
        return _designLowpass();
      case FilterType.highpass:
        return _designHighpass();
      case FilterType.bandpass:
        return _designBandpass();
      case FilterType.notch:
        return _designNotch();
    }
  }

  /// Design 2nd-order lowpass section using bilinear transform
  /// Standard form: H(s) = wc^2 / (s^2 + s*wc/Q + wc^2)
  List<double> _designLowpass2ndOrder(double fc, double q) {
    final fs = design.samplingRate;
    // Pre-warp the cutoff frequency
    final wc = tan(pi * fc / fs);
    final wcSq = wc * wc;
    final k = wc / q;

    // Bilinear transform coefficients
    // H(z) = (b0 + b1*z^-1 + b2*z^-2) / (a0 + a1*z^-1 + a2*z^-2)
    final a0 = 1 + k + wcSq;
    final a1 = 2 * (wcSq - 1);
    final a2 = 1 - k + wcSq;

    final b0 = wcSq;
    final b1 = 2 * wcSq;
    final b2 = wcSq;

    // Normalize by a0
    return [b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0];
  }

  /// Design 2nd-order highpass section using bilinear transform
  List<double> _designHighpass2ndOrder(double fc, double q) {
    final fs = design.samplingRate;
    // Pre-warp the cutoff frequency
    final wc = tan(pi * fc / fs);
    final wcSq = wc * wc;
    final k = wc / q;

    // Bilinear transform coefficients for highpass
    final a0 = 1 + k + wcSq;
    final a1 = 2 * (wcSq - 1);
    final a2 = 1 - k + wcSq;

    final b0 = 1.0;
    final b1 = -2.0;
    final b2 = 1.0;

    // Normalize by a0
    return [b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0];
  }

  /// Get Q values for Butterworth filter poles
  /// For n-th order Butterworth, the k-th section has Q = 1 / (2 * cos(theta_k))
  /// where theta_k = pi * (2*k + 1) / (2*n)
  List<double> _getButterworthQValues(int order) {
    final numSections = order ~/ 2;
    final qValues = <double>[];

    for (int k = 0; k < numSections; k++) {
      final theta = pi * (2 * k + 1) / (2 * order);
      final q = 1.0 / (2.0 * cos(theta));
      qValues.add(q);
    }

    return qValues;
  }

  /// Design lowpass Butterworth filter
  FilterCoefficients _designLowpass() {
    final sos = <List<double>>[];
    final qValues = _getButterworthQValues(design.order);

    for (final q in qValues) {
      sos.add(_designLowpass2ndOrder(design.cutoffLow, q));
    }

    return FilterCoefficients(
      sos: sos,
      gain: 1.0,
      type: design.type,
      samplingRate: design.samplingRate,
    );
  }

  /// Design highpass Butterworth filter
  FilterCoefficients _designHighpass() {
    final sos = <List<double>>[];
    final qValues = _getButterworthQValues(design.order);

    for (final q in qValues) {
      sos.add(_designHighpass2ndOrder(design.cutoffLow, q));
    }

    return FilterCoefficients(
      sos: sos,
      gain: 1.0,
      type: design.type,
      samplingRate: design.samplingRate,
    );
  }

  /// Design bandpass filter as cascade of highpass and lowpass
  FilterCoefficients _designBandpass() {
    final sos = <List<double>>[];
    final fl = design.cutoffLow;
    final fh = design.cutoffHigh!;

    // For bandpass, we split the order between HP and LP
    // Order 4 bandpass = 2nd order HP + 2nd order LP
    final halfOrder = design.order ~/ 2;
    final qValues = _getButterworthQValues(halfOrder.clamp(2, 8));

    // If halfOrder is 2, we get one section each
    // If halfOrder is 4, we get two sections each, etc.
    for (final q in qValues) {
      // Highpass section for low cutoff
      sos.add(_designHighpass2ndOrder(fl, q));
      // Lowpass section for high cutoff
      sos.add(_designLowpass2ndOrder(fh, q));
    }

    // For order=2 (halfOrder=1), add single sections
    if (sos.isEmpty) {
      sos.add(_designHighpass2ndOrder(fl, 0.7071)); // Q = 1/sqrt(2) for Butterworth
      sos.add(_designLowpass2ndOrder(fh, 0.7071));
    }

    return FilterCoefficients(
      sos: sos,
      gain: 1.0,
      type: design.type,
      samplingRate: design.samplingRate,
    );
  }

  /// Design notch filter using standard biquad formula
  FilterCoefficients _designNotch() {
    final q = design.qFactor ?? 30.0;
    final f0 = design.cutoffLow;
    final fs = design.samplingRate;

    // Normalized angular frequency
    final w0 = 2 * pi * f0 / fs;
    final cosW0 = cos(w0);
    final sinW0 = sin(w0);
    final alpha = sinW0 / (2 * q);

    // Notch filter coefficients (standard biquad)
    final b0 = 1.0;
    final b1 = -2 * cosW0;
    final b2 = 1.0;
    final a0 = 1 + alpha;
    final a1 = -2 * cosW0;
    final a2 = 1 - alpha;

    final sos = <List<double>>[
      [b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0],
    ];

    return FilterCoefficients(
      sos: sos,
      gain: 1.0,
      type: design.type,
      samplingRate: design.samplingRate,
    );
  }
}
