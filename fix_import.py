import os
file_path = r'd:\2. Organize\1. Projects\audio convert to txt\flutter_app\lib\screens\transcribe_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'package:go_router/go_router.dart' not in content:
    content = "import 'package:go_router/go_router.dart';\n" + content

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
