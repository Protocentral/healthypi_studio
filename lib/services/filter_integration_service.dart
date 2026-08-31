import 'package:flutter/foundation.dart';
import '../models/filter_models.dart';
import '../services/digital_filter.dart';
import '../controllers/channel_controller.dart';

/// Filter integration service for the recording pipeline
/// Handles applying filters to real-time data streams
class FilterIntegrationService {
  /// Active filters per channel
  final Map<String, DigitalFilter?> _activeFilters = {};

  /// Filter designs per channel
  final Map<String, FilterDesign?> _filterDesigns = {};

  /// Whether filtering is enabled
  bool _filteringEnabled = false;

  /// Constructor
  FilterIntegrationService({
    bool filteringEnabled = false,
  }) : _filteringEnabled = filteringEnabled;

  // ============= GETTERS =============

  /// Check if filtering is enabled
  bool get isFilteringEnabled => _filteringEnabled;

  /// Get active filter for channel
  DigitalFilter? getActiveFilter(String channelId) => _activeFilters[channelId];

  /// Get filter design for channel
  FilterDesign? getFilterDesign(String channelId) => _filterDesigns[channelId];

  /// Check if channel has active filter
  bool hasActiveFilter(String channelId) => _activeFilters[channelId] != null;

  // ============= FILTER MANAGEMENT =============

  /// Enable/disable filtering
  void setFilteringEnabled(bool enabled) {
    _filteringEnabled = enabled;
  }

  /// Apply filter to a channel
  void applyFilterToChannel(String channelId, FilterDesign filterDesign) {
    try {
      // Validate filter design first
      final validationError = filterDesign.validate();
      if (validationError != null) {
        debugPrint('❌ Filter validation failed for $channelId: $validationError');
        debugPrint('   Filter: ${filterDesign.type}, cutoff=${filterDesign.cutoffLow}, order=${filterDesign.order}, fs=${filterDesign.samplingRate}');
        return;
      }

      final coefficients = filterDesign.designFilter();

      // Debug: Print filter coefficients
      debugPrint('📊 Filter coefficients for $channelId:');
      debugPrint('   Type: ${coefficients.type}, Order: ${coefficients.order}');
      debugPrint('   Gain: ${coefficients.gain}');
      debugPrint('   Sections: ${coefficients.numSections}');
      for (int i = 0; i < coefficients.sos.length; i++) {
        final s = coefficients.sos[i];
        debugPrint('   SOS[$i]: b=[${s[0].toStringAsFixed(6)}, ${s[1].toStringAsFixed(6)}, ${s[2].toStringAsFixed(6)}] a=[${s[3].toStringAsFixed(6)}, ${s[4].toStringAsFixed(6)}, ${s[5].toStringAsFixed(6)}]');
      }

      // Check for invalid coefficients
      bool hasInvalidCoeffs = false;
      for (final section in coefficients.sos) {
        for (final coeff in section) {
          if (coeff.isNaN || coeff.isInfinite || coeff.abs() > 1e10) {
            hasInvalidCoeffs = true;
            break;
          }
        }
      }
      if (coefficients.gain.isNaN || coefficients.gain.isInfinite || coefficients.gain.abs() > 1e10) {
        hasInvalidCoeffs = true;
      }

      if (hasInvalidCoeffs) {
        debugPrint('❌ Filter has invalid coefficients (NaN/Inf/too large) - not applying');
        return;
      }

      final filter = DigitalFilter(coefficients);
      _activeFilters[channelId] = filter;
      _filterDesigns[channelId] = filterDesign;
      debugPrint('✅ Filter applied to $channelId: ${filterDesign.type} @ ${filterDesign.cutoffLow} Hz');
    } catch (e, stackTrace) {
      debugPrint('❌ Error applying filter to $channelId: $e');
      debugPrint('   Filter: ${filterDesign.type}, cutoff=${filterDesign.cutoffLow}, order=${filterDesign.order}, fs=${filterDesign.samplingRate}');
      debugPrint('   Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
    }
  }

  /// Remove filter from a channel
  void removeFilterFromChannel(String channelId) {
    _activeFilters[channelId] = null;
    _filterDesigns[channelId] = null;
  }

  /// Clear all filters
  void clearAllFilters() {
    _activeFilters.clear();
    _filterDesigns.clear();
  }

  /// Apply filter to all channels with same design
  void applyFilterToAllChannels(FilterDesign filterDesign) {
    for (final key in _activeFilters.keys) {
      applyFilterToChannel(key, filterDesign);
    }
  }

  // ============= SAMPLE PROCESSING =============

  /// Process a sample through the filter chain
  double processSample(String channelId, double sample) {
    if (!_filteringEnabled) return sample;

    final filter = _activeFilters[channelId];
    if (filter == null) return sample;

    try {
      final result = filter.processSample(sample);
      // Check for filter instability (NaN/Infinity)
      if (result.isNaN || result.isInfinite) {
        // Reset filter state to recover from instability
        filter.reset();
        return sample; // Pass through unfiltered
      }
      return result;
    } catch (e) {
      debugPrint('⚠️ Filter error on $channelId: $e');
      return sample; // Pass through unfiltered on error
    }
  }

  /// Process multiple samples
  List<double> processSamples(String channelId, List<double> samples) {
    if (!_filteringEnabled) return samples;

    final filter = _activeFilters[channelId];
    if (filter == null) return samples;

    return samples.map((s) => filter.processSample(s)).toList();
  }

  /// Process batch of samples offline (with optional zero-phase)
  List<double> processBatch(
    String channelId,
    List<double> samples, {
    bool zeroPhase = false,
  }) {
    final design = _filterDesigns[channelId];
    if (design == null) return samples;

    return OfflineFilter.apply(samples, design, zeroPhase: zeroPhase);
  }

  // ============= FILTER INFO =============

  /// Get filter information string for display
  String getFilterInfo(String channelId) {
    final design = _filterDesigns[channelId];
    if (design == null) return 'No filter';

    final high = design.cutoffHigh != null
        ? ' - ${design.cutoffHigh!.toStringAsFixed(2)}'
        : '';
    return '${design.type.name.toUpperCase()} @'
        ' ${design.cutoffLow.toStringAsFixed(2)}$high Hz (Order ${design.order})';
  }

  /// Get all active filters info
  Map<String, String> getAllFiltersInfo() {
    final info = <String, String>{};
    for (final entry in _filterDesigns.entries) {
      info[entry.key] = getFilterInfo(entry.key);
    }
    return info;
  }

  // ============= RESET =============

  /// Reset service (clear all data)
  void reset() {
    _activeFilters.clear();
    _filterDesigns.clear();
    _filteringEnabled = false;
  }
}

/// Extension for ChannelController to add filter support
extension FilterSupport on ChannelController {
  /// Global filter service (shared across controller)
  static final FilterIntegrationService _filterService =
      FilterIntegrationService();

