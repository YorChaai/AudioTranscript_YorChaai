import os
import re

dir_path = r'd:\2. Organize\1. Projects\audio convert to txt\flutter_app\lib\screens'
for filename in os.listdir(dir_path):
    if filename.endswith('.dart'):
        file_path = os.path.join(dir_path, filename)
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        # Replace widget.onNavigate?(...) with GoRouter calls
        content = re.sub(r'widget\.onNavigate\?\.call\(\s*2\s*,\s*filePath:\s*([^)]+)\)', r"context.go('/editor?file=${\1}')", content)
        content = re.sub(r'widget\.onNavigate\?\.call\(\s*5\s*,\s*filePath:\s*([^)]+)\)', r"context.go('/summary?file=${\1}')", content)
        
        def route_mapper(m):
            routes = ['/', '/transcribe', '/editor', '/pdf', '/history', '/summary', '/browser']
            return f"context.go('{routes[int(m.group(1))]}')"
            
        content = re.sub(r'widget\.onNavigate\?\.call\(\s*(\d+)\s*\)', route_mapper, content)
        
        # In home_screen.dart, it's onNavigate(index)
        content = re.sub(r'onNavigate\(\s*1\s*\)', "context.go('/transcribe')", content)
        content = re.sub(r'onNavigate\(\s*3\s*\)', "context.go('/pdf')", content)
        
        if 'context.go' in content and 'go_router' not in content:
            content = "import 'package:go_router/go_router.dart';\n" + content
            
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f'Updated {filename}')
