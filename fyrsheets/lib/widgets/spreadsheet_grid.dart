import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/sheet_models.dart';
import '../state/sheets_controller.dart';

class SpreadsheetGrid extends StatefulWidget {
  const SpreadsheetGrid({super.key});

  @override
  State<SpreadsheetGrid> createState() => _SpreadsheetGridState();
}

class _SpreadsheetGridState extends State<SpreadsheetGrid> {
  final ScrollController _hHeaderScroll = ScrollController();
  final ScrollController _hBodyScroll = ScrollController();
  final ScrollController _vHeaderScroll = ScrollController();
  final ScrollController _vBodyScroll = ScrollController();

  bool _syncingH = false;
  bool _syncingV = false;

  static const double _rowHeaderWidth = 46.0;
  static const double _colHeaderHeight = 28.0;
  static const double _rowHeight = 28.0;

  @override
  void initState() {
    super.initState();
    _hBodyScroll.addListener(() {
      if (_syncingH) return;
      _syncingH = true;
      if (_hHeaderScroll.hasClients) {
        _hHeaderScroll.jumpTo(_hBodyScroll.offset);
      }
      _syncingH = false;
    });
    _hHeaderScroll.addListener(() {
      if (_syncingH) return;
      _syncingH = true;
      if (_hBodyScroll.hasClients) {
        _hBodyScroll.jumpTo(_hHeaderScroll.offset);
      }
      _syncingH = false;
    });
    _vBodyScroll.addListener(() {
      if (_syncingV) return;
      _syncingV = true;
      if (_vHeaderScroll.hasClients) {
        _vHeaderScroll.jumpTo(_vBodyScroll.offset);
      }
      _syncingV = false;
    });
    _vHeaderScroll.addListener(() {
      if (_syncingV) return;
      _syncingV = true;
      if (_vBodyScroll.hasClients) {
        _vBodyScroll.jumpTo(_vHeaderScroll.offset);
      }
      _syncingV = false;
    });
  }

