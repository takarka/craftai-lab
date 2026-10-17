import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../session/session_repository.dart';
import '../domain/assistant_setup.dart';
import '../domain/initial_workspace_repository.dart';

enum OnboardingFailure { unavailable, invalidDraft, saveFailed, sessionChanged }

class OnboardingState {
  const OnboardingState({
    required this.draft,
    this.saving = false,
    this.completed = false,
    this.failure,
  });
  final AssistantSetup draft;
  final bool saving;
  final bool completed;
  final OnboardingFailure? failure;
}

final initialWorkspaceRepositoryProvider = Provider<InitialWorkspaceRepository>(
  (ref) => const NotConnectedWorkspaceRepository(),
);

final onboardingControllerProvider = NotifierProvider.autoDispose
    .family<OnboardingController, OnboardingState, String>(
      OnboardingController.new,
    );

class OnboardingController extends Notifier<OnboardingState> {
  OnboardingController(this.ownerId);
  final String ownerId;
  bool _active = true;
  int _generation = 0;

  bool get _currentOwner {
    final session = ref.read(sessionProvider);
    final account = session.asData?.value;
    return !session.hasError &&
        account is AuthenticatedSession &&
        account.ownerId == ownerId;
  }

  @override
  OnboardingState build() {
    if (ownerId.trim().isEmpty) throw ArgumentError('Owner ID is required.');
    _active = true;
    ref.onDispose(() {
      _active = false;
      _generation++;
    });
    ref.listen(sessionProvider, (_, next) {
      final account = next.asData?.value;
      if (next.hasError ||
          account is! AuthenticatedSession ||
          account.ownerId != ownerId) {
        _generation++;
        state = OnboardingState(draft: AssistantSetup());
      }
    });
    return OnboardingState(draft: AssistantSetup());
  }

  void _edit(AssistantSetup draft) {
    if (!_currentOwner || state.saving || state.completed) return;
    state = OnboardingState(draft: draft);
  }

  void chooseSubject(SchoolSubject subject) =>
      _edit(state.draft.copyWith(subject: subject));
  void setCustomSubject(String value) =>
      _edit(state.draft.copyWith(customSubject: value));
  void setLanguage(AssistantLanguage value) =>
      _edit(state.draft.copyWith(language: value));
  void setName(String value) =>
      _edit(state.draft.copyWith(name: value, nameEdited: true));
  void suggestName(String value) {
    if (!state.draft.nameEdited) _edit(state.draft.copyWith(name: value));
  }

  void toggleGrade(int grade) {
    if (grade < 1 || grade > 11) {
      throw ArgumentError('Invalid grade.');
    }
    final grades = {...state.draft.grades};
    if (!grades.remove(grade)) grades.add(grade);
    _edit(state.draft.copyWith(grades: grades));
  }

  void toggleGradeGroup(int first, int last) {
    if (first < 1 || last > 11 || first > last) {
      throw ArgumentError('Invalid grade group.');
    }
    final group = {for (var grade = first; grade <= last; grade++) grade};
    final grades = {...state.draft.grades};
    if (grades.containsAll(group)) {
      grades.removeAll(group);
    } else {
      grades.addAll(group);
    }
    _edit(state.draft.copyWith(grades: grades));
  }

  Future<void> create() async {
    if (state.saving || state.completed) return;
    if (!_currentOwner) {
      state = OnboardingState(
        draft: AssistantSetup(),
        failure: OnboardingFailure.sessionChanged,
      );
      return;
    }
    if (!state.draft.ready) {
      state = OnboardingState(
        draft: state.draft,
        failure: OnboardingFailure.invalidDraft,
      );
      return;
    }
    final repository = ref.read(initialWorkspaceRepositoryProvider);
    if (!repository.isAvailable) {
      state = OnboardingState(
        draft: state.draft,
        failure: OnboardingFailure.unavailable,
      );
      return;
    }
    final generation = _generation;
    final draft = state.draft.normalized();
    state = OnboardingState(draft: draft, saving: true);
    try {
      final workspace = await repository.createIfAbsent(
        permit: WorkspaceWritePermit(
          ownerId: ownerId,
          canCommit: () =>
              _active && generation == _generation && _currentOwner,
        ),
        setup: draft,
      );
      if (!_active || generation != _generation || !_currentOwner) return;
      if (workspace.ownerId != ownerId || !workspace.setup.ready) {
        state = OnboardingState(
          draft: draft,
          failure: OnboardingFailure.saveFailed,
        );
        return;
      }
      state = OnboardingState(draft: workspace.setup, completed: true);
    } on WorkspaceUnavailable {
      if (_active && generation == _generation && _currentOwner) {
        state = OnboardingState(
          draft: draft,
          failure: OnboardingFailure.unavailable,
        );
      }
    } catch (_) {
      if (_active && generation == _generation && _currentOwner) {
        state = OnboardingState(
          draft: draft,
          failure: OnboardingFailure.saveFailed,
        );
      }
    }
  }
}
