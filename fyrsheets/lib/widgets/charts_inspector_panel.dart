import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/sheet_models.dart';
import '../state/sheets_controller.dart';

class ChartsInspectorPanel extends StatelessWidget {
  const ChartsInspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SheetsController>();
    if (!ctrl.showRightPanel) return const SizedBox.shrink();

    return Container(
      width: 315,
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          // Top Segmented Tab Switcher
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _tabPill(
                  ctrl: ctrl,
                  tab: RightInspectorTab.charts,
                  icon: Icons.bar_chart_rounded,
                  label: 'Charts',
                ),
                const SizedBox(width: 6),
                _tabPill(
                  ctrl: ctrl,
                  tab: RightInspectorTab.style,
                  icon: Icons.tune_rounded,
                  label: 'Inspector',
                ),
                const SizedBox(width: 6),
                _tabPill(
                  ctrl: ctrl,
                  tab: RightInspectorTab.rules,
                  icon: Icons.rule_rounded,
                  label: 'Rules',
                ),
              ],
            ),
          ),

          // Active Tab Body
          Expanded(
            child: switch (ctrl.activeInspectorTab) {
              RightInspectorTab.charts => _buildChartsTab(context, ctrl),
              RightInspectorTab.style => _buildInspectorTab(context, ctrl),
              RightInspectorTab.rules => _buildRulesTab(context, ctrl),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required SheetsController ctrl,
    required RightInspectorTab tab,
    required IconData icon,
    required String label,
  }) {
    final active = ctrl.activeInspectorTab == tab;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => ctrl.toggleRightPanel(tab),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.2)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? FyrTheme.accentColor : FyrTheme.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartsTab(BuildContext context, SheetsController ctrl) {
    final sheet = ctrl.activeSheet;
    final charts = sheet.charts;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LIVE WORKSHEET CHARTS',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: FyrTheme.textColorMuted,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () => ctrl.addChart(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: FyrTheme.accentColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '+ Add Chart',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.accentColor,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (charts.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.insights_rounded,
                  size: 28,
                  color: FyrTheme.textColorMuted,
                ),
                const SizedBox(height: 8),
                Text(
                  'No charts on this sheet yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ),
          ),
        for (final chart in charts) ...[
          _buildChartCard(ctrl, sheet, chart),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildChartCard(
    SheetsController ctrl,
    Worksheet sheet,
    SheetChartConfig chart,
  ) {
    final labelCoords = CellCoordinate.expandRange(chart.labelRange);
    final valueCoords = CellCoordinate.expandRange(chart.valueRange);
    final count = math.min(labelCoords.length, valueCoords.length);

    final labels = <String>[];
    final values = <double>[];
    for (var i = 0; i < count; i++) {
      final lCell = sheet.getCell(labelCoords[i].row, labelCoords[i].col);
      final vCell = sheet.getCell(valueCoords[i].row, valueCoords[i].col);
      final lText = lCell.displayValue.isNotEmpty
          ? lCell.displayValue
          : labelCoords[i].a1;
      final vNum = vCell.computedValue is num
          ? (vCell.computedValue as num).toDouble()
          : (double.tryParse(vCell.displayValue) ?? 0.0);
      labels.add(lText);
      values.add(vNum);
    }

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  chart.title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  chart.valueRange,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: FyrTheme.accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Chart Type Selector Row
          Row(
            children: [
              for (final t in ChartType.values)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => ctrl.updateChart(chart.copyWith(type: t)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: chart.type == t
                            ? FyrTheme.accentColor.withValues(alpha: 0.22)
                            : FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: chart.type == t
                              ? FyrTheme.accentColor
                              : FyrTheme.dividerColor,
                        ),
                      ),
                      child: Text(
                        t.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: chart.type == t
                              ? FyrTheme.accentColor
                              : FyrTheme.textColorMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // CustomPaint Chart Canvas
          SizedBox(
            height: 175,
            width: double.infinity,
            child: CustomPaint(
              painter: _SheetChartPainter(
                type: chart.type,
                labels: labels,
                values: values,
                accentColor: FyrTheme.accentColor,
                textColor: FyrTheme.textColorMuted,
                gridColor: FyrTheme.dividerColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Legend / Breakdown Rows
          for (var i = 0; i < math.min(labels.length, 6); i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _paletteColor(i, FyrTheme.accentColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: FyrTheme.textColorMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    const CellStyle(
                      numberFormat: NumberFormatType.currency,
                    ).formatValue(values[i], ''),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInspectorTab(BuildContext context, SheetsController ctrl) {
    final coord = ctrl.activeCell;
    final cell = ctrl.currentCell;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'ACTIVE CELL TELEMETRY',
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Column(
            children: [
              _kvRow('Coordinate', coord.a1),
              _kvRow(
                'Raw Input',
                cell.rawInput.isEmpty ? '(empty)' : cell.rawInput,
              ),
              _kvRow(
                'Evaluated',
                cell.computedValue?.toString() ?? '(none)',
              ),
              _kvRow(
                'Display Text',
                cell.displayValue.isEmpty ? '(empty)' : cell.displayValue,
              ),
              _kvRow('Format', cell.style.numberFormat.name.toUpperCase()),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'SUPPORTED FORMULA ENGINE FUNCTIONS',
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: const [
            'SUM',
            'AVERAGE',
            'MIN',
            'MAX',
            'COUNT',
            'COUNTA',
            'MEDIAN',
            'STDEV',
            'IF',
            'AND',
            'OR',
            'NOT',
            'ROUND',
            'FLOOR',
            'CEILING',
            'ABS',
            'SQRT',
            'POW',
            'MOD',
            'LEN',
            'UPPER',
            'LOWER',
            'CONCAT',
            'NPV',
          ]
              .map(
                (fn) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: FyrTheme.dividerColor),
                  ),
                  child: Text(
                    fn,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: FyrTheme.accentColor,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRulesTab(BuildContext context, SheetsController ctrl) {
    final rules = ctrl.activeSheet.conditionalRules;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CONDITIONAL HIGHLIGHT RULES',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: FyrTheme.textColorMuted,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () {
                ctrl.addConditionalRule(
                  ConditionalRule(
                    id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
                    range: ctrl.selectionRange.toA1(),
                    operator: ConditionalOperator.greaterThan,
                    threshold: '1000',
                    highlightHex: '#27C93F',
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: FyrTheme.accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '+ Add Rule',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.accentColor,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final r in rules)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: FyrTheme.accentColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r.range} • ${r.operator.name} ${r.threshold}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 15,
                    color: FyrTheme.textColorMuted,
                  ),
                  onPressed: () => ctrl.removeConditionalRule(r.id),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kvRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              val,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _paletteColor(int index, Color accent) {
    final palette = [
      accent,
      const Color(0xFF00E5FF),
      const Color(0xFF27C93F),
      const Color(0xFFFFBD2E),
      const Color(0xFFFF5F56),
      const Color(0xFF9D4EDD),
    ];
    return palette[index % palette.length];
  }
}

class _SheetChartPainter extends CustomPainter {
  final ChartType type;
  final List<String> labels;
  final List<double> values;
  final Color accentColor;
  final Color textColor;
  final Color gridColor;

  _SheetChartPainter({
    required this.type,
    required this.labels,
    required this.values,
    required this.accentColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.fold<double>(
      1.0,
      (m, v) => math.max(m, v.abs()),
    );

    if (type == ChartType.pie) {
      _paintDonut(canvas, size);
      return;
    }

    const leftPad = 8.0;
    const rightPad = 8.0;
    const topPad = 12.0;
    const bottomPad = 22.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    // Horizontal grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartH * (i / 3.0);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );
    }

    final n = values.length;
    if (type == ChartType.bar) {
      final slotW = chartW / n;
      final barW = math.min(28.0, slotW * 0.62);

      for (var i = 0; i < n; i++) {
        final norm = (values[i].clamp(0.0, maxVal)) / maxVal;
        final barH = math.max(3.0, chartH * norm);
        final cx = leftPad + slotW * (i + 0.5);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            cx - barW / 2,
            topPad + chartH - barH,
            barW,
            barH,
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        );
        final barPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ChartsInspectorPanel._paletteColor(i, accentColor),
              ChartsInspectorPanel._paletteColor(i, accentColor)
                  .withValues(alpha: 0.45),
            ],
          ).createShader(rect.outerRect);
        canvas.drawRRect(rect, barPaint);
      }
    } else {
      // Line or Area
      final points = <Offset>[];
      for (var i = 0; i < n; i++) {
        final norm = (values[i].clamp(0.0, maxVal)) / maxVal;
        final x = n == 1 ? leftPad + chartW / 2 : leftPad + chartW * (i / (n - 1));
        final y = topPad + chartH * (1.0 - norm);
        points.add(Offset(x, y));
      }

      if (type == ChartType.area && points.length >= 2) {
        final areaPath = Path()..moveTo(points.first.dx, topPad + chartH);
        for (final pt in points) {
          areaPath.lineTo(pt.dx, pt.dy);
        }
        areaPath.lineTo(points.last.dx, topPad + chartH);
        areaPath.close();
        final fillPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accentColor.withValues(alpha: 0.45),
              accentColor.withValues(alpha: 0.03),
            ],
          ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH));
        canvas.drawPath(areaPath, fillPaint);
      }

      final linePath = Path();
      for (var i = 0; i < points.length; i++) {
        if (i == 0) {
          linePath.moveTo(points[i].dx, points[i].dy);
        } else {
          linePath.lineTo(points[i].dx, points[i].dy);
        }
      }
      final linePaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(linePath, linePaint);

      final dotPaint = Paint()..color = const Color(0xFF00E5FF);
      for (final pt in points) {
        canvas.drawCircle(pt, 3.6, dotPaint);
      }
    }
  }

  void _paintDonut(Canvas canvas, Size size) {
    final total = values.fold<double>(0.0, (a, b) => a + b.abs());
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;
    var startAngle = -math.pi / 2;

    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i].abs() / total) * math.pi * 2;
      final paint = Paint()
        ..color = ChartsInspectorPanel._paletteColor(i, accentColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep - 0.03,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SheetChartPainter oldDelegate) => true;
}
