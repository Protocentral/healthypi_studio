import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fftea/fftea.dart';
import '../models/eeg_models.dart';

/// Service for computing EEG frequency band powers using FFT
///
/// Processes raw EEG samples to extract power in standard frequency bands:
/// - Delta (0.5-4 Hz): Deep sleep
/// - Theta (4-8 Hz): Drowsiness, meditation
/// - Alpha (8-13 Hz): Relaxed wakefulness
/// - Beta (13-30 Hz): Active thinking
/// - Gamma (30-50 Hz): High cognition
class EegBandPowerService {
  /// Default FFT size (must be power of 2)
  static const int defaultFftSize = 256;

  /// EEG sampling rate in Hz
  static const double samplingRate = 250.0;

  /// Cached FFT instance for performance
  FFT? _fft;
  int _currentFftSize = 0;

  /// Cached Hanning window coefficients
  Float64List? _window;

  /// Get or create FFT instance
  FFT _getFFT(int size) {
    if (_fft == null || _currentFftSize != size) {
      _fft = FFT(size);
      _currentFftSize = size;
      _window = _createHanningWindow(size);
    }
    return _fft!;
  }

  /// Create Hanning window coefficients
  Float64List _createHanningWindow(int size) {
    final window = Float64List(size);
    for (int i = 0; i < size; i++) {
      window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (size - 1)));
    }
    return window;
  }

  /// Apply Hanning window to samples
  Float64List _applyWindow(List<double> samples) {
    final window = _window!;
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] * window[i];
    }
    return result;
  }

  /// Compute band powers for a single channel
  ///
  /// [samples] - Raw EEG samples (should be fftSize samples)
  /// [fftSize] - FFT size (default 256, must be power of 2)
  /// [channelIndex] - Channel index for tracking (default -1 for unspecified)
  EegBandPowers computeBandPowers(
    List<double> samples, {
    int fftSize = defaultFftSize,
    int channelIndex = -1,
  }) {
    if (samples.isEmpty) {
      return EegBandPowers.empty();
    }

    // Ensure we have exactly fftSize samples
    List<double> data;
    if (samples.length >= fftSize) {
      // Take most recent fftSize samples
      data = samples.sublist(samples.length - fftSize);
    } else {
      // Zero-pad if insufficient samples
      data = List<double>.filled(fftSize, 0.0);
      for (int i = 0; i < samples.length; i++) {
        data[i] = samples[i];
      }
    }

    // Get FFT instance and apply window
    final fft = _getFFT(fftSize);
    final windowed = _applyWindow(data);

    // Compute FFT - returns Float64x2List (complex numbers)
    final spectrum = fft.realFft(windowed);

    // Compute power spectrum using fftea's built-in methods
    // discardConjugates() removes redundant conjugate frequencies
    // magnitudes() computes sqrt(real^2 + imag^2) for each bin
    final magnitudes = spectrum.discardConjugates().magnitudes();
    final powerSpectrum = _computePowerFromMagnitudes(magnitudes, fftSize);

    // Frequency resolution: samplingRate / fftSize
    final freqResolution = samplingRate / fftSize;

    // Sum power in each frequency band
    final delta = _sumBandPower(powerSpectrum, 0.5, 4.0, freqResolution);
    final theta = _sumBandPower(powerSpectrum, 4.0, 8.0, freqResolution);
    final alpha = _sumBandPower(powerSpectrum, 8.0, 13.0, freqResolution);
    final beta = _sumBandPower(powerSpectrum, 13.0, 30.0, freqResolution);
    final gamma = _sumBandPower(powerSpectrum, 30.0, 50.0, freqResolution);

    return EegBandPowers(
      delta: delta,
      theta: theta,
      alpha: alpha,
      beta: beta,
      gamma: gamma,
      timestamp: DateTime.now(),
      channelIndex: channelIndex,
    );
  }

  /// Compute power spectrum from magnitudes
  ///
  /// Converts magnitude values to power (magnitude squared) and normalizes
  Float64List _computePowerFromMagnitudes(Float64List magnitudes, int fftSize) {
    final power = Float64List(magnitudes.length);

    // Power = magnitude^2, normalized by FFT size
    final scale = 2.0 / (fftSize * fftSize);
    for (int i = 0; i < magnitudes.length; i++) {
      power[i] = magnitudes[i] * magnitudes[i] * scale;
    }

    // DC component should not be doubled
    if (power.isNotEmpty) {
      power[0] /= 2.0;
    }

    return power;
  }

  /// Sum power in a frequency band
  double _sumBandPower(
    Float64List powerSpectrum,
    double fLow,
    double fHigh,
    double freqResolution,
  ) {
    final binLow = (fLow / freqResolution).floor();
    final binHigh = (fHigh / freqResolution).ceil();

    double sum = 0;
    for (int i = binLow; i <= binHigh && i < powerSpectrum.length; i++) {
      sum += powerSpectrum[i];
    }
    return sum;
  }

  /// Compute band powers for all 8 channels from ring buffer
  ///
  /// [buffer] - EEG ring buffer containing samples
  /// [fftSize] - FFT size (default 256)
  EegAllChannelsBandPowers computeAllChannelsBandPowers(
    EegRingBuffer buffer, {
    int fftSize = defaultFftSize,
  }) {
    final channelPowers = <EegBandPowers>[];

    for (int ch = 0; ch < EegRingBuffer.channelCount; ch++) {
      final samples = buffer.getChannelForFft(ch, fftSize);
      final powers = computeBandPowers(
        samples,
        fftSize: fftSize,
        channelIndex: ch,
      );
      channelPowers.add(powers);
    }

    return EegAllChannelsBandPowers.fromChannels(channelPowers);
  }

  /// Compute band powers for specific channels only
  ///
  /// [buffer] - EEG ring buffer
  /// [channelIndices] - List of channel indices to compute (0-7)
  /// [fftSize] - FFT size
  List<EegBandPowers> computeSelectedChannelsBandPowers(
    EegRingBuffer buffer,
    List<int> channelIndices, {
    int fftSize = defaultFftSize,
  }) {
    return channelIndices.map((ch) {
      final samples = buffer.getChannelForFft(ch, fftSize);
      return computeBandPowers(samples, fftSize: fftSize, channelIndex: ch);
    }).toList();
  }

  /// Get frequency bin for a given frequency
  int frequencyToBin(double frequency, int fftSize) {
    return (frequency * fftSize / samplingRate).round();
  }

  /// Get frequency for a given bin
  double binToFrequency(int bin, int fftSize) {
    return bin * samplingRate / fftSize;
  }

  /// Get the full power spectrum for visualization
  ///
  /// Returns list of (frequency, power) pairs up to Nyquist frequency
  List<MapEntry<double, double>> getFullPowerSpectrum(
    List<double> samples, {
    int fftSize = defaultFftSize,
  }) {
    if (samples.isEmpty) return [];

    List<double> data;
    if (samples.length >= fftSize) {
      data = samples.sublist(samples.length - fftSize);
    } else {
      data = List<double>.filled(fftSize, 0.0);
      for (int i = 0; i < samples.length; i++) {
        data[i] = samples[i];
      }
    }

    final fft = _getFFT(fftSize);
    final windowed = _applyWindow(data);
    final spectrum = fft.realFft(windowed);
    final magnitudes = spectrum.discardConjugates().magnitudes();
    final powerSpectrum = _computePowerFromMagnitudes(magnitudes, fftSize);

    final freqResolution = samplingRate / fftSize;
    final result = <MapEntry<double, double>>[];

    for (int i = 0; i < powerSpectrum.length; i++) {
      final freq = i * freqResolution;
      if (freq > samplingRate / 2) break; // Stop at Nyquist
      result.add(MapEntry(freq, powerSpectrum[i]));
    }

    return result;
  }
}
