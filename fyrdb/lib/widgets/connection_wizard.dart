import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../engine/sql_engine.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';

/// Sleek 3-step Connection Setup Wizard (`1. Engine` -> `2. Configure` -> `3. Test & Connect`).
/// Displayed inline in the workspace whenever no connection is active, and also usable as a modal dialog.
class ConnectionWizard extends StatefulWidget {
  final bool isModal;

  const ConnectionWizard({super.key, this.isModal = false});

  static Future<void> showModal(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: const ConnectionWizard(isModal: true),
      ),
    );
  }

  @override
  State<ConnectionWizard> createState() => _ConnectionWizardState();
}

class _ConnectionWizardState extends State<ConnectionWizard> {
  static const List<DbDriverType> _wizardEngines = [
    DbDriverType.sqlite,
    DbDriverType.postgres,
    DbDriverType.mysql,
    DbDriverType.duckdb,
    DbDriverType.redis,
  ];

  int _step = 0; // 0: Engine, 1: Configure, 2: Test & Connect
  DbDriverType _driver = DbDriverType.sqlite;

  final _uriCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController(text: 'localhost');
  final _portCtrl = TextEditingController(text: '5432');
  final _dbCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _sslEnabled = false;
  bool _readOnly = false;
  bool _createNewFile = false;

  String? _uriFeedback;
  bool _uriError = false;
  String? _validationError;

  bool _isTesting = false;
  ConnectionTestResult? _testResult;
  bool _isConnecting = false;

