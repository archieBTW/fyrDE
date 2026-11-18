import 'dart:math' as math;
import '../models/sheet_models.dart';

class _FormulaErrorException implements Exception {
  final String code; // '#CIRC!', '#DIV/0!', '#REF!', '#ERR!'
  const _FormulaErrorException(this.code);
}

class _RangeValue {
  final List<CellCoordinate> coords;
  const _RangeValue(this.coords);
}

enum _TokenType {
  number,
  string,
  ident,
  lparen,
  rparen,
  comma,
  colon,
  op,
  eof,
}

class _Token {
  final _TokenType type;
  final String text;
  const _Token(this.type, this.text);
}

class FormulaEngine {
  static String normalizeFormulaString(String raw) {
    var s = raw.trim();
    if (s.toLowerCase().startsWith('of:=')) {
      s = '=${s.substring(4)}';
    }
    if (!s.startsWith('=')) return raw;
    // Convert OpenFormula bracketed cell references like [.B2:.B6] or [.C2] to B2:B6 / C2
    s = s.replaceAllMapped(
      RegExp(r'\[\.?(\$?[A-Za-z]+\$?\d+)(?::\.?(\$?[A-Za-z]+\$?\d+))?\]'),
      (m) => m.group(2) != null ? '${m.group(1)}:${m.group(2)}' : m.group(1)!,
    );
    return s;
  }

  static void recalculateWorkbook(SpreadsheetWorkbook workbook) {
    for (final sheet in workbook.sheets) {
      recalculateWorksheet(sheet);
    }
  }

  static void recalculateWorksheet(Worksheet sheet) {
    final memo = <String, dynamic>{};
    final visiting = <String>{};

    dynamic evalCellByKey(String a1Key) {
      final normKey = CellCoordinate.tryParse(a1Key)?.a1 ?? a1Key.toUpperCase();
      if (memo.containsKey(normKey)) {
        return memo[normKey];
      }
      if (visiting.contains(normKey)) {
        throw const _FormulaErrorException('#CIRC!');
      }

      final cell = sheet.cells[normKey];
      if (cell == null || cell.rawInput.trim().isEmpty) {
        memo[normKey] = null;
        return null;
      }

      visiting.add(normKey);
      dynamic result;
      try {
        result = _evaluateCellRaw(
          cell.rawInput,
          resolveCell: (coord) => evalCellByKey(coord.a1),
        );
      } on _FormulaErrorException catch (e) {
        result = e.code;
      } catch (_) {
        result = '#ERR!';
      } finally {
        visiting.remove(normKey);
      }

      memo[normKey] = result;
      final formatted = cell.style.formatValue(result, cell.rawInput);
      sheet.cells[normKey] = cell.copyWith(
        computedValue: result,
        displayValue: formatted,
      );
      return result;
    }

    final keys = sheet.cells.keys.toList();
    for (final key in keys) {
      try {
        evalCellByKey(key);
      } on _FormulaErrorException catch (e) {
        final cell = sheet.cells[key];
        if (cell != null) {
          sheet.cells[key] = cell.copyWith(
            computedValue: e.code,
            displayValue: e.code,
          );
        }
      }
    }
  }

  static dynamic evaluateExpression(
    String expression,
    Worksheet sheet,
  ) {
    recalculateWorksheet(sheet);
    try {
      return _evaluateCellRaw(
        expression.startsWith('=') ? expression : '=$expression',
        resolveCell: (coord) {
          final cell = sheet.getCell(coord.row, coord.col);
          final val = cell.computedValue;
          if (val is String && val.startsWith('#') && val.endsWith('!')) {
            throw _FormulaErrorException(val);
          }
          return val;
        },
      );
    } on _FormulaErrorException catch (e) {
      return e.code;
    } catch (_) {
      return '#ERR!';
    }
  }

