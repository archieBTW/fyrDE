import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fyrsheets/engine/formula_engine.dart';
import 'package:fyrsheets/engine/sheet_io.dart';
import 'package:fyrsheets/main.dart';
import 'package:fyrsheets/models/sheet_models.dart';
import 'package:fyrsheets/state/sheets_controller.dart';

SpreadsheetWorkbook _buildRoundTripTestWorkbook() {
  final sheet1 = Worksheet(id: 's1', name: 'Costs');
  sheet1.setCell(0, 0, const SheetCell(rawInput: 'Item'));
  sheet1.setCell(0, 1, const SheetCell(rawInput: 'Qty'));
  sheet1.setCell(0, 2, const SheetCell(rawInput: 'Price'));
  sheet1.setCell(0, 3, const SheetCell(rawInput: 'Total'));

  sheet1.setCell(1, 0, const SheetCell(rawInput: 'Compute Node'));
  sheet1.setCell(1, 1, const SheetCell(rawInput: '4'));
  sheet1.setCell(1, 2, const SheetCell(rawInput: '250'));
  sheet1.setCell(1, 3, const SheetCell(rawInput: '=B2*C2'));

  sheet1.setCell(2, 0, const SheetCell(rawInput: 'Storage Pool'));
  sheet1.setCell(2, 1, const SheetCell(rawInput: '2'));
  sheet1.setCell(2, 2, const SheetCell(rawInput: '150'));
  sheet1.setCell(2, 3, const SheetCell(rawInput: '=B3*C3'));

  sheet1.setCell(3, 0, const SheetCell(rawInput: 'Grand Total'));
  sheet1.setCell(3, 3, const SheetCell(rawInput: '=SUM(D2:D3)'));

  final sheet2 = Worksheet(id: 's2', name: 'Summary');
  sheet2.setCell(0, 0, const SheetCell(rawInput: 'Status'));
  sheet2.setCell(1, 0, const SheetCell(rawInput: 'Active'));

  final wb = SpreadsheetWorkbook(
    id: 'wb_test',
    title: 'test_workbook.ods',
    format: WorkbookFormat.ods,
    sheets: [sheet1, sheet2],
  );
  FormulaEngine.recalculateWorkbook(wb);
  return wb;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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
    test('default controller opens to a clean blank workbook', () {
      final ctrl = SheetsController();
      expect(ctrl.workbook.title, 'Untitled.ods');
      expect(ctrl.workbook.format, WorkbookFormat.ods);
      expect(ctrl.workbook.sheets.length, 1);
      expect(ctrl.activeSheet.name, 'Sheet 1');
      expect(ctrl.activeSheet.cells, isEmpty);
      expect(ctrl.activeSheet.charts, isEmpty);
      expect(ctrl.activeSheet.conditionalRules, isEmpty);
      expect(ctrl.activeCell, const CellCoordinate(0, 0));
      ctrl.dispose();
    });

    test('encodes and decodes OpenDocument Spreadsheet (.ods) round-trip', () {
      final wb = _buildRoundTripTestWorkbook();
      final odsBytes = SheetIO.encodeOdsBytes(wb);
      expect(odsBytes.isNotEmpty, isTrue);

      final decoded = SheetIO.decodeOdsBytes(odsBytes, title: wb.title);
      expect(decoded.sheets.length, 2);
      expect(decoded.sheets[0].name, 'Costs');
      expect(
        decoded.sheets[0].getCellByA1('A2').displayValue,
        'Compute Node',
      );
      expect(decoded.sheets[0].getCellByA1('D4').rawInput, '=SUM(D2:D3)');
      expect(
        decoded.sheets[0].getCellByA1('D4').computedValue,
        closeTo(1300.0, 1e-3),
      );
    });

    test('encodes and decodes Microsoft Excel (.xlsx) round-trip', () {
      final wb = _buildRoundTripTestWorkbook();
      final xlsxBytes = SheetIO.encodeXlsxBytes(wb);
      expect(xlsxBytes.isNotEmpty, isTrue);

      final decoded = SheetIO.decodeXlsxBytes(xlsxBytes, title: 'budget.xlsx');
      expect(decoded.sheets.length, 2);
      expect(decoded.sheets[0].name, 'Costs');
      expect(
        decoded.sheets[0].getCellByA1('A2').displayValue,
        'Compute Node',
      );
      expect(decoded.sheets[0].getCellByA1('D4').rawInput, '=SUM(D2:D3)');
      expect(
        decoded.sheets[0].getCellByA1('D4').computedValue,
        closeTo(1300.0, 1e-3),
      );
      expect(decoded.sheets[1].name, 'Summary');
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
    testWidgets('renders TopBar, FormulaRibbon, Grid, Charts, and clean Sheet 1',
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
      expect(find.text('Untitled.ods'), findsOneWidget);
      expect(find.text('Sheet 1'), findsOneWidget);
      expect(find.text('No charts on this sheet yet.'), findsOneWidget);
      expect(find.text('COUNT: 0'), findsOneWidget);
      expect(find.text('Q4_Cloud_Infrastructure_Budget.ods'), findsNothing);
      expect(find.text('Infrastructure Cost'), findsNothing);

      ctrl.dispose();
    });
  });
}
