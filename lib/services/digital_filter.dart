import '../models/filter_models.dart';

/// Real-time digital filter for streaming data
/// Implements causal (forward-only) IIR filtering using second-order sections
class DigitalFilter {
  final FilterCoefficients coefficients;
  final List<SecondOrderState> states;

  DigitalFilter(this.coefficients)
      : states = List.generate(
          coefficients.numSections,
          (_) => SecondOrderState(),
        );

  /// Process a single sample through the filter
  /// Applies filter to each second-order section in cascade
  double processSample(double input) {
    var output = input * coefficients.gain;

    // Apply each second-order section in cascade
    for (int i = 0; i < states.length; i++) {
      output = _processSOSection(output, states[i], i);
    }

    return output;
  }

  /// Process multiple samples and return filtered output
  List<double> processBatch(List<double> input) {
    return input.map((sample) => processSample(sample)).toList();
  }

  /// Process a section of data using Direct Form II Transposed
  /// This form is more numerically stable for IIR filters
  double _processSOSection(double x, SecondOrderState state, int sectionIdx) {
    final section = coefficients.sos[sectionIdx];
    final b0 = section[0];
    final b1 = section[1];
    final b2 = section[2];
    final a1 = section[4];
    final a2 = section[5];

    // Direct Form II Transposed (more numerically stable)
    // y[n] = b0*x[n] + s1[n-1]
    // s1[n] = b1*x[n] - a1*y[n] + s2[n-1]
    // s2[n] = b2*x[n] - a2*y[n]
    final y = b0 * x + state.x1;
    final s1 = b1 * x - a1 * y + state.x2;
    final s2 = b2 * x - a2 * y;

    // Update state (x1, x2 are used as s1, s2 state storage)
    state.x1 = s1;
    state.x2 = s2;

    return y;
  }

  /// Reset all internal filter states
  void reset() {
    for (final state in states) {
      state.reset();
    }
  }

  /// Get filter state for debugging/serialization
  /// Returns [s1, s2] for each section (Direct Form II Transposed states)
  List<List<double>> getState() {
    return states
        .map((s) => [s.x1, s.x2])
        .toList();
  }

  /// Set filter state (for recovery/continuation)
  void setState(List<List<double>> state) {
    for (int i = 0; i < states.length && i < state.length; i++) {
      states[i].x1 = state[i][0];
      states[i].x2 = state[i].length > 1 ? state[i][1] : 0.0;
    }
  }

  @override
  String toString() => 'DigitalFilter(${coefficients.type}, order=${coefficients.order})';
}

/// Filter chain for applying multiple filters sequentially
class FilterChain {
  final List<DigitalFilter> filters;

  FilterChain(this.filters);

  /// Apply all filters in sequence to a single sample
  double processSample(double input) {
    var output = input;
    for (final filter in filters) {
      output = filter.processSample(output);
    }
    return output;
  }

  /// Apply all filters to a batch of samples
  List<double> processBatch(List<double> input) {
    var output = input;
    for (final filter in filters) {
      output = filter.processBatch(output);
    }
    return output;
  }

  /// Reset all filters in the chain
  void reset() {
    for (final filter in filters) {
      filter.reset();
    }
  }

  /// Get filter info
  String getInfo() {
    return 'FilterChain(${filters.length} filters: ${filters.map((f) => f.coefficients.type).join(", ")})';
  }
}

/// Offline filter utilities for processing recorded data
/// Supports zero-phase filtering and batch processing
class OfflineFilter {
  /// Apply filter to recorded data
  /// If zeroPhase is true, applies bidirectional filtering (forward then reverse)
  static List<double> apply(
    List<double> data,
    FilterDesign filterDesign, {
    bool zeroPhase = false,
  }) {
    final coefficients = filterDesign.designFilter();
    final filter = DigitalFilter(coefficients);

    if (!zeroPhase) {
      // Simple forward filtering
      return filter.processBatch(data);
    } else {
      // Zero-phase filtering (filtfilt algorithm)
      return _zeroPhaseFilter(data, coefficients);
    }
  }