  static RangeAggregateSummary summarizeRange(
    Worksheet sheet,
    CellRange range,
  ) {
    var count = 0;
    var numericCount = 0;
    var sum = 0.0;
    var minVal = double.infinity;
    var maxVal = double.negativeInfinity;

    for (var r = range.minRow; r <= range.maxRow; r++) {
      for (var c = range.minCol; c <= range.maxCol; c++) {
        final cell = sheet.getCell(r, c);
        if (!cell.isEmpty) {
          count++;
        }
        final v = cell.computedValue;
        if (v is num && !v.isNaN && !v.isInfinite) {
          final d = v.toDouble();
          numericCount++;
          sum += d;
          if (d < minVal) minVal = d;
          if (d > maxVal) maxVal = d;
        }
      }
    }

    if (numericCount == 0) {
      return RangeAggregateSummary(count: count);
    }

    return RangeAggregateSummary(
      count: count,
      numericCount: numericCount,
      sum: sum,
      average: sum / numericCount,
      min: minVal,
      max: maxVal,
    );
  }

  static dynamic _evaluateCellRaw(
    String rawInput, {
    required dynamic Function(CellCoordinate coord) resolveCell,
  }) {
    final normalized = normalizeFormulaString(rawInput);
    final trimmed = normalized.trim();
    if (trimmed.isEmpty) return null;

    if (!trimmed.startsWith('=')) {
      final upper = trimmed.toUpperCase();
      if (upper == 'TRUE') return true;
      if (upper == 'FALSE') return false;
      final numCandidate = double.tryParse(trimmed.replaceAll(',', ''));
      if (numCandidate != null && trimmed.replaceAll(',', '').isNotEmpty) {
        // Avoid converting strings like "2026-11-18" (double.tryParse is null anyway)
        return numCandidate;
      }
      return rawInput;
    }

    final expr = trimmed.substring(1).trim();
    if (expr.isEmpty) return '';

    final tokens = _tokenize(expr);
    final parser = _FormulaParser(tokens, resolveCell);
    final val = parser.parseExpression();
    if (parser.peek().type != _TokenType.eof) {
      throw const _FormulaErrorException('#ERR!');
    }
    if (val is _RangeValue) {
      throw const _FormulaErrorException('#ERR!');
    }
    if (val is num && (val.isNaN || val.isInfinite)) {
      throw const _FormulaErrorException('#ERR!');
    }
    return val;
  }

  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    var i = 0;
    final len = input.length;

    while (i < len) {
      final ch = input[i];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        i++;
        continue;
      }

      if (ch == '(') {
        tokens.add(const _Token(_TokenType.lparen, '('));
        i++;
        continue;
      }
      if (ch == ')') {
        tokens.add(const _Token(_TokenType.rparen, ')'));
        i++;
        continue;
      }
      if (ch == ',' || ch == ';') {
        tokens.add(const _Token(_TokenType.comma, ','));
        i++;
        continue;
      }
      if (ch == ':') {
        tokens.add(const _Token(_TokenType.colon, ':'));
        i++;
        continue;
      }

      // String literal
      if (ch == '"' || ch == "'") {
        final quote = ch;
        i++;
        final sb = StringBuffer();
        while (i < len) {
          if (input[i] == quote) {
            if (i + 1 < len && input[i + 1] == quote) {
              sb.write(quote);
              i += 2;
              continue;
            }
            i++;
            break;
          }
          sb.write(input[i]);
          i++;
        }
        tokens.add(_Token(_TokenType.string, sb.toString()));
        continue;
      }

      // Multi-char operators
      if (i + 1 < len) {
        final two = input.substring(i, i + 2);
        if (two == '<=' ||
            two == '>=' ||
            two == '<>' ||
            two == '!=' ||
            two == '==') {
          tokens.add(_Token(_TokenType.op, two));
          i += 2;
          continue;
        }
      }

      if ('+-*/^&=< >'.contains(ch)) {
        tokens.add(_Token(_TokenType.op, ch));
        i++;
        continue;
      }

