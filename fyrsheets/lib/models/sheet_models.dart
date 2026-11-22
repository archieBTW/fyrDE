import 'dart:math' as math;

enum NumberFormatType {
  general,
  number,
  currency,
  percent,
  scientific,
  date,
}

enum CellAlign {
  left,
  center,
  right,
}

enum ChartType {
  bar,
  line,
  area,
  pie,
}

enum ConditionalOperator {
  greaterThan,
  lessThan,
  equals,
  contains,
}

enum WorkbookFormat {
  ods,
  xlsx,
  csv,
  tsv;

  String get extension {
    switch (this) {
      case WorkbookFormat.ods:
        return 'ods';
      case WorkbookFormat.xlsx:
        return 'xlsx';
      case WorkbookFormat.csv:
        return 'csv';
      case WorkbookFormat.tsv:
        return 'tsv';
    }
  }

  String get badgeLabel => extension.toUpperCase();

  static WorkbookFormat fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.xlsx')) return WorkbookFormat.xlsx;
    if (lower.endsWith('.csv')) return WorkbookFormat.csv;
    if (lower.endsWith('.tsv')) return WorkbookFormat.tsv;
    return WorkbookFormat.ods;
  }
}

class CellCoordinate {
  final int row; // 0-indexed
  final int col; // 0-indexed

  const CellCoordinate(this.row, this.col);

  String get a1 => '${colToLetters(col)}${row + 1}';

  static String colToLetters(int colIndex) {
    var n = colIndex + 1;
    final sb = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      sb.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }

  static int lettersToCol(String letters) {
    final upper = letters.trim().toUpperCase();
    var result = 0;
    for (var i = 0; i < upper.length; i++) {
      final code = upper.codeUnitAt(i);
      if (code < 65 || code > 90) {
        throw FormatException('Invalid column letter in "$letters"');
      }
      result = result * 26 + (code - 64);
    }
    return result - 1;
  }

  static final RegExp _a1Regex = RegExp(r'^\$?([A-Za-z]+)\$?(\d+)$');

  static CellCoordinate? tryParse(String ref) {
    final match = _a1Regex.firstMatch(ref.trim());
    if (match == null) return null;
    final colStr = match.group(1)!;
    final rowStr = match.group(2)!;
    final rowNum = int.tryParse(rowStr);
    if (rowNum == null || rowNum < 1) return null;
    final colIndex = lettersToCol(colStr);
    if (colIndex < 0) return null;
    return CellCoordinate(rowNum - 1, colIndex);
  }

  static CellCoordinate parse(String ref) {
    final parsed = tryParse(ref);
    if (parsed == null) {
      throw FormatException('Invalid A1 cell coordinate: "$ref"');
    }
    return parsed;
  }

  static List<CellCoordinate> expandRange(String rangeSpec) {
    final clean = rangeSpec.trim();
    if (!clean.contains(':')) {
      final single = tryParse(clean);
      return single != null ? [single] : const [];
    }
    final parts = clean.split(':');
    if (parts.length != 2) return const [];
    final start = tryParse(parts[0]);
    final end = tryParse(parts[1]);
    if (start == null || end == null) return const [];
    return CellRange(start, end).coordinates;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellCoordinate && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => a1;
}

class CellRange {
  final CellCoordinate start;
  final CellCoordinate end;

  const CellRange(this.start, this.end);

  int get minRow => math.min(start.row, end.row);
  int get maxRow => math.max(start.row, end.row);
  int get minCol => math.min(start.col, end.col);
  int get maxCol => math.max(start.col, end.col);

  bool get isSingleCell => minRow == maxRow && minCol == maxCol;

  bool contains(int row, int col) =>
      row >= minRow && row <= maxRow && col >= minCol && col <= maxCol;

  String toA1() {
    final tl = CellCoordinate(minRow, minCol).a1;
    final br = CellCoordinate(maxRow, maxCol).a1;
    return tl == br ? tl : '$tl:$br';
  }

