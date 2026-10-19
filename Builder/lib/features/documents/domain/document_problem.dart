/// Why a document task stopped, with user-facing RU/KK text. Codes come from
/// the file contract (`file.*`, `job.*`, `consent.required`, `artifact.expired`).
enum DocumentProblem {
  unsupportedType('file.unsupported-type', false),
  tooLarge('file.too-large', false),
  encrypted('file.encrypted', false),
  corrupt('file.corrupt', false),
  noTextLayer('file.no-text-layer', false),
  partialText('file.partial-text', false),
  limitsExceeded('file.limits-exceeded', false),
  consentRequired('consent.required', false),
  alreadyActive('job.already-active', false),
  modelFailed('job.model-failed', true),
  buildFailed('job.build-failed', true),
  limitReached('job.limit-reached', true),
  unavailable('job.unavailable', true),
  artifactExpired('artifact.expired', false),

  /// The attachment or job no longer exists on the server (expired or deleted).
  expired('resource.expired', false),
  noSpace('client.no-space', false),
  integrity('client.integrity', true),
  noNetwork('client.no-network', true),
  auth('client.auth', false),
  unknown('client.unknown', true);

  const DocumentProblem(this.code, this.retryable);
  final String code;

  /// Whether starting the same task again can reasonably succeed.
  final bool retryable;

  static DocumentProblem fromCode(String? code) => values.firstWhere(
    (p) => p.code == code,
    orElse: () => unknown,
  );

  /// The file itself is the cause; another file is needed.
  bool get needsAnotherFile => switch (this) {
    unsupportedType ||
    tooLarge ||
    encrypted ||
    corrupt ||
    noTextLayer ||
    partialText ||
    limitsExceeded => true,
    _ => false,
  };

  String text({required bool kk}) {
    String t(String ru, String kz) => kk ? kz : ru;
    return switch (this) {
      unsupportedType => t(
        'Поддерживаются только файлы TXT, DOCX и PDF. Тип определяется по содержимому, а не по расширению.',
        'Тек TXT, DOCX және PDF файлдары қолдау табады. Түрі кеңейтімімен емес, мазмұнымен анықталады.',
      ),
      tooLarge => t(
        'Файл больше 10 МБ. Сократите его или выберите другой.',
        'Файл 10 МБ-тан үлкен. Қысқартыңыз немесе басқасын таңдаңыз.',
      ),
      encrypted => t(
        'Файл защищён паролем. Снимите защиту и загрузите снова.',
        'Файл құпиясөзбен қорғалған. Қорғанысты алып, қайта жүктеңіз.',
      ),
      corrupt => t(
        'Файл повреждён или не открывается. Проверьте его и загрузите снова.',
        'Файл бүлінген немесе ашылмайды. Тексеріп, қайта жүктеңіз.',
      ),
      noTextLayer => t(
        'В PDF нет текста — это скан. Распознавание сканов (OCR) не поддерживается: загрузите PDF с текстом, DOCX или TXT.',
        'PDF-те мәтін жоқ — бұл скан. Сканды тану (OCR) қолдау таппайды: мәтіні бар PDF, DOCX немесе TXT жүктеңіз.',
      ),
      partialText => t(
        'Текст в PDF извлекается не со всех страниц, документ получился бы неполным. Загрузите DOCX или TXT.',
        'PDF-тен мәтін барлық беттерден алынбайды, құжат толық болмас еді. DOCX немесе TXT жүктеңіз.',
      ),
      limitsExceeded => t(
        'Файл слишком большой по страницам или объёму текста. Загрузите часть документа.',
        'Файл беттері немесе мәтін көлемі бойынша тым үлкен. Құжаттың бір бөлігін жүктеңіз.',
      ),
      consentRequired => t(
        'Нужно подтвердить согласие на передачу файла в CraftAI.',
        'Файлды CraftAI-ға жіберуге келісімді растау қажет.',
      ),
      alreadyActive => t(
        'Для этого файла уже идёт обработка. Дождитесь её окончания или отмените.',
        'Бұл файл бойынша өңдеу жүріп жатыр. Аяқталуын күтіңіз немесе болдырмаңыз.',
      ),
      modelFailed => t(
        'Модель не смогла подготовить документ. Повторите попытку.',
        'Модель құжатты дайындай алмады. Әрекетті қайталаңыз.',
      ),
      buildFailed => t(
        'Не удалось собрать DOCX или PDF. Повторите попытку.',
        'DOCX немесе PDF құрастыру мүмкін болмады. Әрекетті қайталаңыз.',
      ),
      limitReached => t(
        'Достигнут лимит заданий. Подождите и повторите позже.',
        'Тапсырма лимитіне жеттіңіз. Күтіп, кейін қайталаңыз.',
      ),
      unavailable => t(
        'Сервис обработки временно недоступен. Повторите позже.',
        'Өңдеу сервисі уақытша қолжетімсіз. Кейінірек қайталаңыз.',
      ),
      artifactExpired => t(
        'Срок хранения готового документа истёк. Создайте его заново.',
        'Дайын құжаттың сақтау мерзімі аяқталды. Қайта жасаңыз.',
      ),
      expired => t(
        'Срок хранения файла или задания истёк. Начните заново.',
        'Файлдың немесе тапсырманың сақтау мерзімі аяқталды. Басынан бастаңыз.',
      ),
      noSpace => t(
        'Не хватает места на устройстве. Освободите память и скачайте снова.',
        'Құрылғыда орын жеткіліксіз. Жадты босатып, қайта жүктеңіз.',
      ),
      integrity => t(
        'Скачанный файл не совпал с данными сервера и был удалён. Скачайте снова.',
        'Жүктелген файл сервер деректеріне сәйкес келмеді және жойылды. Қайта жүктеңіз.',
      ),
      noNetwork => t(
        'Нет соединения. Задание сохранено и продолжится, когда связь появится.',
        'Байланыс жоқ. Тапсырма сақталды, байланыс пайда болғанда жалғасады.',
      ),
      auth => t(
        'Сессия истекла. Войдите в аккаунт заново.',
        'Сессия аяқталды. Аккаунтқа қайта кіріңіз.',
      ),
      unknown => t(
        'Не удалось выполнить задание. Повторите попытку.',
        'Тапсырманы орындау мүмкін болмады. Әрекетті қайталаңыз.',
      ),
    };
  }
}