      // Number literal
      if (_isDigit(ch) || (ch == '.' && i + 1 < len && _isDigit(input[i + 1]))) {
        final start = i;
        var hasDot = ch == '.';
        i++;
        while (i < len) {
          final c = input[i];
          if (_isDigit(c)) {
            i++;
          } else if (c == '.' && !hasDot) {
            hasDot = true;
            i++;
          } else if ((c == 'e' || c == 'E') && i + 1 < len) {
            i++;
            if (input[i] == '+' || input[i] == '-') i++;
          } else {
            break;
          }
        }
        var numStr = input.substring(start, i);
        // Percentage suffix e.g. 15%
        if (i < len && input[i] == '%') {
          i++;
          final parsed = double.tryParse(numStr);
          if (parsed == null) throw const _FormulaErrorException('#ERR!');
          tokens.add(_Token(_TokenType.number, (parsed / 100.0).toString()));
        } else {
          tokens.add(_Token(_TokenType.number, numStr));
        }
        continue;
      }

      // Identifier or cell reference ($A$1, A1, SUM, AVERAGE, etc.)
      if (_isIdentStart(ch)) {
        final start = i;
        i++;
        while (i < len && _isIdentPart(input[i])) {
          i++;
        }
        tokens.add(_Token(_TokenType.ident, input.substring(start, i)));
        continue;
      }

      throw const _FormulaErrorException('#ERR!');
    }

    tokens.add(const _Token(_TokenType.eof, ''));
    return tokens;
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isIdentStart(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        ch == '_' ||
        ch == r'$';
  }

  static bool _isIdentPart(String ch) {
    return _isIdentStart(ch) || _isDigit(ch) || ch == '.';
  }
}

class _FormulaParser {
  final List<_Token> tokens;
  final dynamic Function(CellCoordinate coord) resolveCell;
  int _pos = 0;

  _FormulaParser(this.tokens, this.resolveCell);

  _Token peek([int offset = 0]) {
    final idx = _pos + offset;
    if (idx >= tokens.length) return tokens.last;
    return tokens[idx];
  }

  _Token next() {
    final tok = peek();
    if (_pos < tokens.length - 1) _pos++;
    return tok;
  }

  dynamic parseExpression() => _parseComparison();

  dynamic _parseComparison() {
    var left = _parseConcat();
    while (peek().type == _TokenType.op &&
        const ['=', '==', '<>', '!=', '<', '<=', '>', '>='].contains(peek().text)) {
      final op = next().text;
      final right = _parseConcat();
      left = _applyComparison(op, left, right);
    }
    return left;
  }

  dynamic _parseConcat() {
    var left = _parseAdditive();
    while (peek().type == _TokenType.op && peek().text == '&') {
      next();
      final right = _parseAdditive();
      left = '${_toString(left)}${_toString(right)}';
    }
    return left;
  }

  dynamic _parseAdditive() {
    var left = _parseMultiplicative();
    while (peek().type == _TokenType.op &&
        (peek().text == '+' || peek().text == '-')) {
      final op = next().text;
      final right = _parseMultiplicative();
      final lNum = _toDouble(left);
      final rNum = _toDouble(right);
      left = op == '+' ? lNum + rNum : lNum - rNum;
    }
    return left;
  }

  dynamic _parseMultiplicative() {
    var left = _parsePower();
    while (peek().type == _TokenType.op &&
        (peek().text == '*' || peek().text == '/')) {
      final op = next().text;
      final right = _parsePower();
      final lNum = _toDouble(left);
      final rNum = _toDouble(right);
      if (op == '*') {
        left = lNum * rNum;
      } else {
        if (rNum.abs() < 1e-15) {
          throw const _FormulaErrorException('#DIV/0!');
        }
        left = lNum / rNum;
      }
    }
    return left;
  }

  dynamic _parsePower() {
    var left = _parseUnary();
    if (peek().type == _TokenType.op && peek().text == '^') {
      next();
      final right = _parsePower();
      left = math.pow(_toDouble(left), _toDouble(right)).toDouble();
    }
    return left;
  }

