import os
import re

# 颜色映射
color_mapping = {
    '#fff': 'ColorResource.dialog_background',
    '#f5f5f5': 'ColorResource.background_secondary',
    '#fafafa': 'ColorResource.background_tertiary',
    '#f0f0f0': 'ColorResource.button_secondary_background',
    '#666': 'ColorResource.text_secondary',
    '#999': 'ColorResource.text_tertiary',
    '#007aff': 'ColorResource.accent_primary',
    '#ff4d4f': 'ColorResource.button_danger_background',
    '#e0f0ff': 'ColorResource.background_selected',
    '#f8f8f8': 'ColorResource.card_background',
    '#888': 'ColorResource.text_tertiary',
    'transparent': 'Color.Transparent',
    'Color.Black': 'ColorResource.text_primary',
    'Color.White': 'ColorResource.text_inverse'
}

# 读取文件
with open('entry/src/main/ets/pages/Index.ets', 'r', encoding='utf-8') as f:
    content = f.read()

# 替换颜色
for old_color, new_color in color_mapping.items():
    # 处理 backgroundColor
    pattern = f"backgroundColor\\(['\"]{old_color}['\"]\\)"
    replacement = f"backgroundColor({new_color})"
    content = re.sub(pattern, replacement, content)
    
    # 处理 fontColor
    pattern = f"fontColor\\(['\"]{old_color}['\"]\\)"
    replacement = f"fontColor({new_color})"
    content = re.sub(pattern, replacement, content)
    
    # 处理 Color.Black 和 Color.White
    if old_color.startswith('Color.'):
        pattern = old_color
        replacement = new_color
        content = content.replace(pattern, replacement)

# 写入文件
with open('entry/src/main/ets/pages/Index.ets', 'w', encoding='utf-8') as f:
    f.write(content)

print("颜色替换完成！")