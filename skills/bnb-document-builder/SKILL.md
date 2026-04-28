---
name: bnb-document-builder
description: Convert markdown files to Brand New Box branded PDFs. Use only when explicitly asked to create a BNB document, a Brand New Box document, or to use the BNB document builder. Do not use for general PDF or document generation.
---

# BNB Document Builder

Converts markdown to styled PDFs with BNB branding (cover page, headers, footers, syntax highlighting, mermaid diagrams).

## Prerequisites

The document builder lives at `~/Workspaces/bnb-document-builder`. It requires a Python virtualenv with dependencies installed:

```bash
cd ~/Workspaces/bnb-document-builder
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

System dependency (macOS): `brew install pango`

Optional for mermaid diagrams: `npm install -g @mermaid-js/mermaid-cli`

## Usage

Convert any markdown file to PDF from any directory:

```bash
# Basic — outputs input.pdf in the same directory
source ~/Workspaces/bnb-document-builder/.venv/bin/activate && python ~/Workspaces/bnb-document-builder/md_to_pdf.py /path/to/document.md

# Specify output path
source ~/Workspaces/bnb-document-builder/.venv/bin/activate && python ~/Workspaces/bnb-document-builder/md_to_pdf.py /path/to/document.md /path/to/output.pdf

# HTML preview only
source ~/Workspaces/bnb-document-builder/.venv/bin/activate && python ~/Workspaces/bnb-document-builder/md_to_pdf.py /path/to/document.md --html

# Both HTML and PDF
source ~/Workspaces/bnb-document-builder/.venv/bin/activate && python ~/Workspaces/bnb-document-builder/md_to_pdf.py /path/to/document.md --preview
```

## Frontmatter

Add YAML frontmatter to generate a branded cover page:

```yaml
---
title: Project Documentation
subtitle: Technical Specification v2.0
author: Brand New Box
date: 2026-03-26
---
```

## Gotchas

- **Frontmatter is required.** The document won't generate correctly (e.g. missing margins on the first page) if YAML frontmatter is not included at the top of the markdown file. Always add at least a `title` in the frontmatter block.

## Supported Features

- All standard markdown (headings, bold, italic, lists, links, images)
- Fenced code blocks with syntax highlighting
- Tables
- Task lists (`- [x]` / `- [ ]`)
- Footnotes
- Admonitions: `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`, `> [!IMPORTANT]`, `> [!CAUTION]`
- Mermaid diagrams (requires mermaid-cli)
- Page breaks: `<!-- pagebreak -->`

## Reference

See `~/Workspaces/bnb-document-builder/README.md` for full documentation including color/font customization.

See `~/Workspaces/bnb-document-builder/sample_complete.md` for a reference file demonstrating all features.