  dynamic _parseUnary() {
    if (peek().type == _TokenType.op &&
        (peek().text == '+' || peek().text == '-')) {
      final op = next().text;
      final operand = _parseUnary();
      final d = _toDouble(operand);
      return op == '-' ? -d : d;
    }
    return _parsePrimary();
  }

  dynamic _parsePrimary() {
    final tok = peek();
    if (tok.type == _TokenType.number) {
      next();
      final parsed = double.tryParse(tok.text);
      if (parsed == null) throw const _FormulaErrorException('#ERR!');
      return parsed;
    }

    if (tok.type == _TokenType.string) {
      next();
      return tok.text;
    }

    if (tok.type == _TokenType.lparen) {
      next();
      final inner = parseExpression();
      if (peek().type != _TokenType.rparen) {
        throw const _FormulaErrorException('#ERR!');
      }
      next();
      return inner;
    }

    if (tok.type == _TokenType.ident) {
      next();
      final name = tok.text;
      final upper = name.toUpperCase();

      // Function call
      if (peek().type == _TokenType.lparen) {
        next(); // consume '('
        final args = <dynamic>[];
        if (peek().type != _TokenType.rparen) {
          while (true) {
            args.add(_parseFunctionArg());
            if (peek().type == _TokenType.comma) {
              next();
              continue;
            }
            break;
          }
        }
        if (peek().type != _TokenType.rparen) {
          throw const _FormulaErrorException('#ERR!');
        }
        next(); // consume ')'
        return _evalFunction(upper, args);
      }

      // Range A1:B10
      if (peek().type == _TokenType.colon) {
        next(); // consume ':'
        final endTok = next();
        if (endTok.type != _TokenType.ident) {
          throw const _FormulaErrorException('#REF!');
        }
        final startCoord = CellCoordinate.tryParse(name);
        final endCoord = CellCoordinate.tryParse(endTok.text);
        if (startCoord == null || endCoord == null) {
          throw const _FormulaErrorException('#REF!');
        }
        return _RangeValue(CellRange(startCoord, endCoord).coordinates);
      }

      if (upper == 'TRUE') return true;
      if (upper == 'FALSE') return false;
      if (upper == 'PI') return math.pi;

      final coord = CellCoordinate.tryParse(name);
      if (coord == null) {
        throw const _FormulaErrorException('#REF!');
      }
      final cellVal = resolveCell(coord);
      if (cellVal is String && cellVal.startsWith('#') && cellVal.endsWith('!')) {
        throw _FormulaErrorException(cellVal);
      }
      return cellVal ?? 0.0;
    }

    throw const _FormulaErrorException('#ERR!');
  }

  dynamic _parseFunctionArg() {
    // Check if it's a range like A1:B5 before full expression
    if (peek().type == _TokenType.ident &&
        peek(1).type == _TokenType.colon &&
        peek(2).type == _TokenType.ident) {
      final startTok = next();
      next(); // ':'
      final endTok = next();
      final startCoord = CellCoordinate.tryParse(startTok.text);
      final endCoord = CellCoordinate.tryParse(endTok.text);
      if (startCoord == null || endCoord == null) {
        throw const _FormulaErrorException('#REF!');
      }
      return _RangeValue(CellRange(startCoord, endCoord).coordinates);
    }
    return parseExpression();
  }

  List<double> _collectNumbers(List<dynamic> args) {
    final nums = <double>[];
    for (final arg in args) {
      if (arg is _RangeValue) {
        for (final coord in arg.coords) {
          final v = resolveCell(coord);
          if (v is String && v.startsWith('#') && v.endsWith('!')) {
            throw _FormulaErrorException(v);
          }
          if (v is num) {
            nums.add(v.toDouble());
          } else if (v is bool) {
            nums.add(v ? 1.0 : 0.0);
          }
        }
      } else if (arg is num) {
        nums.add(arg.toDouble());
      } else if (arg is bool) {
        nums.add(arg ? 1.0 : 0.0);
      } else if (arg is String && arg.trim().isNotEmpty) {
        final p = double.tryParse(arg.trim());
        if (p != null) nums.add(p);
      }
    }
    return nums;
  }

