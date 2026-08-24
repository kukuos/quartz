---
title: Test
description: 部署验收测试页，验证 WikiLink、图片嵌入、Callout、代码块等功能。
tags:
  - 测试
date: 2026-08-24
---

# Test

这是一篇验收测试笔记，用来确认部署链路的各项功能是否正常。

## WikiLink 测试

- 普通链接：[[中文标题测试]]
- 带别名的链接：[[中文标题测试|点这里看中文页面]]
- 回首页：[[index|首页]]

## 图片嵌入测试

Obsidian 嵌入语法（图片存放在 Vault 的 `附件/` 目录，不在公共目录内）：

![[test.png]]

## Callout 测试

> [!note] 提示
> 这是一个 Obsidian Callout，应该显示为带图标的提示框。

> [!warning] 注意
> 这是警告样式的 Callout。

## 代码块测试

```bash
# 部署命令
bash /www/app/quartz/deploy.sh
```

```python
def hello():
    print("中文注释测试")
```

## 表格测试

| 项目 | 状态 |
| ---- | ---- |
| HTTPS | 待验证 |
| 搜索 | 待验证 |
| 图片 | 待验证 |

## 任务列表

- [x] 创建测试笔记
- [ ] 验证线上访问

## 端到端发布测试

本段由端到端测试追加，用于验证「改笔记 → publish.ps1 → 网站更新」整条链路。

测试标记：E2E-VERIFY-20260824
