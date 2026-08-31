import '../models/filter_models.dart';

/// Filter preset with predefined configurations
class FilterPreset {
  final String name;
  final String description;
  final List<FilterDesign> filters;
  final bool isCustom;
  final String? category; // ECG, EMG, EEG, etc

  const FilterPreset({
    required this.name,
    required this.description,
    required this.filters,
    this.isCustom = false,
    this.category,
  });

  FilterPreset copyWith({
    String? name,
    String? description,
    List<FilterDesign>? filters,
    bool? isCustom,
    String? category,
  }) {
    return FilterPreset(
      name: name ?? this.name,
      description: description ?? this.description,
      filters: filters ?? this.filters,
      isCustom: isCustom ?? this.isCustom,
      category: category ?? this.category,
    );
  }

  @override
  String toString() => 'FilterPreset($name, ${filters.length} filters)';
}

/// Manages built-in and custom filter presets
class FilterPresetManager {
  /// Default built-in presets for common biosignals
  static final List<FilterPreset> defaultPresets = [
    // ECG presets
    FilterPreset(
      name: 'ECG Cleanup',
      description: 'Remove DC drift and high-frequency noise',
      category: 'ECG',
      filters: [
        // High-pass to remove DC and slow drift (0.5 Hz cutoff)
        FilterDesign(
          type: FilterType.highpass,
          cutoffLow: 0.5,
          order: 4,
          samplingRate: 500,
        ),
        // Low-pass to remove high-frequency noise (40 Hz)
        FilterDesign(
          type: FilterType.lowpass,
          cutoffLow: 40,
          order: 4,
          samplingRate: 500,
        ),
        // Notch filter for 50 Hz powerline
        FilterDesign(
          type: FilterType.notch,
          cutoffLow: 50,
          order: 4,
          samplingRate: 500,
          qFactor: 30,
        ),
      ],
    ),
    FilterPreset(
      name: 'ECG Standard (0.5-40 Hz)',
      description: 'Standard ECG bandpass filtering',
      category: 'ECG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.5,
          cutoffHigh: 40,
          order: 4,
          samplingRate: 500,
        ),
      ],
    ),
    FilterPreset(
      name: 'ECG with 60 Hz Notch',
      description: 'ECG filtering for 60 Hz powerline regions',
      category: 'ECG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.5,
          cutoffHigh: 40,
          order: 4,
          samplingRate: 500,
        ),
        FilterDesign(
          type: FilterType.notch,
          cutoffLow: 60,
          order: 4,
          samplingRate: 500,
          qFactor: 30,
        ),
      ],
    ),

    // EMG presets
    FilterPreset(
      name: 'EMG Noise Reduction',
      description: 'Remove DC drift and high-frequency noise from EMG',
      category: 'EMG',
      filters: [
        // High-pass to remove DC (0.5 Hz)
        FilterDesign(
          type: FilterType.highpass,
          cutoffLow: 0.5,
          order: 4,
          samplingRate: 2000,
        ),
        // Bandpass filter typical EMG range (20-500 Hz)
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 20,
          cutoffHigh: 500,
          order: 4,
          samplingRate: 2000,
        ),
      ],
    ),
    FilterPreset(
      name: 'EMG Narrowband (20-450 Hz)',
      description: 'Standard EMG bandpass filtering',
      category: 'EMG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 20,
          cutoffHigh: 450,
          order: 4,
          samplingRate: 2000,
        ),
      ],
    ),

    // EEG presets
    FilterPreset(
      name: 'EEG Standard',
      description: 'Standard EEG bandpass filtering (0.5-50 Hz)',
      category: 'EEG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.5,
          cutoffHigh: 50,
          order: 4,
          samplingRate: 250,
        ),
      ],
    ),
    FilterPreset(
      name: 'EEG with Notch',
      description: 'EEG with powerline interference removal',
      category: 'EEG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.5,
          cutoffHigh: 50,
          order: 4,
          samplingRate: 250,
        ),
        FilterDesign(
          type: FilterType.notch,
          cutoffLow: 50,
          order: 4,
          samplingRate: 250,
          qFactor: 25,
        ),
      ],
    ),
    FilterPreset(
      name: 'Alpha Band (8-12 Hz)',
      description: 'Isolate alpha band for EEG analysis',
      category: 'EEG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 8,
          cutoffHigh: 12,
          order: 4,
          samplingRate: 250,
        ),
      ],
    ),
    FilterPreset(
      name: 'Beta Band (12-30 Hz)',
      description: 'Isolate beta band for EEG analysis',
      category: 'EEG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 12,
          cutoffHigh: 30,
          order: 4,
          samplingRate: 250,
        ),
      ],
    ),

    // General purpose presets
    FilterPreset(
      name: 'High-Pass Only (0.1 Hz)',
      description: 'Remove DC and very low-frequency drift',
      category: 'General',
      filters: [
        FilterDesign(
          type: FilterType.highpass,
          cutoffLow: 0.1,
          order: 4,
          samplingRate: 500,
        ),
      ],
    ),
    FilterPreset(
      name: 'Low-Pass Only (50 Hz)',
      description: 'Remove high-frequency noise',
      category: 'General',
      filters: [
        FilterDesign(
          type: FilterType.lowpass,
          cutoffLow: 50,
          order: 4,
          samplingRate: 500,
        ),
      ],
    ),

    // ECG Diagnostic - wider bandwidth for detailed morphology
    FilterPreset(
      name: 'ECG Diagnostic (0.05-150 Hz)',
      description: 'Wide bandwidth ECG for diagnostic purposes',
      category: 'ECG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.05,
          cutoffHigh: 150,
          order: 4,
          samplingRate: 500,
        ),
      ],
    ),

    // PPG presets
    FilterPreset(
      name: 'PPG Standard (0.5-8 Hz)',
      description: 'Standard PPG filtering for pulse wave',
      category: 'PPG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.5,
          cutoffHigh: 8,
          order: 4,
          samplingRate: 125,
        ),
      ],
    ),

    // Respiration presets
    FilterPreset(
      name: 'Respiration (0.1-1 Hz)',
      description: 'Respiration signal filtering (6-60 breaths/min)',
      category: 'Respiration',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.1,
          cutoffHigh: 1.0,
          order: 4,
          samplingRate: 500,
        ),
      ],
    ),

    // EMG Standard (alias for EMG Narrowband)
    FilterPreset(
      name: 'EMG Standard (20-450 Hz)',
      description: 'Standard EMG bandpass filtering',
      category: 'EMG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 20,
          cutoffHigh: 450,
          order: 4,
          samplingRate: 2000,
        ),
      ],
    ),

    // EEG Standard with explicit frequency range in name
    FilterPreset(
      name: 'EEG Standard (0.5-50 Hz)',
      description: 'Standard EEG bandpass filtering',
      category: 'EEG',
      filters: [
        FilterDesign(
          type: FilterType.bandpass,
          cutoffLow: 0.5,
          cutoffHigh: 50,
          order: 4,
          samplingRate: 250,
        ),
      ],
    ),

    // Notch filters
    FilterPreset(
      name: 'Notch 50 Hz',
      description: 'Remove 50 Hz powerline interference',
      category: 'Notch',
      filters: [
        FilterDesign(
          type: FilterType.notch,
          cutoffLow: 50,
          order: 4,
          samplingRate: 500,
          qFactor: 30,
        ),
      ],
    ),
    FilterPreset(
      name: 'Notch 60 Hz',
      description: 'Remove 60 Hz powerline interference',
      category: 'Notch',
      filters: [
        FilterDesign(
          type: FilterType.notch,
          cutoffLow: 60,
          order: 4,
          samplingRate: 500,
          qFactor: 30,
        ),
      ],
    ),
  ];

  /// Get all available presets (built-in + custom)
  static List<FilterPreset> getAllPresets() {
    return [...defaultPresets];
  }

  /// Get presets by category
  static List<FilterPreset> getPresetsByCategory(String category) {
    return defaultPresets.where((p) => p.category == category).toList();
  }

  /// Get unique categories
  static List<String> getCategories() {
    final categories = <String>{};
    for (final preset in defaultPresets) {
      if (preset.category != null) {
        categories.add(preset.category!);
      }
    }
    return categories.toList();
  }

  /// Find preset by name
  static FilterPreset? findPreset(String name) {
    try {
      return defaultPresets.firstWhere((p) => p.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Create a custom single-filter preset
  static FilterPreset createCustomPreset({
    required String name,
    required FilterDesign filter,
    String? description,
  }) {
    return FilterPreset(
      name: name,
      description: description ?? 'Custom filter preset',
      filters: [filter],
      isCustom: true,
    );
  }

  /// Create a custom multi-filter preset
  static FilterPreset createCustomChainPreset({
    required String name,
    required List<FilterDesign> filters,
    String? description,
  }) {
    return FilterPreset(
      name: name,
      description: description ?? 'Custom filter chain',
      filters: filters,
      isCustom: true,
    );
  }

  /// Get preset information string
  static String getPresetInfo(FilterPreset preset) {
    final buffer = StringBuffer();
    buffer.writeln('Preset: ${preset.name}');
    buffer.writeln('Description: ${preset.description}');
    buffer.writeln('Filters: ${preset.filters.length}');
    for (int i = 0; i < preset.filters.length; i++) {
      final f = preset.filters[i];
      buffer.writeln(
          '  ${i + 1}. ${f.type.name} @ ${f.samplingRate} Hz (order ${f.order})');
      if (f.type == FilterType.highpass || f.type == FilterType.lowpass) {
        buffer.writeln('     Cutoff: ${f.cutoffLow} Hz');
      } else if (f.type == FilterType.bandpass) {
        buffer.writeln('     Band: ${f.cutoffLow}-${f.cutoffHigh} Hz');
      } else if (f.type == FilterType.notch) {
        buffer.writeln('     Notch: ${f.cutoffLow} Hz (Q=${f.qFactor ?? 30})');
      }
    }
    return buffer.toString();
  }
}