  List<CellCoordinate> get coordinates {
    final list = <CellCoordinate>[];
    for (var r = minRow; r <= maxRow; r++) {
      for (var c = minCol; c <= maxCol; c++) {
        list.add(CellCoordinate(r, c));
      }
    }
    return list;
  }
}

class CellStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final String? textColorHex;
  final String? fillColorHex;
  final CellAlign? align;
  final NumberFormatType numberFormat;
  final int decimals;

  const CellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.textColorHex,
    this.fillColorHex,
    this.align,
    this.numberFormat = NumberFormatType.general,
    this.decimals = 2,
  });

  CellStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    String? textColorHex,
    bool clearTextColor = false,
    String? fillColorHex,
    bool clearFillColor = false,
    CellAlign? align,
    bool clearAlign = false,
    NumberFormatType? numberFormat,
    int? decimals,
  }) {
    return CellStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      textColorHex:
          clearTextColor ? null : (textColorHex ?? this.textColorHex),
      fillColorHex:
          clearFillColor ? null : (fillColorHex ?? this.fillColorHex),
      align: clearAlign ? null : (align ?? this.align),
      numberFormat: numberFormat ?? this.numberFormat,
      decimals: decimals ?? this.decimals,
    );
  }

  String formatValue(dynamic value, String rawInput) {
    if (value == null) return '';
    if (value is bool) return value ? 'TRUE' : 'FALSE';
    if (value is String) return value;
    if (value is num) {
      final d = value.toDouble();
      if (d.isNaN || d.isInfinite) return '#ERR!';
      switch (numberFormat) {
        case NumberFormatType.general:
          if (d == d.roundToDouble() && d.abs() < 1e15) {
            return d.toInt().toString();
          }
          // Trim trailing zeros up to 4 decimals
          var s = d.toStringAsFixed(4);
          while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
            if (s.endsWith('.')) {
              s = s.substring(0, s.length - 1);
              break;
            }
            s = s.substring(0, s.length - 1);
          }
          return s;
        case NumberFormatType.number:
          return _formatWithCommas(d, decimals);
        case NumberFormatType.currency:
          final neg = d < 0;
          final formatted = _formatWithCommas(d.abs(), decimals);
          return neg ? '-\$$formatted' : '\$$formatted';
        case NumberFormatType.percent:
          return '${(d * 100).toStringAsFixed(decimals)}%';
        case NumberFormatType.scientific:
          return d.toStringAsExponential(decimals);
        case NumberFormatType.date:
          return rawInput;
      }
    }
    return value.toString();
  }

  static String _formatWithCommas(double value, int decimals) {
    final fixed = value.toStringAsFixed(decimals.clamp(0, 8));
    final parts = fixed.split('.');
    final intPart = parts[0];
    final neg = intPart.startsWith('-');
    final digits = neg ? intPart.substring(1) : intPart;
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        sb.write(',');
      }
      sb.write(digits[i]);
    }
    final prefix = neg ? '-${sb.toString()}' : sb.toString();
    return parts.length > 1 ? '$prefix.${parts[1]}' : prefix;
  }

  Map<String, dynamic> toJson() => {
        'bold': bold,
        'italic': italic,
        'underline': underline,
        if (textColorHex != null) 'textColorHex': textColorHex,
        if (fillColorHex != null) 'fillColorHex': fillColorHex,
        if (align != null) 'align': align!.name,
        'numberFormat': numberFormat.name,
        'decimals': decimals,
      };

  factory CellStyle.fromJson(Map<String, dynamic> json) {
    return CellStyle(
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      underline: json['underline'] == true,
      textColorHex: json['textColorHex'] as String?,
      fillColorHex: json['fillColorHex'] as String?,
      align: json['align'] != null
          ? CellAlign.values.firstWhere(
              (a) => a.name == json['align'],
              orElse: () => CellAlign.left,
            )
          : null,
      numberFormat: json['numberFormat'] != null
          ? NumberFormatType.values.firstWhere(
              (n) => n.name == json['numberFormat'],
              orElse: () => NumberFormatType.general,
            )
          : NumberFormatType.general,
      decimals: (json['decimals'] as num?)?.toInt() ?? 2,
    );
  }
}