  @override
  void dispose() {
    _hHeaderScroll.dispose();
    _hBodyScroll.dispose();
    _vHeaderScroll.dispose();
    _vBodyScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SheetsController>();
    final sheet = ctrl.activeSheet;
    final selRange = ctrl.selectionRange;
    final active = ctrl.activeCell;

    return Container(
      color: FyrTheme.contentColor,
      child: Column(
        children: [
          // Top Sticky Row: Corner Box + Column Headers (A, B, C...)
          SizedBox(
            height: _colHeaderHeight,
            child: Row(
              children: [
                // Top-left select-all corner cell
                GestureDetector(
                  onTap: () {
                    ctrl.selectCell(const CellCoordinate(0, 0));
                    ctrl.updateDragSelection(
                      CellCoordinate(sheet.rowCount - 1, sheet.colCount - 1),
                    );
                  },
                  child: Container(
                    width: _rowHeaderWidth,
                    height: _colHeaderHeight,
                    decoration: BoxDecoration(
                      color: FyrTheme.surfaceColor,
                      border: Border(
                        right: BorderSide(color: FyrTheme.dividerColor),
                        bottom: BorderSide(color: FyrTheme.dividerColor),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.signal_cellular_4_bar_rounded,
                        size: 10,
                        color: FyrTheme.textColorMuted.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
                // Scrollable Column Headers
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hHeaderScroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(sheet.colCount, (c) {
                        final colSelected =
                            c >= selRange.minCol && c <= selRange.maxCol;
                        final w = sheet.widthForCol(c);
                        return _buildColHeader(ctrl, sheet, c, w, colSelected);
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Body: Sticky Row Numbers + 2D Cell Grid
          Expanded(
            child: Row(
              children: [
                // Sticky Row Headers (1, 2, 3...)
                SizedBox(
                  width: _rowHeaderWidth,
                  child: SingleChildScrollView(
                    controller: _vHeaderScroll,
                    child: Column(
                      children: List.generate(sheet.rowCount, (r) {
                        final rowSelected =
                            r >= selRange.minRow && r <= selRange.maxRow;
                        return GestureDetector(
                          onTap: () {
                            ctrl.selectCell(CellCoordinate(r, 0));
                            ctrl.updateDragSelection(
                              CellCoordinate(r, sheet.colCount - 1),
                            );
                          },
                          child: Container(
                            width: _rowHeaderWidth,
                            height: _rowHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: rowSelected
                                  ? FyrTheme.accentColor.withValues(alpha: 0.2)
                                  : FyrTheme.surfaceColor,
                              border: Border(
                                right: BorderSide(color: FyrTheme.dividerColor),
                                bottom: BorderSide(
                                  color: FyrTheme.dividerColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            child: Text(
                              '${r + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: rowSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: rowSelected
                                    ? FyrTheme.accentColor
                                    : FyrTheme.textColorMuted,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                // 2D Scrollable Cell Canvas
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hBodyScroll,
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _vBodyScroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(sheet.rowCount, (r) {
                          return Row(
                            children: List.generate(sheet.colCount, (c) {
                              final w = sheet.widthForCol(c);
                              final cell = sheet.getCell(r, c);
                              final isActive =
                                  active.row == r && active.col == c;
                              final inRange = selRange.contains(r, c);
                              final condHex =
                                  sheet.matchingHighlightHex(r, c, cell);
                              return _buildGridCell(
                                ctrl: ctrl,
                                row: r,
                                col: c,
                                width: w,
                                cell: cell,
                                isActive: isActive,
                                inRange: inRange,
                                condHighlightHex: condHex,
                              );
                            }),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColHeader(
    SheetsController ctrl,
    Worksheet sheet,
    int col,
    double width,
    bool selected,
  ) {
    final label = CellCoordinate.colToLetters(col);
    return SizedBox(
      width: width,
      height: _colHeaderHeight,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              ctrl.selectCell(CellCoordinate(0, col));
              ctrl.updateDragSelection(
                CellCoordinate(sheet.rowCount - 1, col),
              );
            },
            child: Container(
              width: width,
              height: _colHeaderHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? FyrTheme.accentColor.withValues(alpha: 0.2)
                    : FyrTheme.surfaceColor,
                border: Border(
                  right: BorderSide(color: FyrTheme.dividerColor),
                  bottom: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? FyrTheme.accentColor
                      : FyrTheme.textColorMuted,
                ),
              ),
            ),
          ),
          // Drag handle on right edge to resize column
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  ctrl.setColumnWidth(col, width + details.delta.dx);
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell({
    required SheetsController ctrl,
    required int row,
    required int col,
    required double width,
    required SheetCell cell,
    required bool isActive,
    required bool inRange,
    required String? condHighlightHex,
  }) {
    final style = cell.style;
    Color bgColor = Colors.transparent;
    if (style.fillColorHex != null) {
      bgColor = _parseHex(style.fillColorHex!);
    }
    if (condHighlightHex != null) {
      bgColor = _parseHex(condHighlightHex).withValues(alpha: 0.22);
    }
    if (inRange && !isActive) {
      bgColor = Color.alphaBlend(
        FyrTheme.accentColor.withValues(alpha: 0.14),
        bgColor == Colors.transparent ? FyrTheme.contentColor : bgColor,
      );
    }

    Color textColor = FyrTheme.textColor;
    if (cell.isError) {
      textColor = const Color(0xFFFF5F56);
    } else if (style.textColorHex != null) {
      textColor = _parseHex(style.textColorHex!);
    } else if (condHighlightHex != null) {
      textColor = _parseHex(condHighlightHex);
    }

    final align = style.align ??
        (cell.isNumeric ? CellAlign.right : CellAlign.left);
    final alignment = switch (align) {
      CellAlign.left => Alignment.centerLeft,
      CellAlign.center => Alignment.center,
      CellAlign.right => Alignment.centerRight,
    };

    return GestureDetector(
      onTap: () => ctrl.selectCell(CellCoordinate(row, col)),
      onDoubleTap: () => ctrl.selectCell(
        CellCoordinate(row, col),
        startInlineEdit: true,
      ),
      child: Container(
        width: width,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: alignment,
        decoration: BoxDecoration(
          color: bgColor,
          border: isActive
              ? Border.all(color: FyrTheme.accentColor, width: 1.8)
              : Border(
                  right: BorderSide(
                    color: FyrTheme.dividerColor.withValues(alpha: 0.45),
                  ),
                  bottom: BorderSide(
                    color: FyrTheme.dividerColor.withValues(alpha: 0.45),
                  ),
                ),
        ),
        child: isActive && ctrl.isEditingInline
            ? TextField(
                controller: ctrl.formulaController,
                autofocus: true,
                style: TextStyle(
                  fontSize: 12,
                  color: FyrTheme.textColor,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (val) {
                  ctrl.commitFormulaBarValue(val);
                  ctrl.moveSelection(1, 0);
                },
              )
            : Row(
                children: [
                  if (cell.isFormula && !cell.isError)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: FyrTheme.accentColor.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      cell.displayValue,
                      textAlign: switch (align) {
                        CellAlign.left => TextAlign.left,
                        CellAlign.center => TextAlign.center,
                        CellAlign.right => TextAlign.right,
                      },
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            style.bold ? FontWeight.w700 : FontWeight.w400,
                        fontStyle: style.italic
                            ? FontStyle.italic
                            : FontStyle.normal,
                        decoration: style.underline
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    return FyrTheme.accentColor;
  }
}
