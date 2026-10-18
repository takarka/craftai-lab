/// Result of preparing a call or message draft (F14-07, F14-08).
class CommunicationPreparationResult {
  final String action;
  final String phoneNumber;
  final String? recipientName;
  final String? messageBody;
  final String status;
  final String userMessage;

  const CommunicationPreparationResult({
    required this.action,
    required this.phoneNumber,
    this.recipientName,
    this.messageBody,
    required this.status,
    required this.userMessage,
  });

  bool get hasMessageBody => messageBody != null && messageBody!.isNotEmpty;
  String get telUri => 'tel:$phoneNumber';
  String get smsUri => messageBody != null
      ? 'sms:$phoneNumber?body=${Uri.encodeComponent(messageBody!)}'
      : 'sms:$phoneNumber';

  Map<String, dynamic> toMap() {
    return {
      'action': action,
      'phone_number': phoneNumber,
      'recipient_name': recipientName,
      'message_body': messageBody,
      'status': status,
      'user_message': userMessage,
    };
  }
}

/// Adapter for preparing calls and SMS drafts without reading SMS inbox or auto-dialing (F14-07, F14-08).
class CommunicationAdapter {
  const CommunicationAdapter();

  /// Prepares communication intent and returns preview for teacher confirmation.
  Future<CommunicationPreparationResult> prepareCallOrMessage({
    required String phoneNumber,
    String? recipientName,
    String? messageBody,
  }) async {
    final cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanedNumber.length < 5) {
      throw ArgumentError('Некорректный номер телефона: $phoneNumber');
    }

    final isSms = messageBody != null && messageBody.trim().isNotEmpty;

    if (isSms) {
      return CommunicationPreparationResult(
        action: 'sms_draft',
        phoneNumber: cleanedNumber,
        recipientName: recipientName?.trim(),
        messageBody: messageBody.trim(),
        status: 'draft_prepared',
        userMessage: 'Подготовлен черновик SMS для ${recipientName ?? cleanedNumber}. '
            'Для отправки откройте системное приложение сообщений (автоматическая отправка отключена в целях безопасности).',
      );
    } else {
      return CommunicationPreparationResult(
        action: 'phone_call',
        phoneNumber: cleanedNumber,
        recipientName: recipientName?.trim(),
        status: 'dialer_ready',
        userMessage: 'Подготовлен номер $cleanedNumber (${recipientName ?? "Контакт"}). '
            'Номер будет передан в приложение «Телефон» для ручного звонка (ассистент не звонит самостоятельно).',
      );
    }
  }
}