class SheetCell {
  final String rawInput;
  final dynamic computedValue;
  final String displayValue;
  final CellStyle style;

  const SheetCell({
    this.rawInput = '',
    this.computedValue,
    this.displayValue = '',
    this.style = const CellStyle(),
  });

  bool get isEmpty => rawInput.trim().isEmpty;

  bool get isFormula => rawInput.trim().startsWith('=');

  bool get isError =>
      computedValue is String &&
      (computedValue as String).startsWith('#') &&
      (computedValue as String).endsWith('!');

  bool get isNumeric => computedValue is num;

  SheetCell copyWith({
    String? rawInput,
    dynamic computedValue,
    String? displayValue,
    CellStyle? style,
  }) {
    return SheetCell(
      rawInput: rawInput ?? this.rawInput,
      computedValue:
          computedValue != null ? computedValue : this.computedValue,
      displayValue: displayValue ?? this.displayValue,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toJson() => {
        'rawInput': rawInput,
        'computedValue': computedValue,
        'displayValue': displayValue,
        'style': style.toJson(),
      };

  factory SheetCell.fromJson(Map<String, dynamic> json) {
    return SheetCell(
      rawInput: json['rawInput'] as String? ?? '',
      computedValue: json['computedValue'],
      displayValue: json['displayValue'] as String? ?? '',
      style: json['style'] is Map<String, dynamic>
          ? CellStyle.fromJson(json['style'] as Map<String, dynamic>)
          : const CellStyle(),
    );
  }
}

class SheetChartConfig {
  final String id;
  final String title;
  final ChartType type;
  final String labelRange;
  final String valueRange;
  final String accentHex;

  const SheetChartConfig({
    required this.id,
    required this.title,
    this.type = ChartType.bar,
    required this.labelRange,
    required this.valueRange,
    this.accentHex = '#D040FF',
  });

  SheetChartConfig copyWith({
    String? id,
    String? title,
    ChartType? type,
    String? labelRange,
    String? valueRange,
    String? accentHex,
  }) {
    return SheetChartConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      labelRange: labelRange ?? this.labelRange,
      valueRange: valueRange ?? this.valueRange,
      accentHex: accentHex ?? this.accentHex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'labelRange': labelRange,
        'valueRange': valueRange,
        'accentHex': accentHex,
      };

  factory SheetChartConfig.fromJson(Map<String, dynamic> json) {
    return SheetChartConfig(
      id: json['id'] as String? ?? 'chart_1',
      title: json['title'] as String? ?? 'Chart',
      type: ChartType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ChartType.bar,
      ),
      labelRange: json['labelRange'] as String? ?? 'A2:A7',
      valueRange: json['valueRange'] as String? ?? 'E2:E7',
      accentHex: json['accentHex'] as String? ?? '#D040FF',
    );
  }
}

class ConditionalRule {
  final String id;
  final String range;
  final ConditionalOperator operator;
  final String threshold;
  final String highlightHex;

  const ConditionalRule({
    required this.id,
    required this.range,
    required this.operator,
    required this.threshold,
    this.highlightHex = '#FF5F56',
  });

