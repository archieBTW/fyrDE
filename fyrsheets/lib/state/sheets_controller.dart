import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/formula_engine.dart';
import '../engine/sheet_io.dart';
import '../models/sheet_models.dart';

enum RightInspectorTab {
  charts,
  style,
  rules,
}

class SheetsController extends ChangeNotifier {
  late SpreadsheetWorkbook _workbook;
  CellCoordinate _activeCell = const CellCoordinate(7, 4); // E8
  CellCoordinate _selectionAnchor = const CellCoordinate(7, 4);
  CellCoordinate _selectionFocus = const CellCoordinate(7, 4);

  final TextEditingController formulaController = TextEditingController();
  bool isEditingInline = false;
  bool showRightPanel = true;
  RightInspectorTab activeInspectorTab = RightInspectorTab.charts;
  String? statusMessage;

  final List<SpreadsheetWorkbook> _undoStack = [];
  final List<SpreadsheetWorkbook> _redoStack = [];
  static const int _maxHistory = 40;

  SheetsController({SpreadsheetWorkbook? initialWorkbook}) {
    _workbook = initialWorkbook ?? buildDefaultWorkbook();
    FormulaEngine.recalculateWorkbook(_workbook);
    _syncFormulaBar();
  }

  SpreadsheetWorkbook get workbook => _workbook;
  Worksheet get activeSheet => _workbook.activeSheet;
  CellCoordinate get activeCell => _activeCell;
  CellRange get selectionRange => CellRange(_selectionAnchor, _selectionFocus);

