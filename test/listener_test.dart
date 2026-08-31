import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/data_parser.dart';

void main() {
  group('DataParser Listener Test', () {
    late DataParser dataParser;
    late int notifyCount;

    // Each test installs its own listeners. The previous version added one in
    // setUp, never reset the counter between tests, and "removed" a listener by
    // passing a fresh closure — which removes nothing, since ChangeNotifier
    // matches listeners by identity.
    setUp(() {
      dataParser = DataParser();
      notifyCount = 0;
    });

    tearDown(() {
      dataParser.dispose();
    });

    test('DataParser notifyListeners triggers listener', () {
      dataParser.addListener(() => notifyCount++);

      expect(notifyCount, equals(0));

      dataParser.notifyListeners();
      expect(notifyCount, equals(1));

      dataParser.notifyListeners();
      expect(notifyCount, equals(2));
    });

    test('Listener can be removed', () {
      void callback() => notifyCount++;

      dataParser.addListener(callback);
      dataParser.notifyListeners();
      expect(notifyCount, equals(1));

      dataParser.removeListener(callback);
      dataParser.notifyListeners();
      expect(notifyCount, equals(1)); // unchanged — the listener is gone
    });
  });
}