  /// Get filter service
  FilterIntegrationService get filterService => _filterService;
}

/// Bridge class to handle filtered data flow
class FilteredDataBridge {
  final FilterIntegrationService filterService;
  final ChannelController channelController;

  FilteredDataBridge({
    required this.filterService,
    required this.channelController,
  });

  /// Add filtered data point to channel
  void addFilteredDataPoint(String channelId, double value) {
    filterService.setFilteringEnabled(true);
    final filteredValue = filterService.processSample(channelId, value);
    channelController.addDataPoint(channelId, filteredValue);
  }

  /// Add filtered data points (synchronized)
  void addFilteredDataPointsSync(Map<String, double> channelValues) {
    if (!filterService.isFilteringEnabled) {
      channelController.addDataPointsSync(channelValues);
      return;
    }

    final filteredValues = <String, double>{};
    for (final entry in channelValues.entries) {
      filteredValues[entry.key] =
          filterService.processSample(entry.key, entry.value);
    }
    channelController.addDataPointsSync(filteredValues);
  }

  /// Get filter status for channel
  String getFilterStatus(String channelId) {
    if (!filterService.hasActiveFilter(channelId)) {
      return 'No filter';
    }
    return filterService.getFilterInfo(channelId);
  }

  /// Apply filter to channel
  void applyFilter(String channelId, FilterDesign design) {
    filterService.applyFilterToChannel(channelId, design);
  }

  /// Remove filter from channel
  void removeFilter(String channelId) {
    filterService.removeFilterFromChannel(channelId);
  }

  /// Enable/disable all filtering
  void setFilteringEnabled(bool enabled) {
    filterService.setFilteringEnabled(enabled);
  }

  /// Clear all filters
  void clearAllFilters() {
    filterService.clearAllFilters();
  }
}
