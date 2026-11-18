import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyrsheets/engine/formula_engine.dart';
import 'package:fyrsheets/engine/sheet_io.dart';
import 'package:fyrsheets/main.dart';
import 'package:fyrsheets/models/sheet_models.dart';
import 'package:fyrsheets/state/sheets_controller.dart';

void main() {
  group('fyrSheets FormulaEngine & CellCoordinate', () {
    test('parses and formats A1 cell coordinates and ranges', () {
      expect(CellCoordinate.parse('A1'), const CellCoordinate(0, 0));
      expect(CellCoordinate.parse(r'$B$12'), const CellCoordinate(11, 1));
      expect(CellCoordinate.parse('AA1').col, 26);
      expect(const CellCoordinate(0, 26).a1, 'AA1');

      final range = CellCoordinate.expandRange('A1:B3');
      expect(range.length, 6);
      expect(range.first.a1, 'A1');
      expect(range.last.a1, 'B3');
    });

    test('evaluates arithmetic, SUM, AVERAGE, MIN, MAX, COUNT, IF, ROUND', () {
      final sheet = Worksheet(id: 's1', name: 'Test');
      sheet.setCell(0, 0, const SheetCell(rawInput: '10')); // A1
      sheet.setCell(1, 0, const SheetCell(rawInput: '20')); // A2
      sheet.setCell(2, 0, const SheetCell(rawInput: '30')); // A3
      sheet.setCell(3, 0, const SheetCell(rawInput: '=SUM(A1:A3)')); // A4 = 60
      sheet.setCell(
        4,
        0,
        const SheetCell(rawInput: '=AVERAGE(A1:A3)'),
      ); // A5 = 20
      sheet.setCell(
        5,
        0,
        const SheetCell(rawInput: '=IF(A4>50,"Over","Under")'),
      ); // A6 = Over
      sheet.setCell(
        6,
        0,
        const SheetCell(rawInput: '=ROUND(A4/7, 2)'),
      ); // A7 = 8.57
      sheet.setCell(
        7,
        0,
        const SheetCell(rawInput: '=MIN(A1:A3)+MAX(A1:A3)*COUNT(A1:A3)'),
      ); // A8 = 10 + 30*3 = 100

      FormulaEngine.recalculateWorksheet(sheet);

      expect(sheet.getCellByA1('A4').computedValue, closeTo(60.0, 1e-6));
      expect(sheet.getCellByA1('A5').computedValue, closeTo(20.0, 1e-6));
      expect(sheet.getCellByA1('A6').computedValue, 'Over');
      expect(sheet.getCellByA1('A7').computedValue, closeTo(8.57, 1e-6));
      expect(sheet.getCellByA1('A8').computedValue, closeTo(100.0, 1e-6));
    });

    test('detects circular references (#CIRC!) and division by zero (#DIV/0!)',
        () {
      final sheet = Worksheet(id: 's_err', name: 'Errors');
      sheet.setCell(0, 0, const SheetCell(rawInput: '=B1+1')); // A1 -> B1
      sheet.setCell(0, 1, const SheetCell(rawInput: '=A1+1')); // B1 -> A1
      sheet.setCell(1, 0, const SheetCell(rawInput: '=100/0')); // A2 -> #DIV/0!

      FormulaEngine.recalculateWorksheet(sheet);

      expect(sheet.getCellByA1('A1').computedValue, '#CIRC!');
      expect(sheet.getCellByA1('B1').computedValue, '#CIRC!');
      expect(sheet.getCellByA1('A2').computedValue, '#DIV/0!');
    });
  });

  group('fyrSheets .ods, .xlsx, and .csv Round-Trip I/O', () {
    test('encodes and decodes OpenDocument Spreadsheet (.ods) round-trip', () {
      final wb = SheetsController.buildDefaultWorkbook();
      final odsBytes = SheetIO.encodeOdsBytes(wb);
      expect(odsBytes.isNotEmpty, isTrue);

      final decoded = SheetIO.decodeOdsBytes(odsBytes, title: wb.title);
      expect(decoded.sheets.length, 3);
      expect(decoded.sheets[0].name, 'Infrastructure Cost');
      expect(
        decoded.sheets[0].getCellByA1('A2').displayValue,
        'GPU Inference Nodes',
      );
      expect(decoded.sheets[0].getCellByA1('E8').rawInput, '=SUM(E2:E7)');
      expect(
        decoded.sheets[0].getCellByA1('E8').computedValue,
        closeTo(28920.0, 1e-3),
      );
    });

    test('encodes and decodes Microsoft Excel (.xlsx) round-trip', () {
      final wb = SheetsController.buildDefaultWorkbook();
      final xlsxBytes = SheetIO.encodeXlsxBytes(wb);
      expect(xlsxBytes.isNotEmpty, isTrue);

      final decoded = SheetIO.decodeXlsxBytes(xlsxBytes, title: 'budget.xlsx');
      expect(decoded.sheets.length, 3);
      expect(decoded.sheets[0].name, 'Infrastructure Cost');
      expect(
        decoded.sheets[0].getCellByA1('A2').displayValue,
        'GPU Inference Nodes',
      );
      expect(decoded.sheets[0].getCellByA1('E8').rawInput, '=SUM(E2:E7)');
      expect(
        decoded.sheets[0].getCellByA1('E8').computedValue,
        closeTo(28920.0, 1e-3),
      );
      expect(decoded.sheets[1].name, 'Revenue & ARR');
    });

    test('serializes and parses RFC-4180 CSV with quoted fields', () {
      final sheet = Worksheet(id: 'csv_s', name: 'CSV');
      sheet.setCell(0, 0, const SheetCell(rawInput: 'Service, Tier'));
      sheet.setCell(0, 1, const SheetCell(rawInput: 'Quote "Alpha" Node'));
      sheet.setCell(0, 2, const SheetCell(rawInput: '4250'));

      final csv = SheetIO.toCsv(sheet);
      expect(csv, contains('"Service, Tier"'));
      expect(csv, contains('"Quote ""Alpha"" Node"'));

      final parsed = SheetIO.fromCsv(csv);
      expect(parsed.getCell(0, 0).rawInput, 'Service, Tier');
      expect(parsed.getCell(0, 1).rawInput, 'Quote "Alpha" Node');
      expect(parsed.getCell(0, 2).computedValue, closeTo(4250.0, 1e-6));
    });
  });

  group('fyrSheets UI Smoke Test', () {
    testWidgets('renders TopBar, FormulaRibbon, Grid, Charts, and Sheet Tabs',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 880);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = SheetsController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrSheetsApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrSheets'), findsOneWidget);
      expect(find.text('Q4_Cloud_Infrastructure_Budget.ods'), findsOneWidget);
      expect(find.text('Infrastructure Cost'), findsOneWidget);
      expect(find.text('Revenue & ARR'), findsOneWidget);
      expect(find.text('Benchmarks'), findsOneWidget);
      expect(find.text('Monthly Cluster Cost by Service'), findsOneWidget);
      expect(find.text('SUM: \$28,920.00'), findsOneWidget);

      ctrl.dispose();
    });
  });
}
