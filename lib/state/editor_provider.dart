import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/editor_channel.dart';
import '../core/models/adjustments.dart';
import '../core/models/edit_state.dart';
import '../core/models/history.dart';
import 'edit_persistence.dart';

/// Immutable UI state for the editor screen.
class EditorUiState {
  const EditorUiState({
    this.imageId,
    this.preview,
    this.aspectRatio = 1,
    this.sourceAspect = 1,
    this.edit = const EditState(),
    this.canUndo = false,
    this.canRedo = false,
    this.busy = false,
    this.error,
    this.facePts = const <ui.Offset>[],
    this.faceCount = 0,
  });

  final int? imageId;
  final ui.Image? preview;
  final double aspectRatio;

  /// Width / height of the *uncropped* source: the crop overlay is positioned
  /// against this while [EditorController.setCropEditing] is on.
  final double sourceAspect;
  final EditState edit;
  final bool canUndo;
  final bool canRedo;
  final bool busy;
  final String? error;

  /// Face-mesh key points (source-normalized, fixed 45-point order) from the
  /// last [EditorController.detectFace]. Runtime-only detection metadata: never
  /// persisted and never part of [Adjustments] equality — fed straight into
  /// `toRenderBytes` for the native warp engine and drawn as the on-canvas
  /// liquify guide. [faceCount] is the number of valid points (0 = no face).
  final List<ui.Offset> facePts;
  final int faceCount;

  EditorUiState copyWith({
    int? imageId,
    ui.Image? preview,
    double? aspectRatio,
    double? sourceAspect,
    EditState? edit,
    bool? canUndo,
    bool? canRedo,
    bool? busy,
    String? error,
    bool clearError = false,
    bool clearPreview = false,
    List<ui.Offset>? facePts,
    int? faceCount,
    bool clearFace = false,
  }) {
    return EditorUiState(
      imageId: imageId ?? this.imageId,
      preview: clearPreview ? null : (preview ?? this.preview),
      aspectRatio: aspectRatio ?? this.aspectRatio,
      sourceAspect: sourceAspect ?? this.sourceAspect,
      edit: edit ?? this.edit,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      facePts: clearFace ? const <ui.Offset>[] : (facePts ?? this.facePts),
      faceCount: clearFace ? 0 : (faceCount ?? this.faceCount),
    );
  }
}

/// Drives the native CPU preview pipeline and the non-destructive edit history.
class EditorController extends StateNotifier<EditorUiState> {
  EditorController(this._channel) : super(const EditorUiState());

  final EditorChannel _channel;
  HistoryStack? _history;

  // Absolute path of the image currently open; the target for the persisted
  // "保存" action (see saveToDisk / openImage restore).
  String? _path;

  // While the crop overlay is up, the native preview ignores the crop rect so
  // the user can see (and drag against) the whole image. Export always uses the
  // real geometry; see [exportImage].
  bool _cropEditing = false;

  // Whether the native preview bakes in the 90° turns. True only on the beauty
  // / liquify tabs (their overlays map source<->display through the turns);
  // everywhere else the rotation is applied visually, so this stays false.
  bool _nativeTurns = false;

  // Guards against overlapping FaceMesh inference calls (single-flight).
  bool _faceDetecting = false;

  // Preview throttle: single-flight + trailing so a burst of slider updates
  // only renders the newest request once the in-flight one completes.
  bool _rendering = false;
  bool _pending = false;
  int _pendingMaxDim = 1024;
  int _gen = 0; // bumped when the image changes so stale frames are discarded