  @override
  void dispose() {
    _uriCtrl.dispose();
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _dbCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _selectEngine(DbDriverType driver) {
    setState(() {
      _driver = driver;
      _validationError = null;
      _testResult = null;
      _uriFeedback = null;
      if (driver.defaultPort > 0) {
        _portCtrl.text = '${driver.defaultPort}';
      }
      if (driver.isFileBased) {
        _sslEnabled = false;
        _userCtrl.text = '';
      } else {
        if (_hostCtrl.text.trim().isEmpty) {
          _hostCtrl.text = 'localhost';
        }
        _userCtrl.text = driver.defaultUsername;
        if (driver == DbDriverType.redis && _dbCtrl.text.trim().isEmpty) {
          _dbCtrl.text = '0';
        } else if (driver != DbDriverType.redis && _dbCtrl.text.trim() == '0') {
          _dbCtrl.text = '';
        }
      }
    });
  }

  void _applyConnectionUri() {
    final raw = _uriCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _uriFeedback = 'Paste a connection URI first.';
        _uriError = true;
      });
      return;
    }

    final parsed = SqlEngine.parseConnectionUri(raw);
    if (parsed == null) {
      setState(() {
        _uriFeedback =
            'Unsupported URI format. Try postgres://user:pass@host:5432/db';
        _uriError = true;
      });
      return;
    }

    setState(() {
      if (parsed.driver != null) {
        _driver = parsed.driver!;
      }
      if (parsed.host != null) _hostCtrl.text = parsed.host!;
      if (parsed.port != null && parsed.port! > 0) {
        _portCtrl.text = '${parsed.port}';
      }
      if (parsed.database != null) _dbCtrl.text = parsed.database!;
      if (parsed.username != null) _userCtrl.text = parsed.username!;
      if (parsed.password != null) _passwordCtrl.text = parsed.password!;
      if (parsed.sslEnabled != null) _sslEnabled = parsed.sslEnabled!;

      if (_nameCtrl.text.trim().isEmpty) {
        final target = parsed.database ?? parsed.host ?? _driver.name;
        _nameCtrl.text = '${_driver.shortTag.toLowerCase()}_$target';
      }
      _uriFeedback = 'Applied URI settings for ${_driver.label}.';
      _uriError = false;
      _validationError = null;
      _testResult = null;
    });
  }

  Future<void> _browseExistingFile() async {
    final extensions = _driver == DbDriverType.sqlite
        ? ['sqlite', 'sqlite3', 'db']
        : ['duckdb', 'ddb'];
    try {
      final res = await FilePicker.pickFiles(
        dialogTitle: 'Select Existing ${_driver.label} File',
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      if (res != null && res.files.single.path != null) {
        final chosenPath = res.files.single.path!;
        final fileName = chosenPath.split('/').last;
        setState(() {
          _dbCtrl.text = chosenPath;
          _createNewFile = false;
          if (_nameCtrl.text.trim().isEmpty) {
            _nameCtrl.text = fileName;
          }
          _validationError = null;
          _testResult = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _createNewFileLocation() async {
    final defaultName = _driver == DbDriverType.sqlite
        ? 'new_database.sqlite'
        : 'analytics.duckdb';
    try {
      final outPath = await FilePicker.saveFile(
        dialogTitle: 'Choose Location for New ${_driver.label} Database',
        fileName: defaultName,
      );
      if (outPath != null && outPath.trim().isNotEmpty) {
        final fileName = outPath.split('/').last;
        setState(() {
          _dbCtrl.text = outPath;
          _createNewFile = true;
          if (_nameCtrl.text.trim().isEmpty) {
            _nameCtrl.text = fileName;
          }
          _validationError = null;
          _testResult = null;
        });
      }
    } catch (_) {}
  }

  bool _validateStep2() {
    if (_driver.isFileBased) {
      if (_dbCtrl.text.trim().isEmpty) {
        setState(() {
          _validationError =
              'Please enter a database file path, browse an existing file, or create a new file.';
        });
        return false;
      }
    } else {
      if (_hostCtrl.text.trim().isEmpty) {
        setState(() => _validationError = 'Host address is required.');
        return false;
      }
      final port = int.tryParse(_portCtrl.text.trim());
      if (port == null || port <= 0 || port > 65535) {
        setState(() {
          _validationError = 'Port must be a valid number between 1 and 65535.';
        });
        return false;
      }
    }
    setState(() => _validationError = null);
    return true;
  }

  DbConnectionProfile _buildProfile() {
    final dbOrPath = _dbCtrl.text.trim();
    final rawName = _nameCtrl.text.trim();
    final fallbackName = _driver.isFileBased
        ? (dbOrPath.isEmpty ? '${_driver.name}_db' : dbOrPath.split('/').last)
        : (dbOrPath.isNotEmpty
            ? '${_hostCtrl.text.trim()}/$dbOrPath'
            : '${_driver.name}_${_hostCtrl.text.trim()}');

    return DbConnectionProfile(
      id: 'conn_${DateTime.now().microsecondsSinceEpoch}',
      name: rawName.isEmpty ? fallbackName : rawName,
      driver: _driver,
      host: _driver.isFileBased ? 'localhost' : _hostCtrl.text.trim(),
      port: _driver.isFileBased
          ? 0
          : (int.tryParse(_portCtrl.text.trim()) ?? _driver.defaultPort),
      databaseOrPath: dbOrPath,
      username: _driver.isFileBased ? '' : _userCtrl.text.trim(),
      password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
      sslEnabled: _driver.isFileBased ? false : _sslEnabled,
      readOnly: _readOnly,
      isConnected: true,
    );
  }

  Future<void> _runTestConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final profile = _buildProfile();
    final res = await SqlEngine.testConnection(
      profile,
      createIfMissing: _createNewFile,
    );
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testResult = res;
    });
  }

  Future<void> _connectAndOpen() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    final ctrl = context.read<DbController>();
    final profile = _buildProfile();
    await ctrl.addConnection(
      profile,
      createFileIfMissing: _createNewFile,
    );
    if (!mounted) return;
    setState(() => _isConnecting = false);
    if (widget.isModal) {
      Navigator.of(context).pop();
    }
  }

  void _goNext() {
    if (_step == 0) {
      setState(() {
        _step = 1;
        _validationError = null;
      });
    } else if (_step == 1) {
      if (_validateStep2()) {
        setState(() {
          _step = 2;
          _testResult = null;
        });
      }
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() {
        _step -= 1;
        _validationError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = FyrTheme.accentColor;
    final ctrl = context.watch<DbController>();

    final card = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.isModal ? 680 : 740,
        maxHeight: widget.isModal ? 680 : 760,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: FyrTheme.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FyrTheme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isModal ? 0.45 : 0.25),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(accent),
            _buildStepper(accent),
            Divider(height: 1, color: FyrTheme.dividerColor),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_step == 0) _buildStep1Engine(accent),
                    if (_step == 1) _buildStep2Configure(accent),
                    if (_step == 2) _buildStep3TestAndConnect(accent),
                    if (!widget.isModal &&
                        _step == 0 &&
                        ctrl.connections.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildSavedQuickConnectBar(ctrl, accent),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: FyrTheme.dividerColor),
            _buildFooter(accent),
          ],
        ),
      ),
    );

    if (widget.isModal) {
      return card;
    }

    return Container(
      color: FyrTheme.bgColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: card,
    );
  }

  Widget _buildHeader(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.55)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.cable_rounded,
              size: 18,
              color: FyrTheme.getContrastingColor(accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isModal
                      ? 'New Database Connection'
                      : 'Connection Setup Wizard',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: FyrTheme.textColor,
                  ),
                ),
                Text(
                  'Connect a local database file or remote server to open the fyrDB workspace.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isModal)
            IconButton(
              tooltip: 'Close',
              icon: Icon(Icons.close_rounded,
                  size: 18, color: FyrTheme.textColorMuted),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepper(Color accent) {
    const labels = ['1. Engine', '2. Configure', '3. Test & Connect'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 14),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: i < _step ? () => setState(() => _step = i) : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _step == i
                      ? accent.withValues(alpha: 0.18)
                      : (_step > i
                          ? const Color(0xFF22C55E).withValues(alpha: 0.14)
                          : FyrTheme.cardColor),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: _step == i
                        ? accent
                        : (_step > i
                            ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                            : FyrTheme.dividerColor),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_step > i)
                      const Padding(
                        padding: EdgeInsets.only(right: 5),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: Color(0xFF4ADE80),
                        ),
                      ),
                    Text(
                      labels[i],
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight:
                            _step == i ? FontWeight.w700 : FontWeight.w500,
                        color: _step == i
                            ? FyrTheme.textColor
                            : (_step > i
                                ? const Color(0xFF4ADE80)
                                : FyrTheme.textColorMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: _step > i
                      ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                      : FyrTheme.dividerColor,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep1Engine(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Database Engine',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FyrTheme.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose a local embedded engine or a remote database server.',
          style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final colCount = constraints.maxWidth >= 560 ? 2 : 1;
            const spacing = 10.0;
            final cardWidth =
                (constraints.maxWidth - (colCount - 1) * spacing) / colCount;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: _wizardEngines.map((engine) {
                final isSelected = _driver == engine ||
                    (engine == DbDriverType.mysql &&
                        _driver == DbDriverType.mariadb);
                return SizedBox(
                  width: cardWidth,
                  child: InkWell(
                    key: ValueKey('engine_card_${engine.name}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _selectEngine(engine),
                    onDoubleTap: () {
                      _selectEngine(engine);
                      _goNext();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? engine.badgeColor.withValues(alpha: 0.12)
                            : FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? engine.badgeColor
                              : FyrTheme.dividerColor,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: engine.badgeColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    engine.badgeColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Icon(
                              engine.icon,
                              size: 18,
                              color: engine.badgeColor,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        engine.label,
                                        style: GoogleFonts.outfit(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: FyrTheme.textColor,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: engine.badgeColor,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: FyrTheme.bgColor,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: FyrTheme.dividerColor,
                                    ),
                                  ),
                                  child: Text(
                                    engine.hint,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      color: engine.badgeColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  engine.description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: FyrTheme.textColorMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStep2Configure(Color accent) {
    final isFile = _driver.isFileBased;
    final isMysqlFamily =
        _driver == DbDriverType.mysql || _driver == DbDriverType.mariadb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_driver.icon, size: 17, color: _driver.badgeColor),
            const SizedBox(width: 8),
            Text(
              'Configure ${_driver.label}',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: FyrTheme.textColor,
              ),
            ),
            const Spacer(),
            if (isMysqlFamily) _buildMysqlVariantToggle(accent),
          ],
        ),
        const SizedBox(height: 14),
        if (!isFile) ...[
          // Connection URI quick-fill bar
          Text(
            'Quick-Fill from Connection URI (optional)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColorMuted,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    key: const ValueKey('wizard_uri_field'),
                    controller: _uriCtrl,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: FyrTheme.textColor,
                    ),
                    onSubmitted: (_) => _applyConnectionUri(),
                    decoration: _inputDecoration(
                      hintText: _driver == DbDriverType.redis
                          ? 'redis://:password@localhost:6379/0'
                          : '${_driver.name}://user:pass@host:${_driver.defaultPort}/dbname',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('wizard_apply_uri_btn'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  side: BorderSide(color: FyrTheme.dividerColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: _applyConnectionUri,
                icon: Icon(Icons.auto_fix_high_rounded, size: 14, color: accent),
                label: Text(
                  'Apply URI',
                  style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
                ),
              ),
            ],
          ),
          if (_uriFeedback != null) ...[
            const SizedBox(height: 5),
            Text(
              _uriFeedback!,
              style: TextStyle(
                fontSize: 11,
                color: _uriError
                    ? const Color(0xFFF87171)
                    : const Color(0xFF4ADE80),
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        if (isFile) ...[
          _labeledField(
            label: 'Connection Name',
            controller: _nameCtrl,
            fieldKey: const ValueKey('wizard_name_field'),
            hintText: _driver == DbDriverType.sqlite
                ? 'e.g. Local App DB'
                : 'e.g. Local Analytics DuckDB',
          ),
          const SizedBox(height: 12),
          _labeledField(
            label: 'Database File Path',
            controller: _dbCtrl,
            fieldKey: const ValueKey('wizard_path_field'),
            hintText: _driver == DbDriverType.sqlite
                ? '/path/to/database.sqlite (or :memory:)'
                : '/path/to/analytics.duckdb',
            monospace: true,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('wizard_browse_file_btn'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: FyrTheme.dividerColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: _browseExistingFile,
                icon: Icon(Icons.folder_open_rounded, size: 15, color: accent),
                label: Text(
                  'Browse Existing File',
                  style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('wizard_create_file_btn'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _createNewFile ? accent : FyrTheme.dividerColor,
                  ),
                  backgroundColor: _createNewFile
                      ? accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: _createNewFileLocation,
                icon: Icon(Icons.add_circle_outline_rounded,
                    size: 15, color: accent),
                label: Text(
                  'Create New File',
                  style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Switch(
                value: _createNewFile,
                activeTrackColor: accent,
                onChanged: (v) => setState(() => _createNewFile = v),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Create database file on disk if it does not exist yet',
                  style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Switch(
                value: _readOnly,
                activeTrackColor: accent,
                onChanged: (v) => setState(() => _readOnly = v),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Read-Only Safety Lock (block INSERT / UPDATE / DELETE / DDL)',
                  style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _labeledField(
                  label: 'Connection Name',
                  controller: _nameCtrl,
                  fieldKey: const ValueKey('wizard_name_field'),
                  hintText: 'e.g. Local ${_driver.label}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _labeledField(
                  label: 'Host',
                  controller: _hostCtrl,
                  fieldKey: const ValueKey('wizard_host_field'),
                  hintText: 'localhost or 127.0.0.1',
                  monospace: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _labeledField(
                  label: 'Port',
                  controller: _portCtrl,
                  fieldKey: const ValueKey('wizard_port_field'),
                  hintText: '${_driver.defaultPort}',
                  monospace: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _labeledField(
                  label: _driver == DbDriverType.redis
                      ? 'Database Index'
                      : 'Database Name',
                  controller: _dbCtrl,
                  fieldKey: const ValueKey('wizard_db_field'),
                  hintText: _driver == DbDriverType.redis ? '0' : 'postgres',
                  monospace: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _labeledField(
                  label: _driver == DbDriverType.redis
                      ? 'Username (optional)'
                      : 'Username',
                  controller: _userCtrl,
                  fieldKey: const ValueKey('wizard_user_field'),
                  hintText: _driver.defaultUsername.isEmpty
                      ? 'default'
                      : _driver.defaultUsername,
                  monospace: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _passwordField(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    key: const ValueKey('wizard_ssl_switch'),
                    value: _sslEnabled,
                    activeTrackColor: accent,
                    onChanged: (v) => setState(() => _sslEnabled = v),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'SSL / TLS Encrypted',
                    style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _readOnly,
                    activeTrackColor: accent,
                    onChanged: (v) => setState(() => _readOnly = v),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Read-Only Lock',
                    style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Security note: Saved profiles in ~/.config/fyrdb/connections.json never store raw passwords on disk.',
            style: TextStyle(
              fontSize: 10.5,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ],
        if (_validationError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF87171).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: const Color(0xFFF87171).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 15, color: Color(0xFFF87171)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _validationError!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFFCA5A5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMysqlVariantToggle(Color accent) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _variantChip('MySQL', DbDriverType.mysql, accent),
          _variantChip('MariaDB', DbDriverType.mariadb, accent),
        ],
      ),
    );
  }

  Widget _variantChip(String label, DbDriverType type, Color accent) {
    final active = _driver == type;
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => setState(() => _driver = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildStep3TestAndConnect(Color accent) {
    final preview = _buildProfile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review, Test & Connect',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: FyrTheme.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Verify connectivity before saving and opening your workspace.',
          style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
        ),
        const SizedBox(height: 14),
        // Summary Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: FyrTheme.dividerColor),
          ),
          child: Column(
            children: [
              _summaryRow('Engine', preview.driver.label,
                  badgeColor: preview.driver.badgeColor),
              _summaryRow('Connection Name', preview.name),
              if (preview.driver.isFileBased) ...[
                _summaryRow('Database File', preview.databaseOrPath,
                    monospace: true),
                _summaryRow(
                  'File Mode',
                  _createNewFile
                      ? 'Create new file if missing'
                      : 'Open existing file',
                ),
              ] else ...[
                _summaryRow('Endpoint', '${preview.host}:${preview.port}',
                    monospace: true),
                if (preview.databaseOrPath.isNotEmpty)
                  _summaryRow(
                    preview.driver == DbDriverType.redis
                        ? 'DB Index'
                        : 'Database',
                    preview.databaseOrPath,
                    monospace: true,
                  ),
                if (preview.username.isNotEmpty)
                  _summaryRow('Username', preview.username, monospace: true),
                _summaryRow(
                  'Authentication',
                  _passwordCtrl.text.isEmpty
                      ? 'No password provided'
                      : 'Password set (session-only)',
                ),
                _summaryRow(
                  'SSL / TLS',
                  preview.sslEnabled ? 'Enabled' : 'Disabled',
                ),
              ],
              _summaryRow(
                'Safety Mode',
                preview.readOnly ? 'Read-Only Locked' : 'Read & Write',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('wizard_test_conn_btn'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent.withValues(alpha: 0.6)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isTesting ? null : _runTestConnection,
              icon: _isTesting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : Icon(Icons.radar_rounded, size: 16, color: accent),
              label: Text(
                _isTesting ? 'Testing Connection...' : 'Test Connection',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (_testResult != null)
              Text(
                '${_testResult!.latencyMs.toStringAsFixed(1)} ms',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: FyrTheme.textColorMuted,
                ),
              ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_testResult!.success
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFF87171))
                  .withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (_testResult!.success
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFF87171))
                    .withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _testResult!.success
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 17,
                  color: _testResult!.success
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFF87171),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _testResult!.message,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _testResult!.success
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFFCA5A5),
                        ),
                      ),
                      if (_testResult!.details != null &&
                          _testResult!.details!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _testResult!.details!,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSavedQuickConnectBar(DbController ctrl, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Or reconnect to a saved profile:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColorMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ctrl.connections.map((conn) {
              return InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => ctrl.selectConnection(conn.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: FyrTheme.dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(conn.driver.icon,
                          size: 14, color: conn.driver.badgeColor),
                      const SizedBox(width: 6),
                      Text(
                        conn.name,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.textColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        conn.driver.shortTag,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          color: conn.driver.badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      child: Row(
        children: [
          if (_step > 0)
            OutlinedButton.icon(
              key: const ValueKey('wizard_back_btn'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: FyrTheme.dividerColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _goBack,
              icon: Icon(Icons.arrow_back_rounded,
                  size: 15, color: FyrTheme.textColorMuted),
              label: Text(
                'Back',
                style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
              ),
            )
          else if (widget.isModal)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 12, color: FyrTheme.textColorMuted),
              ),
            ),
          const Spacer(),
          if (_step < 2)
            FilledButton.icon(
              key: const ValueKey('wizard_next_btn'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FyrTheme.getContrastingColor(accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _goNext,
              icon: const Icon(Icons.arrow_forward_rounded, size: 15),
              label: Text(
                _step == 0 ? 'Next: Configure' : 'Next: Test & Connect',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            FilledButton.icon(
              key: const ValueKey('wizard_connect_btn'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FyrTheme.getContrastingColor(accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isConnecting ? null : _connectAndOpen,
              icon: _isConnecting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FyrTheme.getContrastingColor(accent),
                      ),
                    )
                  : const Icon(Icons.power_rounded, size: 15),
              label: Text(
                _isConnecting
                    ? 'Connecting...'
                    : 'Connect & Open Workspace',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool monospace = false,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
            ),
          ),
          Expanded(
            child: badgeColor != null
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    value,
                    style: monospace
                        ? GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            color: FyrTheme.textColor,
                          )
                        : TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: FyrTheme.textColor,
                          ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    Key? fieldKey,
    String? hintText,
    bool monospace = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 34,
          child: TextField(
            key: fieldKey,
            controller: controller,
            style: monospace
                ? GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    color: FyrTheme.textColor,
                  )
                : TextStyle(fontSize: 12, color: FyrTheme.textColor),
            decoration: _inputDecoration(hintText: hintText),
          ),
        ),
      ],
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 34,
          child: TextField(
            key: const ValueKey('wizard_password_field'),
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11.5,
              color: FyrTheme.textColor,
            ),
            decoration: _inputDecoration(hintText: '••••••••').copyWith(
              suffixIcon: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 15,
                  color: FyrTheme.textColorMuted,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 11,
        color: FyrTheme.textColorMuted.withValues(alpha: 0.55),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      filled: true,
      fillColor: FyrTheme.bgColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: FyrTheme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: FyrTheme.accentColor),
      ),
    );
  }
}
