import 'package:builder/app/localization/app_localizations.dart';
import 'package:builder/features/documents/application/document_controller.dart';
import 'package:builder/features/documents/domain/document_models.dart';
import 'package:builder/features/documents/presentation/documents_page.dart';
import 'package:builder/features/documents/infrastructure/document_work_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_files_server.dart';

class FakePicker implements DocumentPicker {
  FakePicker(this.name, {this.size = 4096});
  String name;
  int size;
  @override
  Future<PickedDocument?> pick() async => PickedDocument(
    name: name,
    sizeBytes: size,
    readBytes: () async => List.filled(size, 66),
  );
}

Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<InMemoryDocumentWorkRepository> pumpPage(
  WidgetTester tester,
  FakeFilesServer server,
  FakePicker picker, {
  Locale locale = const Locale('ru'),
}) async {
  final repository = InMemoryDocumentWorkRepository();
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        builderFilesClientProvider.overrideWithValue(server.client),
        documentPickerProvider.overrideWithValue(picker),
        documentWorkRepositoryProvider.overrideWithValue(repository),
        documentStagingStoreProvider.overrideWithValue(InMemoryDocumentStagingStore()),
        documentPollIntervalProvider.overrideWithValue(const Duration(milliseconds: 20)),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: DocumentsPage(ownerId: 'teacher'),
      ),
    ),
  );
  await settle(tester, rounds: 2);
  return repository;
}

Future<void> startTask(WidgetTester tester, {bool agree = true}) async {
  await tester.tap(find.text('Добавить файл'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Выбрать файл'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Продолжить'));
  await tester.pumpAndSettle();
  if (!agree) {
    await tester.tap(find.text('Отмена'));
  } else {
    await tester.tap(find.text('Согласен, отправить'));
  }
  await tester.pump();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('consent names the file; after agreeing the document is produced', (tester) async {
    final server = FakeFilesServer();
    await pumpPage(tester, server, FakePicker('урок.docx'));
    await tester.tap(find.text('Добавить файл'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать файл'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('«урок.docx» будет передан на сервер CraftAI'), findsOneWidget);
    expect(server.requests, isEmpty, reason: 'nothing is sent before consent');

    await tester.tap(find.text('Согласен, отправить'));
    await tester.pump();
    await settle(tester);

    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('example.docx'), findsOneWidget);
    expect(server.lastUploadFields['consentRevision'], documentConsentRevision);
    expect(server.attachmentsCreated, 1);
    expect(server.jobsCreated, 1);
    await finish(tester);
  });

  testWidgets('declining the consent sends nothing and stores nothing', (tester) async {
    final server = FakeFilesServer();
    final repository = await pumpPage(tester, server, FakePicker('урок.docx'));
    await startTask(tester, agree: false);
    await settle(tester, rounds: 5);
    expect(server.requests, isEmpty);
    expect(await repository.list('teacher'), isEmpty);
    expect(find.text('Заданий пока нет.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('an unsupported or oversized file is refused before consent', (tester) async {
    final server = FakeFilesServer();
    final picker = FakePicker('макрос.exe');
    await pumpPage(tester, server, picker);
    await tester.tap(find.text('Добавить файл'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать файл'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Поддерживаются только файлы TXT, DOCX и PDF'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Передача файла'), findsNothing);

    picker
      ..name = 'большой.pdf'
      ..size = maxDocumentBytes + 1;
    await tester.tap(find.text('макрос.exe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Файл больше 10 МБ'), findsOneWidget);
    expect(server.requests, isEmpty);
    await finish(tester);
  });

  testWidgets('a scanned PDF is explained, OCR is not offered, and a new file can be chosen', (tester) async {
    final server = FakeFilesServer()..uploadError = (422, 'file.no-text-layer');
    await pumpPage(tester, server, FakePicker('скан.pdf'));
    await startTask(tester);
    await settle(tester, rounds: 10);

    expect(find.textContaining('это скан'), findsOneWidget);
    expect(find.text('Выберите другой файл.'), findsOneWidget);
    expect(find.text('Начать заново'), findsOneWidget);
    expect(server.jobsCreated, 0);
    await finish(tester);
  });

  testWidgets('no connection keeps the task and "try now" resumes it', (tester) async {
    final server = FakeFilesServer()..offline = true;
    await pumpPage(tester, server, FakePicker('урок.txt'));
    await startTask(tester);
    await settle(tester, rounds: 6);

    expect(find.textContaining('Нет соединения'), findsOneWidget);
    expect(find.text('Повторить сейчас'), findsOneWidget);

    server.offline = false;
    await tester.tap(find.text('Повторить сейчас'));
    await settle(tester);
    expect(find.text('Готово'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('cancel asks the server and shows the canceled state', (tester) async {
    final server = FakeFilesServer()..script = ['queued'];
    await pumpPage(tester, server, FakePicker('урок.docx'));
    await startTask(tester);
    await settle(tester, rounds: 6);
    expect(find.text('В очереди…'), findsOneWidget);

    await tester.tap(find.text('Отменить'));
    await settle(tester, rounds: 6);
    expect(server.cancelRequested, isTrue);
    expect(find.text('Отменено'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Kazakh screen and consent are available', (tester) async {
    final server = FakeFilesServer();
    await pumpPage(tester, server, FakePicker('сабақ.docx'), locale: const Locale('kk'));
    expect(find.text('DOCX және PDF құжаттары'), findsOneWidget);
    await tester.tap(find.text('Файл қосу'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Файлды таңдау'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Жалғастыру'));
    await tester.pumpAndSettle();
    expect(find.textContaining('«сабақ.docx» файлы'), findsOneWidget);
    await finish(tester);
  });
}
