/// `.HP6` DBLK wire constants: channel ids, payload sizes and flag bits.
///
/// Generated from the firmware host tool's `healthypi catalog --formats`
/// (see tool/gen_protocol.dart). Field offsets within each struct are decoded
/// by hand in DataParser; the generated sizes make a layout change surface as
/// rejected blocks rather than misread fields.
library;

export 'hp6_formats.g.dart';
