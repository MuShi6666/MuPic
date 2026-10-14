import 'adjustments.dart';

/// Kind of local-adjustment mask (plan section: Masking).
enum MaskKind { global, linearGradient, radial, brush, colorRange, luminanceRange }

/// A single mask layer and its own local adjustment patch.
///
/// M0 defines the structure; local rendering lands in M5.
class MaskState {
  const MaskState({
    required this.id,
    this.kind = MaskKind.global,
    this.enabled = true,
    this.adjustments = Adjustments.identity,
  });

  final int id;
  final MaskKind kind;
  final bool enabled;
  final Adjustments adjustments;

  MaskState copyWith({bool? enabled, Adjustments? adjustments}) => MaskState(
        id: id,
        kind: kind,
        enabled: enabled ?? this.enabled,
        adjustments: adjustments ?? this.adjustments,
      );
}

/// The complete, non-destructive edit for one image: a global adjustment set
/// plus any number of local mask layers.
class EditState {
  const EditState({
    this.adjustments = Adjustments.identity,
    this.masks = const <MaskState>[],
  });

  final Adjustments adjustments;
  final List<MaskState> masks;

  bool get isNeutral =>
      masks.every((m) => !m.enabled || m.adjustments == Adjustments.identity) &&
      adjustments == Adjustments.identity;

  EditState copyWith({Adjustments? adjustments, List<MaskState>? masks}) => EditState(
        adjustments: adjustments ?? this.adjustments,
        masks: masks ?? this.masks,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'adjustments': adjustments.toJson(),
        'masks': masks
            .map((m) => <String, dynamic>{
                  'id': m.id,
                  'kind': m.kind.name,
                  'enabled': m.enabled,
                  'adjustments': m.adjustments.toJson(),
                })
            .toList(),
      };

  factory EditState.fromJson(Map<String, dynamic> j) {
    final a = j['adjustments'];
    final rawMasks = j['masks'];
    return EditState(
      adjustments: a is Map<String, dynamic>
          ? Adjustments.fromJson(a)
          : Adjustments.identity,
      masks: rawMasks is List
          ? rawMasks
              .whereType<Map<String, dynamic>>()
              .map((m) => MaskState(
                    id: (m['id'] as num?)?.toInt() ?? 0,
                    kind: MaskKind.values.firstWhere(
                      (k) => k.name == m['kind'],
                      orElse: () => MaskKind.global,
                    ),
                    enabled: m['enabled'] as bool? ?? true,
                    adjustments: m['adjustments'] is Map<String, dynamic>
                        ? Adjustments.fromJson(m['adjustments'] as Map<String, dynamic>)
                        : Adjustments.identity,
                  ))
              .toList()
          : const <MaskState>[],
    );
  }
}
