import 'dart:math' as math;

enum DiffLineType {
  context,
  added,
  removed,
}

class DiffLine {
  final DiffLineType type;
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;

  const DiffLine({
    required this.type,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });
}

class DiffResult {
  final List<DiffLine> lines;
  final int addedCount;
  final int removedCount;
  final String unifiedPreview;

  const DiffResult({
    required this.lines,
    required this.addedCount,
    required this.removedCount,
    required this.unifiedPreview,
  });

  bool get hasChanges => addedCount > 0 || removedCount > 0;
}

/// Computes a line-by-line diff between [oldText] and [newText], producing both
/// structured [DiffLine] entries (for UI rendering) and a compact unified diff string.
DiffResult computeLineDiff(
  String oldText,
  String newText, {
  int contextLines = 3,
  int maxPreviewLines = 120,
}) {
  final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
  final newLines = newText.isEmpty ? <String>[] : newText.split('\n');

  final rawOps = _computeLcsDiff(oldLines, newLines);
  var added = 0;
  var removed = 0;
  for (final op in rawOps) {
    if (op.type == DiffLineType.added) added++;
    if (op.type == DiffLineType.removed) removed++;
  }

  // Filter down to changed lines + surrounding contextLines for compact preview.
  final changedIndices = <int>[];
  for (var i = 0; i < rawOps.length; i++) {
    if (rawOps[i].type != DiffLineType.context) {
      changedIndices.add(i);
    }
  }

  final visibleLines = <DiffLine>[];
  final previewBuf = StringBuffer();

  if (changedIndices.isEmpty) {
    return const DiffResult(
      lines: [],
      addedCount: 0,
      removedCount: 0,
      unifiedPreview: '',
    );
  }

  final include = List<bool>.filled(rawOps.length, false);
  for (final idx in changedIndices) {
    final start = math.max(0, idx - contextLines);
    final end = math.min(rawOps.length - 1, idx + contextLines);
    for (var j = start; j <= end; j++) {
      include[j] = true;
    }
  }

  var inGap = false;
  var printed = 0;
  for (var i = 0; i < rawOps.length; i++) {
    if (!include[i]) {
      inGap = true;
      continue;
    }
    if (inGap && visibleLines.isNotEmpty) {
      final separator = const DiffLine(
        type: DiffLineType.context,
        text: '···',
      );
      visibleLines.add(separator);
      if (printed < maxPreviewLines) {
        previewBuf.writeln('@@ ... @@');
        printed++;
      }
    }
    inGap = false;

    final line = rawOps[i];
    visibleLines.add(line);
    if (printed < maxPreviewLines) {
      final prefix = switch (line.type) {
        DiffLineType.added => '+',
        DiffLineType.removed => '-',
        DiffLineType.context => ' ',
      };
      previewBuf.writeln('$prefix${line.text}');
      printed++;
    }
  }

  if (printed >= maxPreviewLines && visibleLines.length > maxPreviewLines) {
    previewBuf.writeln('... (diff truncated)');
  }

  return DiffResult(
    lines: visibleLines,
    addedCount: added,
    removedCount: removed,
    unifiedPreview: previewBuf.toString().trimRight(),
  );
}

List<DiffLine> _computeLcsDiff(List<String> a, List<String> b) {
  // Trim common prefix and suffix first to keep DP matrix tiny on large files.
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }

  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }

  final result = <DiffLine>[];
  for (var i = 0; i < prefix; i++) {
    result.add(
      DiffLine(
        type: DiffLineType.context,
        text: a[i],
        oldLineNumber: i + 1,
        newLineNumber: i + 1,
      ),
    );
  }

  final midA = a.sublist(prefix, a.length - suffix);
  final midB = b.sublist(prefix, b.length - suffix);

  // If the changed middle region is very large, fall back to a linear
  // remove-then-add diff to stay fast and responsive in UI.
  if (midA.length * midB.length > 250000) {
    for (var i = 0; i < midA.length; i++) {
      result.add(
        DiffLine(
          type: DiffLineType.removed,
          text: midA[i],
          oldLineNumber: prefix + i + 1,
        ),
      );
    }
    for (var j = 0; j < midB.length; j++) {
      result.add(
        DiffLine(
          type: DiffLineType.added,
          text: midB[j],
          newLineNumber: prefix + j + 1,
        ),
      );
    }
  } else {
    final m = midA.length;
    final n = midB.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (var i = m - 1; i >= 0; i--) {
      for (var j = n - 1; j >= 0; j--) {
        if (midA[i] == midB[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = math.max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
    }

    var i = 0;
    var j = 0;
    while (i < m && j < n) {
      if (midA[i] == midB[j]) {
        result.add(
          DiffLine(
            type: DiffLineType.context,
            text: midA[i],
            oldLineNumber: prefix + i + 1,
            newLineNumber: prefix + j + 1,
          ),
        );
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        result.add(
          DiffLine(
            type: DiffLineType.removed,
            text: midA[i],
            oldLineNumber: prefix + i + 1,
          ),
        );
        i++;
      } else {
        result.add(
          DiffLine(
            type: DiffLineType.added,
            text: midB[j],
            newLineNumber: prefix + j + 1,
          ),
        );
        j++;
      }
    }

    while (i < m) {
      result.add(
        DiffLine(
          type: DiffLineType.removed,
          text: midA[i],
          oldLineNumber: prefix + i + 1,
        ),
      );
      i++;
    }
    while (j < n) {
      result.add(
        DiffLine(
          type: DiffLineType.added,
          text: midB[j],
          newLineNumber: prefix + j + 1,
        ),
      );
      j++;
    }
  }

  final tailStartA = a.length - suffix;
  final tailStartB = b.length - suffix;
  for (var k = 0; k < suffix; k++) {
    result.add(
      DiffLine(
        type: DiffLineType.context,
        text: a[tailStartA + k],
        oldLineNumber: tailStartA + k + 1,
        newLineNumber: tailStartB + k + 1,
      ),
    );
  }

  return result;
}
