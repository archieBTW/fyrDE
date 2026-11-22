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
  CellCoordinate _activeCell = const CellCoordinate(0, 0); // A1
  CellCoordinate _selectionAnchor = const CellCoordinate(0, 0);
  CellCoordinate _selectionFocus = const CellCoordinate(0, 0);

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
    _workbook = buildDefaultWorkbook();
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
  // Default Blank Workbook
  // ===========================================================================

  static SpreadsheetWorkbook buildDefaultWorkbook() {
    return SpreadsheetWorkbook(
      id: 'wb_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Untitled.ods',
      format: WorkbookFormat.ods,
      sheets: [
        Worksheet(
          id: 'sheet_1',
          name: 'Sheet 1',
        ),
      ],
    );
  }

  @override
  void dispose() {
    formulaController.dispose();
    super.dispose();
  }
}