  Future<void> openImage(String path) async {
    state = state.copyWith(busy: true, clearError: true);
    final gen = ++_gen;
    try {
      final opened = await _channel.openImage(path);
      if (gen != _gen) return;
      _path = path;
      final saved = await loadEdits(path) ?? const EditState();
      _history = HistoryStack(initial: saved);
      _cropEditing = false;
      _nativeTurns = false;
      state = state.copyWith(
        imageId: opened.imageId,
        edit: saved,
        sourceAspect: opened.aspectRatio,
        canUndo: false,
        canRedo: false,
        busy: false,
        clearPreview: true,
        clearFace: true,
      );
      await _applyParams(opened.imageId, _payload(saved));
      await _renderNow(1280);
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  /// Live update while a slider is dragging: no history entry, small preview.
  Future<void> updateAdjustment(Adjustments Function(Adjustments) transform) async {
    final id = state.imageId;
    if (id == null) return;
    final next = state.edit.copyWith(adjustments: transform(state.edit.adjustments));
    state = state.copyWith(edit: next);
    await _applyParams(id, _payload(next));
    await _scheduleRender(900);
  }

  /// Apply a filter preset on top of the current edits (additive merge, so
  /// manual adjustments are not wiped), then commit to history.
  Future<void> applyAdjustments(Adjustments adjustments) async {
    final id = state.imageId;
    final history = _history;
    if (id == null || history == null) return;
    final merged = state.edit.adjustments.mergeWithPreset(adjustments);
    final next = state.edit.copyWith(adjustments: merged);
    state = state.copyWith(edit: next);
    await _applyParams(id, _payload(next));
    history.push(next);
    state = state.copyWith(canUndo: history.canUndo, canRedo: history.canRedo);
    await _scheduleRender(1280);
  }

  /// Commit the current edit into history once a gesture ends (refine render).
  Future<void> commit() async {
    final id = state.imageId;
    final history = _history;
    if (id == null || history == null) return;
    history.push(state.edit);
    state = state.copyWith(canUndo: history.canUndo, canRedo: history.canRedo);
    await _scheduleRender(1280);
  }

  Future<void> undo() => _transition(canUndo: true);
  Future<void> redo() => _transition(canUndo: false);

  Future<void> _transition({required bool canUndo}) async {
    final id = state.imageId;
    final history = _history;
    if (id == null || history == null) return;
    final next = canUndo ? history.undo() : history.redo();
    state = state.copyWith(
      edit: next,
      canUndo: history.canUndo,
      canRedo: history.canRedo,
    );
    await _applyParams(id, _payload(next));
    await _scheduleRender(1280);
  }

  Future<void> reset() async {
    final id = state.imageId;
    final history = _history;
    if (id == null || history == null) return;
    final identity = const EditState();
    history.reset(identity);
    state = state.copyWith(edit: identity, canUndo: false, canRedo: false);
    await _applyParams(id, identity);
    await _scheduleRender(1280);
  }

  /// Exports the current full-resolution render to the gallery in [format]
  /// ('jpeg' | 'png'). Returns the saved URI / path, or null on failure.
  Future<String?> exportImage({String format = 'jpeg', int quality = 92}) async {
    final id = state.imageId;
    if (id == null) return null;
    // Push the *real* geometry first: the native session may currently hold a
    // crop-neutralized preview payload from crop-overlay mode.
    await _applyParams(id, state.edit);
    final saved = await _channel.exportImage(id, format: format, quality: quality);
    // Restore the preview-mode payload so the on-screen frame stays put.
    await _applyParams(id, _payload(state.edit));
    return saved;
  }

  Future<void> release() async {
    _gen++;
    final id = state.imageId;
    if (id != null) await _channel.release(id);
    _history = null;
    _path = null;
    state = const EditorUiState();
  }

  /// Persist the current edit set for the open image so it survives a relaunch
  /// and is restored the next time this exact image is opened.
  Future<void> saveToDisk() async {
    final path = _path;
    if (path == null) return;
    await saveEdits(path, state.edit);
  }

  /// The edit payload sent to native for the *preview*: the crop rect is
  /// neutralized while the crop overlay is up, and the 90° turns are stripped
  /// unless the active tab bakes rotation natively (beauty / liquify). Export
  /// bypasses this and always uses the real geometry; see [exportImage].
  EditState _payload(EditState e) {
    var a = e.adjustments;
    if (!_nativeTurns) a = a.copyWith(cropTurns: 0);
    if (_cropEditing) {
      a = a.copyWith(cropLeft: 0, cropTop: 0, cropRight: 1, cropBottom: 1);
    }
    return e.copyWith(adjustments: a);
  }

  /// Sends [e] to native together with the current face-mesh key points so the
  /// warp engine sees both manual impulses and the auto face sliders.
  Future<void> _applyParams(int id, EditState e) => _channel.setParams(
        id,
        e,
        facePts: state.facePts,
        faceCount: state.faceCount,
      );

  /// Runs ML Kit FaceMesh on the open image and stores the key points for the
  /// native warp engine + on-canvas guide. Safe to call each time the liquify
  /// tab opens; no-ops without an image or while another detection is in flight.
  Future<void> detectFace() async {
    final id = state.imageId;
    final path = _path;
    if (id == null || path == null || _faceDetecting) return;
    _faceDetecting = true;
    try {
      final pts = await _channel.detectFace(path);
      if (state.imageId != id) return;
      state = state.copyWith(facePts: pts, faceCount: pts.length);
      await _applyParams(id, _payload(state.edit));
      await _scheduleRender(1280);
    } finally {
      _faceDetecting = false;
    }
  }

  /// Sync the preview geometry mode to the active tab: [cropEditing] shows the
  /// full frame for overlay dragging; [nativeTurns] bakes the 90° rotation into
  /// the native frame (beauty / liquify) instead of rotating it visually.
  /// Re-renders only when the mode actually changes.
  Future<void> setPreviewMode({
    required bool cropEditing,
    required bool nativeTurns,
  }) async {
    if (_cropEditing == cropEditing && _nativeTurns == nativeTurns) return;
    _cropEditing = cropEditing;
    _nativeTurns = nativeTurns;
    final id = state.imageId;
    if (id == null) return;
    await _applyParams(id, _payload(state.edit));
    await _scheduleRender(1280);
  }

  // ---- preview scheduling ----

  Future<void> _scheduleRender(int maxDim) async {
    if (_rendering) {
      _pending = true;
      _pendingMaxDim = maxDim; // newest request wins
      return;
    }
    await _renderNow(maxDim);
  }

  Future<void> _renderNow(int maxDim) async {
    final id = state.imageId;
    if (id == null) return;
    final gen = _gen;
    _rendering = true;
    try {
      final frame = await _channel.renderPreview(id, maxDim: maxDim);
      if (frame == null || gen != _gen) return;
      final image = await _decode(frame);
      if (image == null || gen != _gen) return;
      state = state.copyWith(preview: image, aspectRatio: frame.aspectRatio);
    } finally {
      _rendering = false;
      if (_pending && gen == _gen) {
        _pending = false;
        await _renderNow(_pendingMaxDim);
      } else {
        _pending = false;
      }
    }
  }

  Future<ui.Image?> _decode(PreviewFrame frame) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.bytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  void dispose() {
    _gen++;
    final id = state.imageId;
    if (id != null) {
      // Fire-and-forget cleanup of the native session.
      _channel.release(id).ignore();
    }
    super.dispose();
  }
}

final editorChannelProvider = Provider<EditorChannel>((_) => EditorChannel.instance);

final editorProvider =
    StateNotifierProvider<EditorController, EditorUiState>((ref) {
  return EditorController(ref.watch(editorChannelProvider));
});
