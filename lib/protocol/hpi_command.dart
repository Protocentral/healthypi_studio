import 'dart:typed_data';

/// Hand-written support for the generated group-64 surface
/// (`hpi_group64.g.dart`). Nothing in here restates the protocol; the command
/// table, field names and error codes all come from the generated file.

/// MCUmgr management group of the HealthyPi control surface.
const int hpiGroupId = 64;

/// Whether the firmware actually implements a command. A `stub` is routed but
/// answers ENOTSUP; an `unreachable` id is declared in the header only.
enum HpiStatus { live, stub, unreachable }

/// One group-64 command, as described by the firmware's catalog.
class HpiCommand {
  const HpiCommand(
    this.id,
    this.name, {
    this.read = false,
    this.write = false,
    this.status = HpiStatus.live,
    this.unlock = false,
    this.signedBuild = false,
    this.errors = const [],
  });

  final int id;
  final String name;

  /// Supports the SMP read op.
  final bool read;

  /// Supports the SMP write op.
  final bool write;
  final HpiStatus status;

  /// Rejected while the device is locked.
  final bool unlock;

  /// Only present in signed firmware builds.
  final bool signedBuild;

  /// Group-64 error codes this command documents.
  final List<int> errors;

  @override
  String toString() => '$name (0x${id.toRadixString(16).padLeft(4, '0')})';
}

/// A named error code with the catalog's hint for the user.
class HpiErrorCode {
  const HpiErrorCode(this.code, this.name, this.hint);

  final int code;
  final String name;
  final String hint;

  @override
  String toString() => '$name ($code)';
}

// Reply-field readers. Replies are CBOR maps decoded by mcumgr_dart; a field
// the device left out, or sent with an unexpected type, reads as null rather
// than throwing, so a newer firmware adding or retyping a key never crashes a
// reply parse.

int? hpiInt(Object? v) => v is int ? v : null;

bool? hpiBool(Object? v) => v is bool ? v : null;

String? hpiStr(Object? v) => v is String ? v : null;

Uint8List? hpiBytes(Object? v) {
  if (v is Uint8List) return v;
  if (v is List<int>) return Uint8List.fromList(v);
  return null;
}

Map<Object?, Object?>? hpiMap(Object? v) => v is Map ? v : null;
