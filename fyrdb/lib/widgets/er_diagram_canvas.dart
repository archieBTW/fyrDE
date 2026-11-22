import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';

class ErDiagramCanvas extends StatelessWidget {
  const ErDiagramCanvas({super.key});

  static const double _cardWidth = 265.0;
  static const double _headerHeight = 32.0;
  static const double _rowHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final schemas = ctrl.activeSchemas;
    final accent = FyrTheme.accentColor;

    var fkCount = 0;
    for (final t in schemas) {
      for (final c in t.columns) {
        if (c.isForeignKey) fkCount++;
      }
    }

    return Column(
      children: [
        // ER Diagram Toolbar
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(Icons.hub_rounded, size: 15, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'ER Schema Diagram — ${ctrl.activeConnection?.name ?? 'Disconnected'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _legendChip('PK', 'Primary Key', const Color(0xFFFBBF24)),
              const SizedBox(width: 8),
              _legendChip(
                'FK',
                '$fkCount FKs',
                const Color(0xFF38BDF8),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: ctrl.autoLayoutErDiagram,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FyrTheme.dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 13,
                        color: accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Auto-Layout',
                        style: TextStyle(
                          fontSize: 11,
                          color: FyrTheme.textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Interactive Canvas
        Expanded(
          child: Container(
            color: const Color(0xFF070709),
            child: ClipRect(
              child: Stack(
                children: [
                  // Background grid & Bezier Foreign Key Connectors
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ErDiagramPainter(
                        schemas: schemas,
                        accentColor: accent,
                        selectedTableName: ctrl.selectedTableName ?? '',
                      ),
                    ),
                  ),
                  if (schemas.isEmpty)
                    Center(
                      child: Text(
                        'No tables in this schema yet. Create tables in the SQL Editor to inspect ER relationships.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                    ),
                  // Draggable Table Entity Cards
                  for (final table in schemas)
                    Positioned(
                      left: table.erPosition.dx,
                      top: table.erPosition.dy,
                      child: GestureDetector(
                        onTap: () => ctrl.selectTable(table.name),
                        onPanUpdate: (details) {
                          ctrl.updateTableErPosition(
                            table.name,
                            table.erPosition + details.delta,
                          );
                        },
                        child: _buildEntityNode(
                          ctrl,
                          table,
                          accent,
                          ctrl.selectedTableName == table.name,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendChip(String badge, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            badge,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
        ),
      ],
    );
  }

  Widget _buildEntityNode(
    DbController ctrl,
    DbTableSchema table,
    Color accent,
    bool isSelected,
  ) {
    final headerColor = table.isView ? const Color(0xFF38BDF8) : accent;

    return Container(
      width: _cardWidth,
      decoration: BoxDecoration(
        color: const Color(0xFF141318),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? headerColor
              : headerColor.withValues(alpha: 0.38),
          width: isSelected ? 1.8 : 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  headerColor.withValues(alpha: 0.32),
                  headerColor.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(color: headerColor.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  table.isView
                      ? Icons.visibility_rounded
                      : Icons.table_chart_rounded,
                  size: 13.5,
                  color: headerColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    table.name,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${table.rows.length} rows',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          // Columns
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final col in table.columns)
                  SizedBox(
                    height: _rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Row(
                        children: [
                          if (col.isPrimaryKey)
                            _keyBadge('PK', const Color(0xFFFBBF24))
                          else if (col.isForeignKey)
                            _keyBadge('FK', const Color(0xFF38BDF8))
                          else
                            const SizedBox(width: 24),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              col.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight:
                                    col.isPrimaryKey || col.isForeignKey
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            col.dataType,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              color: Colors.white54,
                            ),
                          ),
                        ],
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

  Widget _keyBadge(String text, Color color) {
    return Container(
      width: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ErDiagramPainter extends CustomPainter {
  final List<DbTableSchema> schemas;
  final Color accentColor;
  final String selectedTableName;

  const _ErDiagramPainter({
    required this.schemas,
    required this.accentColor,
    required this.selectedTableName,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Subtle dot grid
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const step = 28.0;
    for (double x = 14; x < size.width; x += step) {
      for (double y = 14; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Foreign Key Bezier Connectors
    final tableMap = <String, DbTableSchema>{
      for (final t in schemas) t.name.toLowerCase(): t,
    };

    for (final srcTable in schemas) {
      for (var cIdx = 0; cIdx < srcTable.columns.length; cIdx++) {
        final col = srcTable.columns[cIdx];
        if (!col.isForeignKey) continue;
        final targetTblName = col.foreignKeyTable?.toLowerCase();
        if (targetTblName == null) continue;
        final dstTable = tableMap[targetTblName];
        if (dstTable == null) continue;

        var dstColIdx = 0;
        final targetColName = col.foreignKeyColumn?.toLowerCase() ?? 'id';
        for (var i = 0; i < dstTable.columns.length; i++) {
          if (dstTable.columns[i].name.toLowerCase() == targetColName) {
            dstColIdx = i;
            break;
          }
        }

        final srcY = srcTable.erPosition.dy +
            ErDiagramCanvas._headerHeight +
            6 +
            cIdx * ErDiagramCanvas._rowHeight +
            ErDiagramCanvas._rowHeight / 2;
        final dstY = dstTable.erPosition.dy +
            ErDiagramCanvas._headerHeight +
            6 +
            dstColIdx * ErDiagramCanvas._rowHeight +
            ErDiagramCanvas._rowHeight / 2;

        final srcCenterX =
            srcTable.erPosition.dx + ErDiagramCanvas._cardWidth / 2;
        final dstCenterX =
            dstTable.erPosition.dx + ErDiagramCanvas._cardWidth / 2;

        final bool srcOnLeft = srcCenterX <= dstCenterX;
        final startX = srcOnLeft
            ? srcTable.erPosition.dx + ErDiagramCanvas._cardWidth
            : srcTable.erPosition.dx;
        final endX = srcOnLeft
            ? dstTable.erPosition.dx
            : dstTable.erPosition.dx + ErDiagramCanvas._cardWidth;

        final start = Offset(startX, srcY);
        final end = Offset(endX, dstY);
        final ctrlOffset = (end.dx - start.dx).abs() * 0.48 + 36.0;
        final c1 = Offset(
          srcOnLeft ? start.dx + ctrlOffset : start.dx - ctrlOffset,
          start.dy,
        );
        final c2 = Offset(
          srcOnLeft ? end.dx - ctrlOffset : end.dx + ctrlOffset,
          end.dy,
        );

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

        final isHighlighted = srcTable.name == selectedTableName ||
            dstTable.name == selectedTableName;

        // Glow stroke
        final glowPaint = Paint()
          ..color = (isHighlighted ? accentColor : const Color(0xFF38BDF8))
              .withValues(alpha: isHighlighted ? 0.35 : 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 5.0 : 3.5;
        canvas.drawPath(path, glowPaint);

        // Core curve stroke
        final linePaint = Paint()
          ..color = isHighlighted ? accentColor : const Color(0xFF38BDF8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 2.0 : 1.5;
        canvas.drawPath(path, linePaint);

        // Endpoint circles (crow's foot style markers)
        final markerPaint = Paint()
          ..color = isHighlighted ? accentColor : const Color(0xFFFBBF24)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(start, 3.5, markerPaint);
        canvas.drawCircle(end, 4.0, markerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ErDiagramPainter oldDelegate) => true;
}
