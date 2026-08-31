import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/screens/studio/studio_home.dart';
import 'package:healthypi_studio/shell/studio_nav.dart';
import 'package:healthypi_studio/shell/studio_shell.dart';
import 'package:healthypi_studio/shell/studio_settings.dart';
import 'package:healthypi_studio/theme/app_theme.dart';
import 'package:healthypi_studio/theme/hpi_tokens.dart';
import 'package:provider/provider.dart';

/// The revamp's core invariant: one chrome, and every screen is content inside
/// it. These tests pin the navigation model and the rail that expresses it,
/// without booting the transport services.
void main() {
  group('StudioNavController', () {
    test('starts on Live with no display mode engaged', () {
      final nav = StudioNavController();
      expect(nav.destination, StudioDestination.live);
      expect(nav.focusMode, isFalse);
      expect(nav.dockExpanded, isFalse);
    });

    test('leaving Live drops focus mode, because it only means anything there',
        () {
      final nav = StudioNavController()..setFocusMode(true);
      expect(nav.focusMode, isTrue);

      nav.go(StudioDestination.records);
      expect(nav.focusMode, isFalse);
      expect(nav.destination, StudioDestination.records);
    });

    test('Esc leaves focus mode first, then closes the dock', () {
      final nav = StudioNavController()
        ..setFocusMode(true)
        ..setDockExpanded(true);

      expect(nav.escape(), isTrue);
      expect(nav.focusMode, isFalse);
      expect(nav.dockExpanded, isTrue, reason: 'dock survives the first Esc');

      expect(nav.escape(), isTrue);
      expect(nav.dockExpanded, isFalse);

      expect(nav.escape(), isFalse, reason: 'nothing left to dismiss');
    });

    test('selecting the open tool collapses the dock', () {
      final nav = StudioNavController()..selectTool(InspectorTool.filters);
      expect(nav.dockExpanded, isTrue);
      expect(nav.tool, InspectorTool.filters);

      nav.selectTool(InspectorTool.filters);
      expect(nav.dockExpanded, isFalse);

      nav.selectTool(InspectorTool.recording);
      expect(nav.dockExpanded, isTrue);
      expect(nav.tool, InspectorTool.recording);
    });

    test('Connect can be dismissed for the session and reopened', () {
      final nav = StudioNavController()
        ..go(StudioDestination.device)
        ..dismissConnect();
      expect(nav.connectDismissed, isTrue);

      nav.showConnect();
      expect(nav.connectDismissed, isFalse);
      expect(nav.destination, StudioDestination.live,
          reason: 'Connect is the Live destination\'s empty state');
    });

    test('every destination carries a rail label and a screen title', () {
      for (final d in StudioDestination.values) {
        expect(d.label, isNotEmpty);
        expect(d.title, isNotEmpty);
      }
      // Rail order: six primary destinations above the spacer, two below.
      expect(
        [...StudioDestination.primary, ...StudioDestination.secondary],
        StudioDestination.values,
      );
    });
  });

  group('StudioRail', () {
    Widget harness(StudioNavController nav) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: nav),
              ChangeNotifierProvider(create: (_) => StudioSettings()),
            ],
            child: const Scaffold(body: Row(children: [StudioRail()])),
          ),
        );

    testWidgets('labels every destination', (tester) async {
      await tester.pumpWidget(harness(StudioNavController()));

      for (final d in StudioDestination.values) {
        expect(find.text(d.label.toUpperCase()), findsOneWidget,
            reason: 'rail should label ${d.name}');
      }
    });

    testWidgets('tapping a destination navigates', (tester) async {
      final nav = StudioNavController();
      await tester.pumpWidget(harness(nav));

      await tester.tap(find.text('FILTERS'));
      await tester.pump();

      expect(nav.destination, StudioDestination.filters);
    });

    testWidgets('active destination takes the amber indicator, others do not',
        (tester) async {
      final nav = StudioNavController();
      await tester.pumpWidget(harness(nav));

      final context = tester.element(find.byType(StudioRail));
      final accent = context.hpi.accent;

      Color? indicatorFor(String label) {
        final container = tester.widget<Container>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(Container),
              )
              .first,
        );
        final border = (container.decoration as BoxDecoration?)?.border;
        return border is Border ? border.left.color : null;
      }

      expect(indicatorFor('LIVE'), accent);
      expect(indicatorFor('HRV'), Colors.transparent);
    });

    testWidgets('every item spans the rail, so the indicator is a left EDGE',
        (tester) async {
      await tester.pumpWidget(harness(StudioNavController()));
      final rail = tester.getRect(find.byType(StudioRail));

      for (final d in StudioDestination.values) {
        final item = find
            .ancestor(
              of: find.text(d.label.toUpperCase()),
              matching: find.byType(Container),
            )
            .first;
        final rect = tester.getRect(item);
        // Items used to shrink-wrap their label, which floated the 3px amber
        // edge inward by however long the word was — 5.7px for SETTINGS,
        // 30.9px for HRV — instead of pinning it to the rail edge.
        expect(rect.left, rail.left,
            reason: '${d.name} indicator must sit on the rail edge');
        expect(rect.width, greaterThanOrEqualTo(rail.width - 1),
            reason: '${d.name} must span the rail, wash included');
      }
    });

    testWidgets('icon and label clear the 3px indicator', (tester) async {
      await tester.pumpWidget(harness(StudioNavController()));
      final rail = tester.getRect(find.byType(StudioRail));
      const indicatorRight = 3.0;

      for (final d in StudioDestination.values) {
        final label = find.text(d.label.toUpperCase());
        final item = find
            .ancestor(of: label, matching: find.byType(Container))
            .first;
        final icon =
            find.descendant(of: item, matching: find.byType(Icon)).first;

        for (final (what, rect) in [
          ('icon', tester.getRect(icon)),
          ('label', tester.getRect(label)),
        ]) {
          expect(rect.left - rail.left, greaterThan(indicatorRight),
              reason: '${d.name} $what must not touch the indicator');
        }
      }
    });
  });

  group('Theme', () {
    test('both themes carry the palette so screens never hard-code hex', () {
      expect(AppTheme.darkTheme.extension<HpiPalette>(), HpiPalette.dark);
      expect(AppTheme.lightTheme.extension<HpiPalette>(), HpiPalette.light);
    });

    test('the trace ramp keeps the three ECG leads in one family', () {
      // Amber family for all three leads — that is the point of the ramp.
      for (final c in [
        HpiTraceRamp.dark.ecg1,
        HpiTraceRamp.dark.ecg2,
        HpiTraceRamp.dark.ecg3,
      ]) {
        expect(c.r, greaterThan(c.g), reason: 'warm');
        expect(c.g, greaterThan(c.b), reason: 'amber, not red');
      }
      // And the other modalities are distinct families.
      expect(HpiTraceRamp.dark.respiration, isNot(HpiTraceRamp.dark.ecg1));
      expect(HpiTraceRamp.dark.ppg, isNot(HpiTraceRamp.dark.eeg1));
    });

    test('nothing in the dark ramp is pure black or saturated RGB', () {
      for (final c in [
        HpiPalette.dark.canvas,
        HpiPalette.dark.chrome,
        HpiPalette.dark.cardInner,
        HpiPalette.dark.well,
      ]) {
        expect(c.r + c.g + c.b, greaterThan(0), reason: 'not pure black');
      }
    });

    test('channel colours resolve by channel id', () {
      const ramp = HpiTraceRamp.dark;
      expect(ramp.forChannel('ecg1'), ramp.ecg1);
      expect(ramp.forChannel('respiration'), ramp.respiration);
      expect(ramp.forChannel('eeg2'), ramp.eeg2);
      expect(ramp.forChannel('unknown-channel'), ramp.ppg,
          reason: 'unknown channels fall back rather than throwing');
    });
  });

  group('Global shortcuts', () {
    /// The shell binds bare letters and digits — `R` records, `M` marks, digits
    /// jump destinations. Flutter hands those key events to ancestor handlers
    /// even while a text field has the caret, so without a guard, typing a WiFi
    /// host or a subject name fires them mid-word.
    Future<List<String>> typeInto(WidgetTester tester,
        {required bool intoTextField}) async {
      final seen = <String>[];
      final field = FocusNode();
      addTearDown(field.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (textEntryHasFocus()) return KeyEventResult.ignored;
            seen.add(event.logicalKey.keyLabel);
            return KeyEventResult.handled;
          },
          child: Material(child: TextField(focusNode: field)),
        ),
      ));

      if (intoTextField) {
        field.requestFocus();
        await tester.pump();
      }
      for (final key in [
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.digit5,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      return seen;
    }

    testWidgets('stand down while a text field has the caret', (tester) async {
      expect(await typeInto(tester, intoTextField: true), isEmpty);
    });

    testWidgets('still fire when no text field is focused', (tester) async {
      expect(await typeInto(tester, intoTextField: false), hasLength(5));
    });
  });
}
