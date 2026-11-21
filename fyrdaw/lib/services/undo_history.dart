/// Bounded, generic Undo/Redo history stack for DAW project state snapshots.
class UndoRedoStack<T> {
  final int maxEntries;
  final List<T> _undo = [];
  final List<T> _redo = [];

  UndoRedoStack({this.maxEntries = 50}) : assert(maxEntries > 0);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoLength => _undo.length;
  int get redoLength => _redo.length;

  /// Records a new state [snapshot] prior to a mutation and clears the redo
  /// branch, evicting the oldest entry if [maxEntries] is exceeded.
  void push(T snapshot) {
    _undo.add(snapshot);
    while (_undo.length > maxEntries) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  /// Moves [currentState] to the redo stack and returns the previous snapshot,
  /// or `null` if there is nothing to undo.
  T? undo(T currentState) {
    if (_undo.isEmpty) return null;
    _redo.add(currentState);
    while (_redo.length > maxEntries) {
      _redo.removeAt(0);
    }
    return _undo.removeLast();
  }

  /// Moves [currentState] to the undo stack and returns the next snapshot,
  /// or `null` if there is nothing to redo.
  T? redo(T currentState) {
    if (_redo.isEmpty) return null;
    _undo.add(currentState);
    while (_undo.length > maxEntries) {
      _undo.removeAt(0);
    }
    return _redo.removeLast();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