  dynamic _evalFunction(String func, List<dynamic> args) {
    switch (func) {
      case 'SUM':
        final nums = _collectNumbers(args);
        return nums.fold<double>(0.0, (a, b) => a + b);

      case 'AVERAGE':
      case 'AVG':
        final nums = _collectNumbers(args);
        if (nums.isEmpty) throw const _FormulaErrorException('#DIV/0!');
        final sum = nums.fold<double>(0.0, (a, b) => a + b);
        return sum / nums.length;

      case 'MIN':
        final nums = _collectNumbers(args);
        if (nums.isEmpty) return 0.0;
        return nums.reduce(math.min);

      case 'MAX':
        final nums = _collectNumbers(args);
        if (nums.isEmpty) return 0.0;
        return nums.reduce(math.max);

      case 'COUNT':
        final nums = _collectNumbers(args);
        return nums.length.toDouble();

      case 'COUNTA':
        var count = 0;
        for (final arg in args) {
          if (arg is _RangeValue) {
            for (final coord in arg.coords) {
              final v = resolveCell(coord);
              if (v != null && v.toString().trim().isNotEmpty) count++;
            }
          } else if (arg != null && arg.toString().trim().isNotEmpty) {
            count++;
          }
        }
        return count.toDouble();

      case 'MEDIAN':
        final nums = _collectNumbers(args)..sort();
        if (nums.isEmpty) return 0.0;
        final mid = nums.length ~/ 2;
        if (nums.length.isOdd) return nums[mid];
        return (nums[mid - 1] + nums[mid]) / 2.0;

      case 'STDEV':
      case 'STDEV.S':
        final nums = _collectNumbers(args);
        if (nums.length < 2) throw const _FormulaErrorException('#DIV/0!');
        final mean = nums.fold<double>(0.0, (a, b) => a + b) / nums.length;
        final variance = nums.fold<double>(
              0.0,
              (acc, x) => acc + (x - mean) * (x - mean),
            ) /
            (nums.length - 1);
        return math.sqrt(variance);

      case 'IF':
        if (args.length < 2) throw const _FormulaErrorException('#ERR!');
        final cond = _toBool(args[0]);
        if (cond) return args[1];
        return args.length >= 3 ? args[2] : false;

      case 'AND':
        if (args.isEmpty) return true;
        for (final arg in args) {
          if (arg is _RangeValue) {
            for (final coord in arg.coords) {
              final v = resolveCell(coord);
              if (v != null && !_toBool(v)) return false;
            }
          } else if (!_toBool(arg)) {
            return false;
          }
        }
        return true;

      case 'OR':
        for (final arg in args) {
          if (arg is _RangeValue) {
            for (final coord in arg.coords) {
              final v = resolveCell(coord);
              if (v != null && _toBool(v)) return true;
            }
          } else if (_toBool(arg)) {
            return true;
          }
        }
        return false;

      case 'NOT':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        return !_toBool(args[0]);

      case 'ROUND':
        if (args.isEmpty) throw const _FormulaErrorException('#ERR!');
        final val = _toDouble(args[0]);
        final digits = args.length >= 2 ? _toDouble(args[1]).round() : 0;
        final factor = math.pow(10.0, digits).toDouble();
        return (val * factor).roundToDouble() / factor;

      case 'FLOOR':
        if (args.isEmpty) throw const _FormulaErrorException('#ERR!');
        final val = _toDouble(args[0]);
        final sig = args.length >= 2 ? _toDouble(args[1]) : 1.0;
        if (sig == 0) throw const _FormulaErrorException('#DIV/0!');
        return (val / sig).floorToDouble() * sig;

      case 'CEILING':
      case 'CEIL':
        if (args.isEmpty) throw const _FormulaErrorException('#ERR!');
        final val = _toDouble(args[0]);
        final sig = args.length >= 2 ? _toDouble(args[1]) : 1.0;
        if (sig == 0) throw const _FormulaErrorException('#DIV/0!');
        return (val / sig).ceilToDouble() * sig;

      case 'ABS':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        return _toDouble(args[0]).abs();

      case 'SQRT':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        final v = _toDouble(args[0]);
        if (v < 0) throw const _FormulaErrorException('#ERR!');
        return math.sqrt(v);

      case 'POW':
      case 'POWER':
        if (args.length != 2) throw const _FormulaErrorException('#ERR!');
        return math.pow(_toDouble(args[0]), _toDouble(args[1])).toDouble();

      case 'MOD':
        if (args.length != 2) throw const _FormulaErrorException('#ERR!');
        final d = _toDouble(args[1]);
        if (d.abs() < 1e-15) throw const _FormulaErrorException('#DIV/0!');
        return _toDouble(args[0]) % d;

      case 'LEN':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        return _toString(args[0]).length.toDouble();

      case 'UPPER':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        return _toString(args[0]).toUpperCase();

      case 'LOWER':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        return _toString(args[0]).toLowerCase();

      case 'TRIM':
        if (args.length != 1) throw const _FormulaErrorException('#ERR!');
        return _toString(args[0]).trim();

      case 'CONCAT':
      case 'CONCATENATE':
        final sb = StringBuffer();
        for (final arg in args) {
          if (arg is _RangeValue) {
            for (final coord in arg.coords) {
              sb.write(_toString(resolveCell(coord)));
            }
          } else {
            sb.write(_toString(arg));
          }
        }
        return sb.toString();

      case 'NPV':
        if (args.length < 2) throw const _FormulaErrorException('#ERR!');
        final rate = _toDouble(args[0]);
        final cashflows = _collectNumbers(args.sublist(1));
        var npv = 0.0;
        for (var i = 0; i < cashflows.length; i++) {
          npv += cashflows[i] / math.pow(1.0 + rate, i + 1);
        }
        return npv;

      default:
        throw const _FormulaErrorException('#ERR!');
    }
  }

