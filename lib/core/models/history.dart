import 'edit_state.dart';

/// Undo / redo stack over [EditState] snapshots.
///
/// M0 keeps full-state snapshots (simple and correct); patch-based compression
/// to bound memory is a M7 optimization noted in the plan.
class HistoryStack {
  HistoryStack({required EditState initial, this.limit = 64})
      : _undo = <EditState>[initial];

  final int limit;
  final List<EditState> _undo;
  final List<EditState> _redo = <EditState>[];

  EditState get current => _undo.last;
  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  /// Push a new state, clearing the redo branch. No-op if identical to current.
  void push(EditState state) {
    if (state == current) return;
    _undo.add(state);
    if (_undo.length > limit) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  EditState undo() {
    if (!canUndo) return current;
    _redo.add(_undo.removeLast());
    return current;
  }

  EditState redo() {
    if (!canRedo) return current;
    final s = _redo.removeLast();
    _undo.add(s);
    return current;
  }

  void reset(EditState state) {
    _undo
      ..clear()
      ..add(state);
    _redo.clear();
  }
}