  bool matches(SheetCell cell) {
    if (cell.isEmpty) return false;
    final val = cell.computedValue;
    final thresholdNum = double.tryParse(threshold.trim());
    switch (operator) {
      case ConditionalOperator.greaterThan:
        if (val is num && thresholdNum != null) {
          return val.toDouble() > thresholdNum;
        }
        return false;
      case ConditionalOperator.lessThan:
        if (val is num && thresholdNum != null) {
          return val.toDouble() < thresholdNum;
        }
        return false;
      case ConditionalOperator.equals:
        if (val is num && thresholdNum != null) {
          return (val.toDouble() - thresholdNum).abs() < 1e-9;
        }
        return cell.displayValue.toLowerCase() ==
                threshold.trim().toLowerCase() ||
            val?.toString().toLowerCase() == threshold.trim().toLowerCase();
      case ConditionalOperator.contains:
        final needle = threshold.trim().toLowerCase();
        if (needle.isEmpty) return false;
        return cell.displayValue.toLowerCase().contains(needle) ||
            (val?.toString().toLowerCase().contains(needle) ?? false);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'range': range,
        'operator': operator.name,
        'threshold': threshold,
        'highlightHex': highlightHex,
      };

  factory ConditionalRule.fromJson(Map<String, dynamic> json) {
    return ConditionalRule(
      id: json['id'] as String? ?? 'rule_1',
      range: json['range'] as String? ?? 'E2:E7',
      operator: ConditionalOperator.values.firstWhere(
        (o) => o.name == json['operator'],
        orElse: () => ConditionalOperator.greaterThan,
      ),
      threshold: json['threshold'] as String? ?? '10000',
      highlightHex: json['highlightHex'] as String? ?? '#FF5F56',
    );
  }
}

class Worksheet {
  final String id;
  String name;
  int rowCount;
  int colCount;
  final Map<int, double> columnWidths;
  int frozenRows;
  final Map<String, SheetCell> cells;
  final List<SheetChartConfig> charts;
  final List<ConditionalRule> conditionalRules;

  Worksheet({
    required this.id,
    required this.name,
    this.rowCount = 50,
    this.colCount = 16,
    Map<int, double>? columnWidths,
    this.frozenRows = 1,
    Map<String, SheetCell>? cells,
    List<SheetChartConfig>? charts,
    List<ConditionalRule>? conditionalRules,
  })  : columnWidths = columnWidths ?? <int, double>{},
        cells = cells ?? <String, SheetCell>{},
        charts = charts ?? <SheetChartConfig>[],
        conditionalRules = conditionalRules ?? <ConditionalRule>[];

  double widthForCol(int col) => columnWidths[col] ?? 124.0;

  SheetCell getCell(int row, int col) {
    final key = CellCoordinate(row, col).a1;
    return cells[key] ?? const SheetCell();
  }

  SheetCell getCellByA1(String a1) {
    final coord = CellCoordinate.tryParse(a1);
    if (coord == null) return const SheetCell();
    return cells[coord.a1] ?? const SheetCell();
  }

  void setCell(int row, int col, SheetCell cell) {
    final key = CellCoordinate(row, col).a1;
    if (cell.rawInput.trim().isEmpty &&
        cell.style.fillColorHex == null &&
        cell.style.textColorHex == null &&
        !cell.style.bold &&
        !cell.style.italic &&
        !cell.style.underline &&
        cell.style.numberFormat == NumberFormatType.general) {
      cells.remove(key);
    } else {
      cells[key] = cell;
    }
    if (row >= rowCount) rowCount = row + 10;
    if (col >= colCount) colCount = col + 4;
  }

  String? matchingHighlightHex(int row, int col, SheetCell cell) {
    for (final rule in conditionalRules) {
      final coords = CellCoordinate.expandRange(rule.range);
      if (coords.any((c) => c.row == row && c.col == col)) {
        if (rule.matches(cell)) {
          return rule.highlightHex;
        }
      }
    }
    return null;
  }