  /// Apply multiple filters in cascade
  static List<double> applyFilterChain(
    List<double> data,
    List<FilterDesign> filterDesigns, {
    bool zeroPhase = false,
  }) {
    var output = data;

    for (final design in filterDesigns) {
      output = apply(output, design, zeroPhase: zeroPhase);
    }

    return output;
  }

  /// Apply filter with pre-padding to reduce edge artifacts
  static List<double> applyWithPadding(
    List<double> data,
    FilterDesign filterDesign, {
    int padLength = 100,
    bool zeroPhase = false,
  }) {
    if (data.isEmpty) return data;

    // Calculate initial/final conditions based on first/last samples
    final padStart = List<double>.filled(padLength, data.first);
    final padEnd = List<double>.filled(padLength, data.last);

    final paddedData = padStart + data + padEnd;
    final filtered = apply(paddedData, filterDesign, zeroPhase: zeroPhase);

    // Remove padding
    return filtered.sublist(padLength, filtered.length - padLength);
  }

  /// Bidirectional filtering (zero-phase)
  static List<double> _zeroPhaseFilter(
    List<double> data,
    FilterCoefficients coefficients,
  ) {
    // Forward pass
    final filter1 = DigitalFilter(coefficients);
    final forward = filter1.processBatch(data);

    // Reverse data and filter
    final reversed = forward.reversed.toList();
    final filter2 = DigitalFilter(coefficients);
    final backPass = filter2.processBatch(reversed);

    // Reverse result
    return backPass.reversed.toList();
  }

  /// Get filter frequency response magnitude at specific frequencies
  static List<double> getFrequencyResponse(
    FilterDesign filterDesign,
    List<double> frequencies,
  ) {
    final coefficients = filterDesign.designFilter();
    final freqResp = coefficients.evaluateFrequencyResponse(frequencies);
    return freqResp.magnitudes;
  }

  /// Get filter frequency response in dB
  static List<double> getFrequencyResponseDB(
    FilterDesign filterDesign,
    List<double> frequencies,
  ) {
    final coefficients = filterDesign.designFilter();
    final freqResp = coefficients.evaluateFrequencyResponse(frequencies);
    return freqResp.getMagnitudesDB();
  }

  /// Estimate filter delay (group delay at center frequency)
  static double estimateGroupDelay(FilterDesign filterDesign) {
    // Rough estimate: group delay approximately filter_order / (2 * cutoff_frequency)
    final order = filterDesign.order;
    final cutoff = filterDesign.cutoffLow;
    return order / (2 * cutoff);
  }
}

/// Adaptive filter for real-time filtering with dynamic parameters
class AdaptiveFilter {
  late DigitalFilter _currentFilter;
  late FilterDesign _currentDesign;
  final double samplingRate;
  final void Function(FilterDesign)? onDesignChanged;

  AdaptiveFilter({
    required FilterDesign initialDesign,
    required this.samplingRate,
    this.onDesignChanged,
  }) {
    _currentDesign = initialDesign;
    _currentFilter = DigitalFilter(initialDesign.designFilter());
  }

  /// Update filter design (useful for real-time parameter adjustment)
  void updateDesign(FilterDesign newDesign) {
    if (newDesign.validate() != null) {
      throw ArgumentError('Invalid filter design: ${newDesign.validate()}');
    }

    _currentDesign = newDesign;
    _currentFilter = DigitalFilter(newDesign.designFilter());
    onDesignChanged?.call(newDesign);
  }

  /// Process sample with current filter
  double processSample(double input) {
    return _currentFilter.processSample(input);
  }

  /// Process batch with current filter
  List<double> processBatch(List<double> input) {
    return _currentFilter.processBatch(input);
  }

  /// Reset current filter state
  void reset() {
    _currentFilter.reset();
  }

  FilterDesign get currentDesign => _currentDesign;
  DigitalFilter get filter => _currentFilter;
}
