import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/presentation/foundation_pages.dart';
import '../../../core/errors/app_failure.dart';
import '../../../ui_kit/ui_kit.dart';
import '../application/auth_controller.dart';
import '../domain/auth_gateway.dart';
import 'auth_validation.dart';

typedef _DocumentRevision = ({String locale, String terms, String privacy});

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key, required this.kind});
  final AuthFormKind kind;
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  _DocumentRevision? _acceptedRevision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearSecrets();
  }

  void _clearSecrets() {
    _password.clear();
    _confirmation.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  AuthLegalDocuments? _documents() {
    final documents = ref
        .read(authGatewayProvider)
        .documentsFor(Localizations.localeOf(context).languageCode);
    return documents != null && documents.isUsable ? documents : null;
  }

  _DocumentRevision? _revision(AuthLegalDocuments? documents) =>
      documents == null
      ? null
      : (
          locale: Localizations.localeOf(context).languageCode,
          terms: documents.terms.revision,
          privacy: documents.privacy.revision,
        );

  Future<void> _submit() async {
    if (ref.read(authControllerProvider(widget.kind)).busy) return;
    if (!_form.currentState!.validate()) return;
    final documents = _documents();
    if (widget.kind == AuthFormKind.register &&
        (documents == null || _acceptedRevision != _revision(documents))) {
      return;
    }
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final password = _password.text;
    final name = _name.text.trim();
    try {
      await ref
          .read(authControllerProvider(widget.kind).notifier)
          .submit(
            (gateway) => switch (widget.kind) {
              AuthFormKind.signIn => gateway.signIn(
                email: email,
                password: password,
              ),
              AuthFormKind.register => gateway.register(
                name: name,
                email: email,
                password: password,
                termsRevision: documents!.terms.revision,
                privacyRevision: documents.privacy.revision,
              ),
              AuthFormKind.recovery => gateway.requestPasswordReset(
                email: email,
              ),
            },
          );
    } finally {
      if (mounted) _clearSecrets();
    }
  }

  void _navigate(String path) {
    _clearSecrets();
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final submission = ref.watch(authControllerProvider(widget.kind));
    final gateway = ref.watch(authGatewayProvider);
    final registering = widget.kind == AuthFormKind.register;
    final recovering = widget.kind == AuthFormKind.recovery;
    final documents = _documents();
    final revision = _revision(documents);
    final accepted = revision != null && _acceptedRevision == revision;
    final canSubmit =
        gateway.isAvailable && !submission.busy && (!registering || accepted);
    final title = recovering
        ? strings.authRecoveryTitle
        : registering
        ? strings.authRegister
        : strings.appTitle;
    return Scaffold(
      appBar: AppBar(actions: const [LanguageSelector()]),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  onDisposeAction: AutofillContextAction.cancel,
                  child: Form(
                    key: _form,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          label: strings.authHeroLabel,
                          image: true,
                          child: ExcludeSemantics(
                            child: Center(
                              child: BuilderCharacter(
                                size: recovering ? 80 : 112,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          submission.recoverySent
                              ? strings.authCheckInbox
                              : title,
                          textAlign: TextAlign.center,
                          style: BuilderType.h1,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          recovering
                              ? strings.authRecoveryDescription
                              : strings.authIntro,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (!gateway.isAvailable) ...[
                          _Message(strings.authUnavailable),
                          const SizedBox(height: 16),
                        ],
                        if (submission.recoverySent) ...[
                          Semantics(
                            liveRegion: true,
                            child: _Message(strings.authResetSent),
                          ),
                        ] else ...[
                          if (registering) ...[
                            TextFormField(
                              key: const Key('auth.name'),
                              controller: _name,
                              enabled: !submission.busy,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              decoration: InputDecoration(
                                labelText: strings.authName,
                                errorMaxLines: 3,
                              ),
                              validator: (value) =>
                                  AuthValidation.requiredText(value, strings),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            key: const Key('auth.email'),
                            controller: _email,
                            enabled: !submission.busy,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: recovering
                                ? TextInputAction.done
                                : TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              labelText: strings.authEmail,
                              hintText: 'name@school.kz',
                              errorMaxLines: 3,
                            ),
                            onFieldSubmitted: recovering && canSubmit
                                ? (_) => _submit()
                                : null,
                            validator: (value) =>
                                AuthValidation.email(value, strings),
                          ),
                          if (!recovering) ...[
                            const SizedBox(height: 16),
                            AuthPasswordField(
                              key: const Key('auth.password'),
                              controller: _password,
                              label: strings.authPassword,
                              enabled: !submission.busy,
                              newPassword: registering,
                              textInputAction: registering
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              validator: (value) =>
                                  AuthValidation.password(value, strings),
                              onSubmitted: !registering && canSubmit
                                  ? (_) => _submit()
                                  : null,
                            ),
                          ],
                          if (registering) ...[
                            const SizedBox(height: 8),
                            Text(
                              strings.authPasswordHint,
                              style: BuilderType.small,
                            ),
                            const SizedBox(height: 16),
                            AuthPasswordField(
                              key: const Key('auth.confirmPassword'),
                              controller: _confirmation,
                              label: strings.authConfirmPassword,
                              enabled: !submission.busy,
                              newPassword: true,
                              textInputAction: TextInputAction.done,
                              validator: (value) => AuthValidation.confirmation(
                                value,
                                _password.text,
                                strings,
                              ),
                              onSubmitted: canSubmit ? (_) => _submit() : null,
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              key: const Key('auth.consent'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: accepted,
                              title: Text(strings.authAcceptDocuments),
                              onChanged: documents == null || submission.busy
                                  ? null
                                  : (value) => setState(
                                      () => _acceptedRevision = value == true
                                          ? revision
                                          : null,
                                    ),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: submission.busy
                                      ? null
                                      : () => _navigate('/legal/terms'),
                                  child: Text(strings.authTerms),
                                ),
                                TextButton(
                                  onPressed: submission.busy
                                      ? null
                                      : () => _navigate('/legal/privacy'),
                                  child: Text(strings.authPrivacy),
                                ),
                              ],
                            ),
                            if (documents == null)
                              _Message(strings.authLegalUnavailable),
                          ],
                          if (submission.failure
                              case final AppFailure failure) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              liveRegion: true,
                              child: _Message(
                                _failureMessage(failure, strings),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          BuilderButton(
                            label: recovering
                                ? strings.authSendReset
                                : registering
                                ? strings.authRegister
                                : strings.authSignIn,
                            onPressed: canSubmit ? _submit : null,
                            loading: submission.busy,
                            loadingLabel: strings.authSubmitting,
                          ),
                          if (!registering && !recovering) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: submission.busy
                                  ? null
                                  : () => _navigate('/recover-password'),
                              child: Text(strings.authForgotPassword),
                            ),
                            const SizedBox(height: 8),
                            BuilderButton(
                              label: strings.authRegister,
                              variant: BuilderButtonVariant.secondary,
                              onPressed: submission.busy
                                  ? null
                                  : () => _navigate('/register'),
                            ),
                          ],
                        ],
                        if (registering || recovering) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: submission.busy
                                ? null
                                : () {
                                    _clearSecrets();
                                    context.go('/sign-in');
                                  },
                            child: Text(strings.authBackToSignIn),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          strings.authSharedAccount,
                          textAlign: TextAlign.center,
                          style: BuilderType.small,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    required this.enabled,
    required this.newPassword,
    required this.textInputAction,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final bool enabled;
  final bool newPassword;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: _obscure
              ? strings.authShowPassword
              : strings.authHidePassword,
          onPressed: widget.enabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => BuilderCard(child: Text(text));
}

String _failureMessage(AppFailure failure, AppLocalizations strings) =>
    switch (failure.code) {
      AppFailureCode.invalidCredentials => strings.authInvalidCredentials,
      AppFailureCode.accountExists => strings.authAccountExists,
      AppFailureCode.weakPassword => strings.authWeakPassword,
      AppFailureCode.networkUnavailable => strings.authNetworkError,
      AppFailureCode.rateLimited => strings.authRateLimited,
      AppFailureCode.serviceUnavailable => strings.authUnavailable,
      AppFailureCode.unexpected => strings.authUnexpectedError,
    };

class AuthLegalPage extends ConsumerWidget {
  const AuthLegalPage({super.key, required this.privacy});
  final bool privacy;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final documents = ref
        .watch(authGatewayProvider)
        .documentsFor(Localizations.localeOf(context).languageCode);
    final document = documents != null && documents.isUsable
        ? privacy
              ? documents.privacy
              : documents.terms
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(privacy ? strings.authPrivacy : strings.authTerms),
        leading: IconButton(
          tooltip: strings.closePage,
          icon: const Icon(Icons.close),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/sign-in'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(document?.body ?? strings.authLegalUnavailable),
        ),
      ),
    );
  }
}