  SheetCell get currentCell =>
      activeSheet.getCell(_activeCell.row, _activeCell.col);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  RangeAggregateSummary get selectionSummary {
    final range = selectionRange;
    if (!range.isSingleCell) {
      return FormulaEngine.summarizeRange(activeSheet, range);
    }
    // When a single formula cell referencing a range (like E8 =SUM(E2:E7)) is selected,
    // summarize its target range so the status bar shows rich aggregate telemetry.
    final cell = currentCell;
    if (cell.isFormula) {
      final match = RegExp(r'([A-Za-z]+\d+:[A-Za-z]+\d+)')
          .firstMatch(cell.rawInput);
      if (match != null) {
        final coords = CellCoordinate.expandRange(match.group(1)!);
        if (coords.length > 1) {
          return FormulaEngine.summarizeRange(
            activeSheet,
            CellRange(coords.first, coords.last),
          );
        }
      }
    }
    return FormulaEngine.summarizeRange(activeSheet, range);
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_workbook.clone());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(_workbook.clone());
    _workbook = _undoStack.removeLast();
    FormulaEngine.recalculateWorkbook(_workbook);
    _syncFormulaBar();
    statusMessage = 'Undid last action';
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_workbook.clone());
    _workbook = _redoStack.removeLast();
    FormulaEngine.recalculateWorkbook(_workbook);
    _syncFormulaBar();
    statusMessage = 'Redid action';
    notifyListeners();
  }

  void selectCell(
    CellCoordinate coord, {
    bool extendSelection = false,
    bool startInlineEdit = false,
  }) {
    final clamped = CellCoordinate(
      coord.row.clamp(0, activeSheet.rowCount - 1),
      coord.col.clamp(0, activeSheet.colCount - 1),
    );
    _activeCell = clamped;
    if (extendSelection) {
      _selectionFocus = clamped;
    } else {
      _selectionAnchor = clamped;
      _selectionFocus = clamped;
    }
    isEditingInline = startInlineEdit;
    _syncFormulaBar();
    notifyListeners();
  }

  void updateDragSelection(CellCoordinate coord) {
    final clamped = CellCoordinate(
      coord.row.clamp(0, activeSheet.rowCount - 1),
      coord.col.clamp(0, activeSheet.colCount - 1),
    );
    if (_selectionFocus != clamped) {
      _selectionFocus = clamped;
      notifyListeners();
    }
  }

  void moveSelection(int dRow, int dCol, {bool extend = false}) {
    final base = extend ? _selectionFocus : _activeCell;
    final nextCoord = CellCoordinate(
      (base.row + dRow).clamp(0, activeSheet.rowCount - 1),
      (base.col + dCol).clamp(0, activeSheet.colCount - 1),
    );
    selectCell(nextCoord, extendSelection: extend);
  }

  void _syncFormulaBar() {
    final raw = currentCell.rawInput;
    if (formulaController.text != raw) {
      formulaController.text = raw;
    }
  }

  void commitFormulaBarValue([String? overrideValue]) {
    final text = overrideValue ?? formulaController.text;
    setCellInput(_activeCell.row, _activeCell.col, text);
    isEditingInline = false;
  }

  void cancelFormulaBarEdit() {
    isEditingInline = false;
    _syncFormulaBar();
    notifyListeners();
  }

  void setCellInput(int row, int col, String rawInput) {
    final existing = activeSheet.getCell(row, col);
    if (existing.rawInput == rawInput) {
      isEditingInline = false;
      notifyListeners();
      return;
    }
    _pushUndoSnapshot();
    final updated = existing.copyWith(rawInput: rawInput);
    activeSheet.setCell(row, col, updated);
    FormulaEngine.recalculateWorksheet(activeSheet);
    _syncFormulaBar();
    notifyListeners();
  }

  void clearSelectedCells() {
    _pushUndoSnapshot();
    final range = selectionRange;
    for (var r = range.minRow; r <= range.maxRow; r++) {
      for (var c = range.minCol; c <= range.maxCol; c++) {
        final existing = activeSheet.getCell(r, c);
        activeSheet.setCell(
          r,
          c,
          SheetCell(rawInput: '', displayValue: '', style: existing.style),
        );
      }
    }
    FormulaEngine.recalculateWorksheet(activeSheet);
    _syncFormulaBar();
    statusMessage = 'Cleared ${range.toA1()}';
    notifyListeners();
  }

  void updateSelectedCellsStyle(CellStyle Function(CellStyle current) updater) {
    _pushUndoSnapshot();
    final range = selectionRange;
    for (var r = range.minRow; r <= range.maxRow; r++) {
      for (var c = range.minCol; c <= range.maxCol; c++) {
        final cell = activeSheet.getCell(r, c);
        final newStyle = updater(cell.style);
        final formatted = newStyle.formatValue(
          cell.computedValue,
          cell.rawInput,
        );
        activeSheet.setCell(
          r,
          c,
          cell.copyWith(style: newStyle, displayValue: formatted),
        );
      }
    }
    FormulaEngine.recalculateWorksheet(activeSheet);
    notifyListeners();
  }

  void toggleBold() {
    final target = !currentCell.style.bold;
    updateSelectedCellsStyle((s) => s.copyWith(bold: target));
  }

  void toggleItalic() {
    final target = !currentCell.style.italic;
    updateSelectedCellsStyle((s) => s.copyWith(italic: target));
  }

  void toggleUnderline() {
    final target = !currentCell.style.underline;
    updateSelectedCellsStyle((s) => s.copyWith(underline: target));
  }

  void setAlignment(CellAlign align) {
    updateSelectedCellsStyle((s) => s.copyWith(align: align));
  }

  void setNumberFormat(NumberFormatType fmt) {
    updateSelectedCellsStyle((s) => s.copyWith(numberFormat: fmt));
  }

  void adjustDecimals(int delta) {
    final nextDec = (currentCell.style.decimals + delta).clamp(0, 6);
    updateSelectedCellsStyle((s) => s.copyWith(decimals: nextDec));
  }

  void setTextColor(String? hex) {
    updateSelectedCellsStyle(
      (s) => hex == null
          ? s.copyWith(clearTextColor: true)
          : s.copyWith(textColorHex: hex),
    );
  }

  void setFillColor(String? hex) {
    updateSelectedCellsStyle(
      (s) => hex == null
          ? s.copyWith(clearFillColor: true)
          : s.copyWith(fillColorHex: hex),
    );
  }

  void insertQuickFunction(String funcName) {
    final range = selectionRange;
    String targetRange;
    if (!range.isSingleCell) {
      targetRange = range.toA1();
    } else {
      final r = _activeCell.row;
      final c = _activeCell.col;
      final topRow = math.max(1, r - 5);
      final bottomRow = math.max(1, r - 1);
      final colLet = CellCoordinate.colToLetters(c);
      targetRange = '$colLet${topRow + 1}:$colLet${bottomRow + 1}';
    }
    final formula = funcName == 'IF'
        ? '=IF($targetRange>5000,"High","Normal")'
        : '=$funcName($targetRange)';
    formulaController.text = formula;
    setCellInput(_activeCell.row, _activeCell.col, formula);
  }

  void insertRowAbove() {
    _pushUndoSnapshot();
    final targetRow = _activeCell.row;
    final newCells = <String, SheetCell>{};
    activeSheet.cells.forEach((key, cell) {
      final coord = CellCoordinate.tryParse(key);
      if (coord == null) return;
      if (coord.row >= targetRow) {
        newCells[CellCoordinate(coord.row + 1, coord.col).a1] = cell;
      } else {
        newCells[key] = cell;
      }
    });
    activeSheet.cells
      ..clear()
      ..addAll(newCells);
    activeSheet.rowCount++;
    FormulaEngine.recalculateWorksheet(activeSheet);
    statusMessage = 'Inserted row at ${targetRow + 1}';
    notifyListeners();
  }

  void deleteActiveRow() {
    if (activeSheet.rowCount <= 2) return;
    _pushUndoSnapshot();
    final targetRow = _activeCell.row;
    final newCells = <String, SheetCell>{};
    activeSheet.cells.forEach((key, cell) {
      final coord = CellCoordinate.tryParse(key);
      if (coord == null) return;
      if (coord.row == targetRow) return;
      if (coord.row > targetRow) {
        newCells[CellCoordinate(coord.row - 1, coord.col).a1] = cell;
      } else {
        newCells[key] = cell;
      }
    });
    activeSheet.cells
      ..clear()
      ..addAll(newCells);
    FormulaEngine.recalculateWorksheet(activeSheet);
    _syncFormulaBar();
    statusMessage = 'Deleted row ${targetRow + 1}';
    notifyListeners();
  }

  void insertColumnLeft() {
    _pushUndoSnapshot();
    final targetCol = _activeCell.col;
    final newCells = <String, SheetCell>{};
    activeSheet.cells.forEach((key, cell) {
      final coord = CellCoordinate.tryParse(key);
      if (coord == null) return;
      if (coord.col >= targetCol) {
        newCells[CellCoordinate(coord.row, coord.col + 1).a1] = cell;
      } else {
        newCells[key] = cell;
      }
    });
    activeSheet.cells
      ..clear()
      ..addAll(newCells);
    activeSheet.colCount++;
    FormulaEngine.recalculateWorksheet(activeSheet);
    statusMessage =
        'Inserted column ${CellCoordinate.colToLetters(targetCol)}';
    notifyListeners();
  }

  void deleteActiveColumn() {
    if (activeSheet.colCount <= 2) return;
    _pushUndoSnapshot();
    final targetCol = _activeCell.col;
    final newCells = <String, SheetCell>{};
    activeSheet.cells.forEach((key, cell) {
      final coord = CellCoordinate.tryParse(key);
      if (coord == null) return;
      if (coord.col == targetCol) return;
      if (coord.col > targetCol) {
        newCells[CellCoordinate(coord.row, coord.col - 1).a1] = cell;
      } else {
        newCells[key] = cell;
      }
    });
    activeSheet.cells
      ..clear()
      ..addAll(newCells);
    FormulaEngine.recalculateWorksheet(activeSheet);
    _syncFormulaBar();
    statusMessage =
        'Deleted column ${CellCoordinate.colToLetters(targetCol)}';
    notifyListeners();
  }

  void sortActiveColumn({required bool ascending}) {
    _pushUndoSnapshot();
    final col = _activeCell.col;
    final startRow = activeSheet.frozenRows;
    var maxDataRow = startRow;
    for (final k in activeSheet.cells.keys) {
      final coord = CellCoordinate.tryParse(k);
      if (coord != null && coord.row > maxDataRow) {
        // Stop before summary rows that contain SUM/AVERAGE formulas
        final cell = activeSheet.cells[k]!;
        if (!cell.rawInput.toUpperCase().contains('SUM(') &&
            !cell.rawInput.toUpperCase().contains('AVERAGE(')) {
          maxDataRow = coord.row;
        }
      }
    }
    if (maxDataRow <= startRow) return;

    final rowsData = <List<SheetCell>>[];
    for (var r = startRow; r <= maxDataRow; r++) {
      final rowCells = <SheetCell>[];
      var hasAny = false;
      for (var c = 0; c < activeSheet.colCount; c++) {
        final cell = activeSheet.getCell(r, c);
        if (!cell.isEmpty) hasAny = true;
        rowCells.add(cell);
      }
      if (hasAny) rowsData.add(rowCells);
    }

    rowsData.sort((a, b) {
      final ca = col < a.length ? a[col] : const SheetCell();
      final cb = col < b.length ? b[col] : const SheetCell();
      final va = ca.computedValue;
      final vb = cb.computedValue;
      int cmp;
      if (va is num && vb is num) {
        cmp = va.compareTo(vb);
      } else {
        cmp = ca.displayValue.compareTo(cb.displayValue);
      }
      return ascending ? cmp : -cmp;
    });

    for (var i = 0; i < rowsData.length; i++) {
      final r = startRow + i;
      for (var c = 0; c < rowsData[i].length; c++) {
        activeSheet.setCell(r, c, rowsData[i][c]);
      }
    }

    FormulaEngine.recalculateWorksheet(activeSheet);
    statusMessage =
        'Sorted column ${CellCoordinate.colToLetters(col)} (${ascending ? "A→Z" : "Z→A"})';
    notifyListeners();
  }

  void setColumnWidth(int col, double width) {
    activeSheet.columnWidths[col] = width.clamp(64.0, 420.0);
    notifyListeners();
  }

  // ===========================================================================
  // Multi-Sheet Operations
  // ===========================================================================

  void switchSheet(int index) {
    if (index < 0 || index >= _workbook.sheets.length) return;
    _workbook.activeSheetIndex = index;
    _activeCell = const CellCoordinate(0, 0);
    _selectionAnchor = _activeCell;
    _selectionFocus = _activeCell;
    FormulaEngine.recalculateWorksheet(activeSheet);
    _syncFormulaBar();
    notifyListeners();
  }

  void addSheet({String? name}) {
    _pushUndoSnapshot();
    final idx = _workbook.sheets.length + 1;
    final sheet = Worksheet(
      id: 'sheet_${DateTime.now().millisecondsSinceEpoch}_$idx',
      name: name ?? 'Sheet $idx',
    );
    _workbook.sheets.add(sheet);
    _workbook.activeSheetIndex = _workbook.sheets.length - 1;
    _activeCell = const CellCoordinate(0, 0);
    _selectionAnchor = _activeCell;
    _selectionFocus = _activeCell;
    _syncFormulaBar();
    statusMessage = 'Added ${sheet.name}';
    notifyListeners();
  }

  void duplicateSheet(int index) {
    if (index < 0 || index >= _workbook.sheets.length) return;
    _pushUndoSnapshot();
    final source = _workbook.sheets[index];
    final copy = source.clone(
      newId: 'sheet_${DateTime.now().millisecondsSinceEpoch}',
      newName: '${source.name} Copy',
    );
    _workbook.sheets.insert(index + 1, copy);
    _workbook.activeSheetIndex = index + 1;
    FormulaEngine.recalculateWorksheet(activeSheet);
    _syncFormulaBar();
    statusMessage = 'Duplicated ${source.name}';
    notifyListeners();
  }

  void renameSheet(int index, String newName) {
    if (index < 0 || index >= _workbook.sheets.length) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _pushUndoSnapshot();
    _workbook.sheets[index].name = trimmed;
    notifyListeners();
  }

  void deleteSheet(int index) {
    if (_workbook.sheets.length <= 1) return;
    if (index < 0 || index >= _workbook.sheets.length) return;
    _pushUndoSnapshot();
    final removed = _workbook.sheets.removeAt(index);
    if (_workbook.activeSheetIndex >= _workbook.sheets.length) {
      _workbook.activeSheetIndex = _workbook.sheets.length - 1;
    }
    _syncFormulaBar();
    statusMessage = 'Deleted ${removed.name}';
    notifyListeners();
  }

  // ===========================================================================
  // Charts & Conditional Rules
  // ===========================================================================

  void updateChart(SheetChartConfig updated) {
    _pushUndoSnapshot();
    final idx = activeSheet.charts.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) {
      activeSheet.charts[idx] = updated;
    } else {
      activeSheet.charts.add(updated);
    }
    notifyListeners();
  }

  void addChart({
    String title = 'Selection Series',
    ChartType type = ChartType.bar,
    String labelRange = 'A2:A7',
    String valueRange = 'E2:E7',
  }) {
    _pushUndoSnapshot();
    activeSheet.charts.add(
      SheetChartConfig(
        id: 'chart_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        type: type,
        labelRange: labelRange,
        valueRange: valueRange,
      ),
    );
    notifyListeners();
  }

  void addConditionalRule(ConditionalRule rule) {
    _pushUndoSnapshot();
    activeSheet.conditionalRules.add(rule);
    notifyListeners();
  }

  void removeConditionalRule(String id) {
    _pushUndoSnapshot();
    activeSheet.conditionalRules.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  void toggleRightPanel([RightInspectorTab? tab]) {
    if (tab != null) {
      if (showRightPanel && activeInspectorTab == tab) {
        showRightPanel = false;
      } else {
        showRightPanel = true;
        activeInspectorTab = tab;
      }
    } else {
      showRightPanel = !showRightPanel;
    }
    notifyListeners();
  }

  // ===========================================================================
  // File I/O Operations
  // ===========================================================================

  void newWorkbook() {
    _pushUndoSnapshot();
    final sheet = Worksheet(id: 'sheet_1', name: 'Sheet 1');
    _workbook = SpreadsheetWorkbook(
      id: 'wb_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Untitled_Workbook.ods',
      format: WorkbookFormat.ods,
      sheets: [sheet],
    );
    _activeCell = const CellCoordinate(0, 0);
    _selectionAnchor = _activeCell;
    _selectionFocus = _activeCell;
    _syncFormulaBar();
    statusMessage = 'Created new workbook';
    notifyListeners();
  }

  Future<void> openWorkbookFromFile(String path) async {
    try {
      final loaded = await SheetIO.loadWorkbook(path);
      _pushUndoSnapshot();
      _workbook = loaded;
      _activeCell = const CellCoordinate(0, 0);
      _selectionAnchor = _activeCell;
      _selectionFocus = _activeCell;
      _syncFormulaBar();
      statusMessage = 'Opened ${loaded.title}';
      notifyListeners();
    } catch (e) {
      statusMessage = 'Failed to open file: $e';
      notifyListeners();
    }
  }

  Future<void> saveWorkbookToFile(String path) async {
    try {
      await SheetIO.saveWorkbook(_workbook, path);
      statusMessage = 'Saved ${_workbook.title} (${_workbook.format.badgeLabel})';
      notifyListeners();
    } catch (e) {
      statusMessage = 'Failed to save file: $e';
      notifyListeners();
    }
  }

  // ===========================================================================
  // Default Pre-Populated Workbook
  // ===========================================================================

  static SpreadsheetWorkbook buildDefaultWorkbook() {
    const headerStyle = CellStyle(
      bold: true,
      fillColorHex: '#1F182B',
      textColorHex: '#E9B8FF',
      align: CellAlign.left,
    );
    const numHeaderStyle = CellStyle(
      bold: true,
      fillColorHex: '#1F182B',
      textColorHex: '#E9B8FF',
      align: CellAlign.right,
    );
    const currencyStyle = CellStyle(
      numberFormat: NumberFormatType.currency,
      decimals: 2,
      align: CellAlign.right,
    );
    const boldCurrencyStyle = CellStyle(
      bold: true,
      numberFormat: NumberFormatType.currency,
      decimals: 2,
      align: CellAlign.right,
      fillColorHex: '#1B1426',
      textColorHex: '#D040FF',
    );
    const percentStyle = CellStyle(
      numberFormat: NumberFormatType.percent,
      decimals: 1,
      align: CellAlign.right,
    );
    const intStyle = CellStyle(
      numberFormat: NumberFormatType.number,
      decimals: 0,
      align: CellAlign.right,
    );
    const centerBadgeStyle = CellStyle(
      bold: true,
      align: CellAlign.center,
    );

    // Sheet 1: Infrastructure Cost
    final sheet1 = Worksheet(
      id: 'sheet_infra',
      name: 'Infrastructure Cost',
      rowCount: 40,
      colCount: 12,
      columnWidths: {
        0: 196.0,
        1: 118.0,
        2: 88.0,
        3: 112.0,
        4: 132.0,
        5: 108.0,
        6: 106.0,
      },
      charts: [
        const SheetChartConfig(
          id: 'chart_infra_cost',
          title: 'Monthly Cluster Cost by Service',
          type: ChartType.bar,
          labelRange: 'A2:A7',
          valueRange: 'E2:E7',
          accentHex: '#D040FF',
        ),
      ],
      conditionalRules: [
        const ConditionalRule(
          id: 'rule_high_cost',
          range: 'E2:E7',
          operator: ConditionalOperator.greaterThan,
          threshold: '5000',
          highlightHex: '#D040FF',
        ),
      ],
    );

    final headers1 = [
      ('Service Workload', headerStyle),
      ('Region', headerStyle),
      ('Nodes', numHeaderStyle),
      ('Unit Rate', numHeaderStyle),
      ('Monthly Cost', numHeaderStyle),
      ('Share %', numHeaderStyle),
      ('Tier Alert', headerStyle),
    ];
    for (var c = 0; c < headers1.length; c++) {
      sheet1.setCell(
        0,
        c,
        SheetCell(
          rawInput: headers1[c].$1,
          displayValue: headers1[c].$1,
          style: headers1[c].$2,
        ),
      );
    }

    final rows1 = [
      ('GPU Inference Nodes', 'us-east-1', '16', '600'),
      ('Kubernetes Control Plane', 'us-west-2', '12', '450'),
      ('Postgres HA Replicas', 'eu-central-1', '8', '520'),
      ('Object Storage Tier-1', 'global-cdn', '31', '40'),
      ('Vector Search Cluster', 'us-east-1', '10', '512'),
      ('Edge WAF & Telemetry', 'global-edge', '20', '170'),
    ];

    for (var i = 0; i < rows1.length; i++) {
      final r = i + 1;
      final rowNum = r + 1;
      final item = rows1[i];
      sheet1.setCell(0 + r, 0, SheetCell(rawInput: item.$1));
      sheet1.setCell(0 + r, 1, SheetCell(rawInput: item.$2));
      sheet1.setCell(
        0 + r,
        2,
        SheetCell(rawInput: item.$3, style: intStyle),
      );
      sheet1.setCell(
        0 + r,
        3,
        SheetCell(rawInput: item.$4, style: currencyStyle),
      );
      sheet1.setCell(
        0 + r,
        4,
        SheetCell(
          rawInput: '=C$rowNum*D$rowNum',
          style: currencyStyle,
        ),
      );
      sheet1.setCell(
        0 + r,
        5,
        SheetCell(
          rawInput: '=E$rowNum/E8',
          style: percentStyle,
        ),
      );
      sheet1.setCell(
        0 + r,
        6,
        SheetCell(
          rawInput: '=IF(E$rowNum>5000,"High","Normal")',
          style: centerBadgeStyle,
        ),
      );
    }

    // Row 8 (index 7): Total Cluster Spend
    sheet1.setCell(
      7,
      0,
      const SheetCell(
        rawInput: 'Total Monthly Spend',
        style: CellStyle(
          bold: true,
          fillColorHex: '#1B1426',
          textColorHex: '#FFFFFF',
        ),
      ),
    );
    sheet1.setCell(
      7,
      2,
      const SheetCell(
        rawInput: '=SUM(C2:C7)',
        style: CellStyle(
          bold: true,
          numberFormat: NumberFormatType.number,
          decimals: 0,
          align: CellAlign.right,
          fillColorHex: '#1B1426',
        ),
      ),
    );
    sheet1.setCell(
      7,
      4,
      const SheetCell(
        rawInput: '=SUM(E2:E7)',
        style: boldCurrencyStyle,
      ),
    );
    sheet1.setCell(
      7,
      5,
      const SheetCell(
        rawInput: '=SUM(F2:F7)',
        style: CellStyle(
          bold: true,
          numberFormat: NumberFormatType.percent,
          decimals: 1,
          align: CellAlign.right,
          fillColorHex: '#1B1426',
        ),
      ),
    );

    // Row 9 (index 8): Average Service Cost
    sheet1.setCell(
      8,
      0,
      const SheetCell(
        rawInput: 'Average Workload Cost',
        style: CellStyle(bold: true, textColorHex: '#B8B5C0'),
      ),
    );
    sheet1.setCell(
      8,
      4,
      const SheetCell(
        rawInput: '=AVERAGE(E2:E7)',
        style: currencyStyle,
      ),
    );

    // Sheet 2: Revenue & ARR
    final sheet2 = Worksheet(
      id: 'sheet_arr',
      name: 'Revenue & ARR',
      rowCount: 35,
      colCount: 10,
      columnWidths: {0: 160.0, 1: 130.0, 2: 130.0, 3: 130.0, 4: 130.0},
      charts: [
        const SheetChartConfig(
          id: 'chart_arr_growth',
          title: 'Quarterly ARR Progression',
          type: ChartType.line,
          labelRange: 'A2:A5',
          valueRange: 'D2:D5',
          accentHex: '#00E5FF',
        ),
      ],
    );

    final headers2 = [
      'Quarter',
      'Enterprise ARR',
      'Self-Serve ARR',
      'Total ARR',
      'Net Margin',
    ];
    for (var c = 0; c < headers2.length; c++) {
      sheet2.setCell(
        0,
        c,
        SheetCell(rawInput: headers2[c], style: headerStyle),
      );
    }

    final arrRows = [
      ('Q1 2026', '420000', '115000', '0.74'),
      ('Q2 2026', '510000', '142000', '0.77'),
      ('Q3 2026', '645000', '178000', '0.79'),
      ('Q4 2026', '810000', '215000', '0.82'),
    ];
    for (var i = 0; i < arrRows.length; i++) {
      final r = i + 1;
      final rn = r + 1;
      sheet2.setCell(r, 0, SheetCell(rawInput: arrRows[i].$1));
      sheet2.setCell(
        r,
        1,
        SheetCell(rawInput: arrRows[i].$2, style: currencyStyle),
      );
      sheet2.setCell(
        r,
        2,
        SheetCell(rawInput: arrRows[i].$3, style: currencyStyle),
      );
      sheet2.setCell(
        r,
        3,
        SheetCell(rawInput: '=B$rn+C$rn', style: boldCurrencyStyle),
      );
      sheet2.setCell(
        r,
        4,
        SheetCell(rawInput: arrRows[i].$4, style: percentStyle),
      );
    }

    // Sheet 3: Benchmarks
    final sheet3 = Worksheet(
      id: 'sheet_bench',
      name: 'Benchmarks',
      rowCount: 35,
      colCount: 10,
      columnWidths: {0: 180.0, 1: 120.0, 2: 120.0, 3: 120.0},
    );
    final headers3 = ['Engine Kernel', 'p50 Latency (ms)', 'p99 Latency (ms)', 'Throughput (req/s)'];
    for (var c = 0; c < headers3.length; c++) {
      sheet3.setCell(0, c, SheetCell(rawInput: headers3[c], style: headerStyle));
    }
    final benchRows = [
      ('fyrWayland Compositor', '1.2', '3.4', '14400'),
      ('fyrSheets Formula AST', '0.4', '1.1', '92000'),
      ('ODS Archive Streamer', '4.8', '9.2', '6800'),
    ];
    for (var i = 0; i < benchRows.length; i++) {
      final r = i + 1;
      sheet3.setCell(r, 0, SheetCell(rawInput: benchRows[i].$1));
      sheet3.setCell(r, 1, SheetCell(rawInput: benchRows[i].$2));
      sheet3.setCell(r, 2, SheetCell(rawInput: benchRows[i].$3));
      sheet3.setCell(r, 3, SheetCell(rawInput: benchRows[i].$4, style: intStyle));
    }

    final wb = SpreadsheetWorkbook(
      id: 'wb_default_q4',
      title: 'Q4_Cloud_Infrastructure_Budget.ods',
      format: WorkbookFormat.ods,
      sheets: [sheet1, sheet2, sheet3],
    );
    FormulaEngine.recalculateWorkbook(wb);
    return wb;
  }

  @override
  void dispose() {
    formulaController.dispose();
    super.dispose();
  }
}
