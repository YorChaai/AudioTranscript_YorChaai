import os

file_path = r'd:\2. Organize\1. Projects\audio convert to txt\flutter_app\lib\main.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

if "import 'package:provider/provider.dart';" not in content:
    content = "import 'package:provider/provider.dart';\n" + content

if "import 'providers/transcribe_provider.dart';" not in content:
    content = "import 'providers/transcribe_provider.dart';\n" + content

replacement = """runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TranscribeProvider()),
      ],
      child: const MyApp(),
    ),
  );"""

content = content.replace('runApp(const MyApp());', replacement)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
