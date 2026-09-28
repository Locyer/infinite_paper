import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/canvas_controller.dart';
import 'models/canvas_models.dart';
import 'pages/home_page.dart';
import 'services/document_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(InfinitePaperApp(repository: FileDocumentRepository()));
}

class InfinitePaperApp extends StatelessWidget {
  const InfinitePaperApp({super.key, required this.repository});

  final DocumentRepository repository;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => CanvasController(repository: repository)..open(),
        child: Consumer<CanvasController>(
          builder: (context, controller, _) => MaterialApp(
            title: '无限草稿纸',
            debugShowCheckedModeBanner: false,
            themeMode: switch (controller.themeMode) {
              AppThemeMode.system => ThemeMode.system,
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
            },
            theme: ThemeData(
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xff4f46e5)),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff818cf8),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            home: const HomePage(),
          ),
        ),
      );
}