  bool _applyComparison(String op, dynamic left, dynamic right) {
    if (left is num && right is num) {
      final l = left.toDouble();
      final r = right.toDouble();
      switch (op) {
        case '=':
        case '==':
          return (l - r).abs() < 1e-12;
        case '<>':
        case '!=':
          return (l - r).abs() >= 1e-12;
        case '<':
          return l < r;
        case '<=':
          return l <= r;
        case '>':
          return l > r;
        case '>=':
          return l >= r;
      }
    }
    final ls = _toString(left).toLowerCase();
    final rs = _toString(right).toLowerCase();
    final cmp = ls.compareTo(rs);
    switch (op) {
      case '=':
      case '==':
        return cmp == 0;
      case '<>':
      case '!=':
        return cmp != 0;
      case '<':
        return cmp < 0;
      case '<=':
        return cmp <= 0;
      case '>':
        return cmp > 0;
      case '>=':
        return cmp >= 0;
      default:
        return false;
    }
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is bool) return val ? 1.0 : 0.0;
    if (val is String) {
      if (val.startsWith('#') && val.endsWith('!')) {
        throw _FormulaErrorException(val);
      }
      if (val.trim().isEmpty) return 0.0;
      final parsed = double.tryParse(val.trim().replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
    throw const _FormulaErrorException('#ERR!');
  }

  bool _toBool(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final u = val.trim().toUpperCase();
      if (u == 'TRUE' || u == '1') return true;
      if (u == 'FALSE' || u == '0' || u.isEmpty) return false;
    }
    return false;
  }

  String _toString(dynamic val) {
    if (val == null) return '';
    if (val is bool) return val ? 'TRUE' : 'FALSE';
    if (val is num) {
      if (val == val.roundToDouble() && val.abs() < 1e15) {
        return val.toInt().toString();
      }
      return val.toString();
    }
    return val.toString();
  }
}