  Worksheet clone({String? newId, String? newName}) {
    return Worksheet(
      id: newId ?? id,
      name: newName ?? name,
      rowCount: rowCount,
      colCount: colCount,
      columnWidths: Map<int, double>.from(columnWidths),
      frozenRows: frozenRows,
      cells: Map<String, SheetCell>.from(cells),
      charts: charts.map((c) => c.copyWith()).toList(),
      conditionalRules: conditionalRules
          .map((r) => ConditionalRule.fromJson(r.toJson()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rowCount': rowCount,
        'colCount': colCount,
        'columnWidths':
            columnWidths.map((k, v) => MapEntry(k.toString(), v)),
        'frozenRows': frozenRows,
        'cells': cells.map((k, v) => MapEntry(k, v.toJson())),
        'charts': charts.map((c) => c.toJson()).toList(),
        'conditionalRules': conditionalRules.map((r) => r.toJson()).toList(),
      };

  factory Worksheet.fromJson(Map<String, dynamic> json) {
    final widths = <int, double>{};
    if (json['columnWidths'] is Map) {
      (json['columnWidths'] as Map).forEach((k, v) {
        final col = int.tryParse(k.toString());
        if (col != null && v is num) {
          widths[col] = v.toDouble();
        }
      });
    }
    final cellMap = <String, SheetCell>{};
    if (json['cells'] is Map) {
      (json['cells'] as Map).forEach((k, v) {
        if (v is Map<String, dynamic>) {
          cellMap[k.toString()] = SheetCell.fromJson(v);
        }
      });
    }
    final chartList = <SheetChartConfig>[];
    if (json['charts'] is List) {
      for (final item in json['charts'] as List) {
        if (item is Map<String, dynamic>) {
          chartList.add(SheetChartConfig.fromJson(item));
        }
      }
    }
    final rulesList = <ConditionalRule>[];
    if (json['conditionalRules'] is List) {
      for (final item in json['conditionalRules'] as List) {
        if (item is Map<String, dynamic>) {
          rulesList.add(ConditionalRule.fromJson(item));
        }
      }
    }
    return Worksheet(
      id: json['id'] as String? ?? 'sheet_1',
      name: json['name'] as String? ?? 'Sheet 1',
      rowCount: (json['rowCount'] as num?)?.toInt() ?? 50,
      colCount: (json['colCount'] as num?)?.toInt() ?? 16,
      columnWidths: widths,
      frozenRows: (json['frozenRows'] as num?)?.toInt() ?? 1,
      cells: cellMap,
      charts: chartList,
      conditionalRules: rulesList,
    );
  }
}

class SpreadsheetWorkbook {
  final String id;
  String title;
  String? filePath;
  WorkbookFormat format;
  final List<Worksheet> sheets;
  int activeSheetIndex;

  SpreadsheetWorkbook({
    required this.id,
    required this.title,
    this.filePath,
    this.format = WorkbookFormat.ods,
    required this.sheets,
    this.activeSheetIndex = 0,
  });

  Worksheet get activeSheet =>
      sheets[activeSheetIndex.clamp(0, math.max(0, sheets.length - 1))];

  SpreadsheetWorkbook clone() {
    return SpreadsheetWorkbook(
      id: id,
      title: title,
      filePath: filePath,
      format: format,
      sheets: sheets.map((s) => s.clone()).toList(),
      activeSheetIndex: activeSheetIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'format': format.name,
        'activeSheetIndex': activeSheetIndex,
        'sheets': sheets.map((s) => s.toJson()).toList(),
      };

  factory SpreadsheetWorkbook.fromJson(Map<String, dynamic> json) {
    final sheetList = <Worksheet>[];
    if (json['sheets'] is List) {
      for (final item in json['sheets'] as List) {
        if (item is Map<String, dynamic>) {
          sheetList.add(Worksheet.fromJson(item));
        }
      }
    }
    if (sheetList.isEmpty) {
      sheetList.add(Worksheet(id: 'sheet_1', name: 'Sheet 1'));
    }
    return SpreadsheetWorkbook(
      id: json['id'] as String? ?? 'wb_1',
      title: json['title'] as String? ?? 'Untitled.ods',
      filePath: json['filePath'] as String?,
      format: WorkbookFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => WorkbookFormat.ods,
      ),
      sheets: sheetList,
      activeSheetIndex: (json['activeSheetIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

class RangeAggregateSummary {
  final int count;
  final int numericCount;
  final double sum;
  final double average;
  final double min;
  final double max;

  const RangeAggregateSummary({
    this.count = 0,
    this.numericCount = 0,
    this.sum = 0,
    this.average = 0,
    this.min = 0,
    this.max = 0,
  });
}
