import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../session/session_repository.dart';
import 'push_registration_service.dart';
import 'push_providers.dart';

class PushSettingsCard extends ConsumerStatefulWidget {
  const PushSettingsCard({super.key, required this.ownerId});
  final String ownerId;
  @override
  ConsumerState<PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends ConsumerState<PushSettingsCard> {
  bool _busy = false;
  Future<void> _action(
    Future<void> Function(PushRegistrationService) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider).value;
      if (session is! AuthenticatedSession ||
          session.ownerId != widget.ownerId) {
        return;
      }
      final service = ref.read(pushRegistrationServiceProvider);
      await service.setOwner(
        widget.ownerId,
        locale: Localizations.localeOf(context).languageCode == 'kk'
            ? 'kk'
            : 'ru',
      );
      final current = ref.read(sessionProvider).value;
      if (!mounted ||
          current is! AuthenticatedSession ||
          current.ownerId != widget.ownerId) {
        return;
      }
      await action(service);
    } catch (_) {
      // The card reports state through the service; startup/storage failures do
      // not crash the schedules screen or expose configuration/token details.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kk = Localizations.localeOf(context).languageCode == 'kk';
    String t(String ru, String kz) => kk ? kz : ru;
    final status =
        ref.watch(pushStatusProvider).asData?.value ?? PushStatus.off;
    final message = switch (status) {
      PushStatus.off => t(
        'Уведомления о результатах выключены.',
        'Нәтиже хабарламалары өшірілген.',
      ),
      PushStatus.unavailable => t(
        'Push не настроен или не поддерживается на этой платформе.',
        'Push бапталмаған немесе бұл платформада қолдау жоқ.',
      ),
      PushStatus.denied => t(
        'Разрешение уведомлений не получено. Его можно изменить в настройках телефона.',
        'Хабарламаларға рұқсат жоқ. Оны телефон баптауларында өзгертуге болады.',
      ),
      PushStatus.waitingForToken => t(
        'Ожидается регистрация телефона. Обновите после подключения к сети.',
        'Телефон тіркелуі күтілуде. Желіге қосылған соң жаңартыңыз.',
      ),
      PushStatus.registered => t(
        'Устройство зарегистрировано для уведомлений. Доставка не гарантируется.',
        'Құрылғы хабарламалар үшін тіркелген. Жеткізуге кепілдік жоқ.',
      ),
      PushStatus.failed => t(
        'Регистрация не подтверждена. Обновите при доступной сети.',
        'Тіркелу расталмады. Желі қолжетімді болғанда жаңартыңыз.',
      ),
      PushStatus.revokePending => t(
        'Отключение не полностью подтверждено. Повторите при доступной сети.',
        'Өшіру толық расталмады. Желі қолжетімді болғанда қайталаңыз.',
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                'Уведомления о готовом результате',
                'Дайын нәтиже туралы хабарламалар',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(message),
            Text(
              t(
                'Результаты доступны в истории и без push. Напоминания календаря настраиваются отдельно.',
                'Нәтижелер push болмаса да тарихта қолжетімді. Күнтізбе еске салулары бөлек бапталады.',
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _action((s) => s.enable()),
                  child: Text(t('Включить push', 'Push қосу')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _action((s) => s.refresh()),
                  child: Text(t('Обновить регистрацию', 'Тіркелуді жаңарту')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _action((s) => s.disable()),
                  child: Text(t('Выключить push', 'Push өшіру')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
