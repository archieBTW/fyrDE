import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../engine/sql_engine.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';

class StructureDdlPanel extends StatelessWidget {
  const StructureDdlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final table = ctrl.selectedTable;
    final accent = FyrTheme.accentColor;

    if (table == null) {
      return Center(
        child: Text(
          'Select a table in the Database Navigator.',
          style: TextStyle(fontSize: 13, color: FyrTheme.textColorMuted),
        ),
      );
    }

    final ddl = table.ddlSql.trim().isNotEmpty
        ? table.ddlSql
        : SqlEngine.generateTableDdl(table);

    return Row(
      children: [
        // Left: Columns, Indexes, Triggers
        Expanded(
          flex: 6,
          child: Container(
            color: FyrTheme.bgColor,
            padding: const EdgeInsets.all(14),
            child: ListView(
              children: [
                Row(
                  children: [
                    Icon(Icons.view_column_rounded, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Text(
                      '${table.schemaName}.${table.name} — Columns (${table.columns.length})',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${table.rows.length} rows • ${table.formattedSize}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: FyrTheme.textColorMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Columns Table
                Container(
                  decoration: BoxDecoration(
                    color: FyrTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FyrTheme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: FyrTheme.dividerColor),
                          ),
                        ),
                        child: Row(
                          children: [
                            _hdr('COLUMN', flex: 3),
                            _hdr('TYPE', flex: 2),
                            _hdr('KEYS', flex: 2),
                            _hdr('NULLABLE', flex: 2),
                            _hdr('DEFAULT / FK TARGET', flex: 3),
                          ],
                        ),
                      ),
                      for (final col in table.columns)
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: FyrTheme.dividerColor.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  col.name,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: FyrTheme.textColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  col.dataType,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: const Color(0xFF38BDF8),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    if (col.isPrimaryKey)
                                      _pill('PK', const Color(0xFFFBBF24)),
                                    if (col.isForeignKey)
                                      _pill('FK', const Color(0xFF38BDF8)),
                                    if (col.isUnique && !col.isPrimaryKey)
                                      _pill('UQ', const Color(0xFFA78BFA)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  col.isNullable ? 'YES' : 'NOT NULL',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10.5,
                                    color: col.isNullable
                                        ? FyrTheme.textColorMuted
                                        : const Color(0xFFF472B6),
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  col.isForeignKey
                                      ? '-> ${col.foreignKeyTarget}'
                                      : (col.defaultValue ?? '—'),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: col.isForeignKey
                                        ? const Color(0xFF38BDF8)
                                        : FyrTheme.textColorMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Indexes
                Text(
                  'Indexes (${table.indexes.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FyrTheme.textColor,
                  ),
                ),
                const SizedBox(height: 8),
                for (final idx in table.indexes)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: FyrTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.flash_on_rounded,
                          size: 14,
                          color: Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          idx.name,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.textColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '(${idx.columns.join(', ')})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                        const Spacer(),
                        _pill(
                          idx.isUnique ? 'UNIQUE BTREE' : 'BTREE',
                          idx.isUnique
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFA78BFA),
                        ),
                      ],
                    ),
                  ),
                if (table.triggers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Triggers (${table.triggers.length})',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final trg in table.triggers)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: FyrTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: Color(0xFFF472B6),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                trg.name,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: FyrTheme.textColor,
                                ),
                              ),
                              const Spacer(),
                              _pill(
                                '${trg.timing} ${trg.event}',
                                const Color(0xFFF472B6),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trg.definitionSql,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        // Right: Generated DDL SQL Viewer
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: FyrTheme.contentColor,
              border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Generated DDL Script',
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: ddl));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
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
                              Icons.copy_rounded,
                              size: 12,
                              color: FyrTheme.textColorMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Copy DDL',
                              style: TextStyle(
                                fontSize: 11,
                                color: FyrTheme.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => ctrl.newSqlTab(
                        title: 'ddl_${table.name}.sql',
                        initialSql: ddl,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          'Open in SQL Editor',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FyrTheme.bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        ddl,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          height: 1.5,
                          color: FyrTheme.textColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _hdr(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: FyrTheme.textColorMuted,
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
