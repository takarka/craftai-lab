import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Status of a mutating action requiring teacher confirmation (F14-05, F14-12).
enum PendingActionStatus {
  pending('pending', 'Ожидает решения учителя'),
  approved('approved', 'Подтверждено'),
  rejected('rejected', 'Отклонено учителем'),
  executed('executed', 'Успешно выполнено'),
  expired('expired', 'Истёк срок действия');

  final String id;
  final String label;

  const PendingActionStatus(this.id, this.label);

  static PendingActionStatus fromId(String id) {
    return PendingActionStatus.values.firstWhere(
      (s) => s.id == id,
      orElse: () => PendingActionStatus.pending,
    );
  }
}

/// A pending action requiring teacher confirmation stored in SQLite (tablePendingActions) (F14-05).
class PendingAction {
  final String invocationId;
  final String ownerId;
  final int workspaceEpoch;
  final String actionName;
  final String paramsHash;
  final Map<String, dynamic> params;
  final PendingActionStatus status;
  final DateTime? expiresAtUtc;
  final DateTime createdAtUtc;

  const PendingAction({
    required this.invocationId,
    required this.ownerId,
    required this.workspaceEpoch,
    required this.actionName,
    required this.paramsHash,
    required this.params,
    this.status = PendingActionStatus.pending,
    this.expiresAtUtc,
    required this.createdAtUtc,
  });

  bool get isExpired {
    if (expiresAtUtc == null) return false;
    return DateTime.now().toUtc().isAfter(expiresAtUtc!);
  }

  bool get canBeDecided {
    return status == PendingActionStatus.pending && !isExpired;
  }

  PendingAction copyWith({
    String? invocationId,
    String? ownerId,
    int? workspaceEpoch,
    String? actionName,
    String? paramsHash,
    Map<String, dynamic>? params,
    PendingActionStatus? status,
    DateTime? expiresAtUtc,
    DateTime? createdAtUtc,
  }) {
    return PendingAction(
      invocationId: invocationId ?? this.invocationId,
      ownerId: ownerId ?? this.ownerId,
      workspaceEpoch: workspaceEpoch ?? this.workspaceEpoch,
      actionName: actionName ?? this.actionName,
      paramsHash: paramsHash ?? this.paramsHash,
      params: params ?? this.params,
      status: status ?? this.status,
      expiresAtUtc: expiresAtUtc ?? this.expiresAtUtc,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invocation_id': invocationId,
      'owner_id': ownerId,
      'workspace_epoch': workspaceEpoch,
      'action_name': actionName,
      'params_hash': paramsHash,
      'params_json': jsonEncode(params),
      'status': status.id,
      'expires_at_utc': expiresAtUtc?.toIso8601String(),
      'created_at_utc': createdAtUtc.toIso8601String(),
    };
  }

  factory PendingAction.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedParams = {};
    try {
      final raw = map['params_json'];
      if (raw is String) {
        parsedParams = jsonDecode(raw) as Map<String, dynamic>;
      } else if (raw is Map) {
        parsedParams = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}

    return PendingAction(
      invocationId: map['invocation_id'] as String,
      ownerId: map['owner_id'] as String,
      workspaceEpoch: map['workspace_epoch'] as int? ?? 1,
      actionName: map['action_name'] as String,
      paramsHash: map['params_hash'] as String,
      params: parsedParams,
      status: PendingActionStatus.fromId(map['status'] as String? ?? 'pending'),
      expiresAtUtc: DateTime.tryParse(
        map['expires_at_utc'] as String? ?? '',
      )?.toUtc(),
      createdAtUtc:
          DateTime.tryParse(map['created_at_utc'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  /// Calculates deterministic SHA-256 hash of parameters to guard against replay / changes.
  static String computeParamsHash(Map<String, dynamic> params) {
    final sortedKeys = params.keys.toList()..sort();
    final sortedMap = {for (final k in sortedKeys) k: params[k]};
    final jsonStr = jsonEncode(sortedMap);
    return sha256.convert(utf8.encode(jsonStr)).toString();
  }
}

/// Domain state machine managing action confirmation lifecycle and preventing double execution (F14-05, F14-12).
class PendingActionStateMachine {
  const PendingActionStateMachine();

  /// Transitions a pending action to approved. Throws StateError if not in pending state or expired.
  PendingAction approve(PendingAction action) {
    if (action.isExpired) {
      throw StateError('Срок действия карточки подтверждения истёк');
    }
    if (action.status != PendingActionStatus.pending) {
      throw StateError('Действие уже обработано: ${action.status.label}');
    }
    return action.copyWith(status: PendingActionStatus.approved);
  }

  /// Transitions a pending action to rejected.
  PendingAction reject(PendingAction action) {
    if (action.status != PendingActionStatus.pending) {
      throw StateError('Действие уже обработано: ${action.status.label}');
    }
    return action.copyWith(status: PendingActionStatus.rejected);
  }

  /// Transitions an approved action to executed. Throws StateError if not approved.
  PendingAction markExecuted(PendingAction action) {
    if (action.status == PendingActionStatus.executed) {
      throw StateError(
        'Действие уже было исполнено (защита от повторного выполнения)',
      );
    }
    if (action.status != PendingActionStatus.approved) {
      throw StateError(
        'Нельзя исполнить не подтверждённое действие: ${action.status.label}',
      );
    }
    return action.copyWith(status: PendingActionStatus.executed);
  }

  /// Expires an action if its timeout has passed.
  PendingAction checkExpiration(PendingAction action) {
    if (action.status == PendingActionStatus.pending && action.isExpired) {
      return action.copyWith(status: PendingActionStatus.expired);
    }
    return action;
  }
}
