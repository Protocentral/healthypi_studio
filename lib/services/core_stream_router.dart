import 'dart:typed_data';

import 'package:mcumgr_dart/mcumgr_dart.dart';

import '../protocol/hpi_command.dart';
import '../protocol/hpi_core.dart';

/// Pulls the DBLK block out of each HealthyPi Core stream notification and
/// hands it to the same parse entry point the HealthyPi 6's CDC0 bytes go to
/// (`DataParser.parseBinaryData`), so plotting, `.hpd` recording and the gap
/// and drop counters work unchanged.
///
/// The Core has one CDC port. Its samples arrive as unsolicited SMP frames on
/// the control link (op 3, group 64, id 0xC0, `{"b": <DBLK block>}`), which
/// `SmpClient.unsolicited` delivers. Anything else on that stream (a late reply
/// after a timeout, say) is counted and ignored, never parsed as samples.
class CoreStreamRouter {
  CoreStreamRouter(this.sink);

  /// Where each block's bytes go — `DataParser.parseBinaryData`.
  final void Function(List<int> bytes) sink;

  /// Stream notifications routed to [sink].
  int get blocks => _blocks;
  int _blocks = 0;

  /// Unsolicited frames that were not stream notifications.
  int get ignored => _ignored;
  int _ignored = 0;

  /// Stream notifications with no byte string under `b`.
  int get malformed => _malformed;
  int _malformed = 0;

  /// Whether [m] is a Core stream notification.
  static bool isStreamFrame(SmpMessage m) =>
      m.op == SmpOp.writeRsp &&
      m.group == hpiGroupId &&
      m.id == HpiCore.streamData;

  /// Route one unsolicited frame. Returns true if it carried a block.
  bool add(SmpMessage m) {
    if (!isStreamFrame(m)) {
      _ignored++;
      return false;
    }
    final Uint8List? block = hpiBytes(m.payload[HpiCore.streamDataKey]);
    if (block == null || block.isEmpty) {
      _malformed++;
      return false;
    }
    _blocks++;
    sink(block);
    return true;
  }

  void reset() {
    _blocks = 0;
    _ignored = 0;
    _malformed = 0;
  }
}
