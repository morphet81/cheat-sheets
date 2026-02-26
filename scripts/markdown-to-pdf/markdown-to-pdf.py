#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["markdown>=3.5", "weasyprint>=60.0"]
# ///
"""
Convert a Markdown document to a styled PDF.

Renders Markdown to HTML (with support for tables, fenced code blocks, and
table of contents) then produces a paginated A4 PDF using WeasyPrint.

Usage:
    python markdown-to-pdf.py input.md [-o output.pdf]
    uv run markdown-to-pdf.py input.md

If no output path is given, the output file is named <input>.pdf.

System dependencies (required by WeasyPrint):
    macOS:    brew install cairo pango gdk-pixbuf libffi
    Ubuntu:   sudo apt install libcairo2-dev libpango1.0-dev libgdk-pixbuf2.0-dev libffi-dev
"""

import argparse
import re
import shutil
import sys
from pathlib import Path

try:
    import markdown as md_lib
except ImportError:
    print("Error: the 'markdown' package is required but not installed.\n", file=sys.stderr)
    print("Install it with:  pip install markdown\n", file=sys.stderr)
    if shutil.which("uv"):
        print(f"Or run directly with uv:  uv run {sys.argv[0]} <input.md>", file=sys.stderr)
    sys.exit(1)

try:
    from weasyprint import HTML
except ImportError:
    print("Error: the 'weasyprint' package is required but not installed.\n", file=sys.stderr)
    print("Install it with:  pip install weasyprint", file=sys.stderr)
    print("Note: weasyprint also requires system libraries (cairo, pango, gdk-pixbuf).", file=sys.stderr)
    print("  macOS:    brew install cairo pango gdk-pixbuf libffi", file=sys.stderr)
    print("  Ubuntu:   sudo apt install libcairo2-dev libpango1.0-dev libgdk-pixbuf2.0-dev libffi-dev\n", file=sys.stderr)
    if shutil.which("uv"):
        print(f"Or run directly with uv:  uv run {sys.argv[0]} <input.md>", file=sys.stderr)
    sys.exit(1)

CSS = """\
@page {
    size: A4;
    margin: 2cm;
}
body {
    font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    color: #222;
}
h1 { font-size: 22pt; margin-top: 1.5em; margin-bottom: 0.5em; }
h2 { font-size: 17pt; margin-top: 1.3em; margin-bottom: 0.4em; }
h3 { font-size: 13pt; margin-top: 1.1em; margin-bottom: 0.3em; }
p  { margin-bottom: 0.8em; }
ul, ol { margin-bottom: 0.8em; padding-left: 1.5em; }
table { border-collapse: collapse; width: 100%; margin-bottom: 1em; }
th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
th { background: #f5f5f5; }
hr { border: none; border-top: 1px solid #ddd; margin: 2em 0; }
code { background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-size: 0.9em; }
pre { background: #f4f4f4; padding: 12px; border-radius: 5px; overflow-x: auto; }
img { max-width: 100%; }
"""


def markdown_to_pdf(md_path: Path, pdf_path: Path) -> None:
    """Convert a Markdown file to a styled PDF."""
    md_text = md_path.read_text(encoding="utf-8")

    # Strip page markers that may have been added by pdf-to-markdown
    md_text = re.sub(r"<!-- page \d+ -->", "", md_text)

    html_body = md_lib.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc"],
    )

    full_html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
{CSS}
</style>
</head>
<body>
{html_body}
</body>
</html>"""

    HTML(string=full_html).write_pdf(str(pdf_path))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a Markdown document to a styled PDF."
    )
    parser.add_argument("md", type=Path, help="Source Markdown file")
    parser.add_argument("-o", "--output", type=Path, help="Output .pdf file (default: <input>.pdf)")

    args = parser.parse_args()

    md_path = args.md.resolve()
    if not md_path.exists():
        sys.exit(f"Error: Markdown file not found: {md_path}")
    if md_path.suffix.lower() not in (".md", ".markdown", ".mdown", ".mkd"):
        print(f"Warning: expected a Markdown file, got: {md_path.suffix}", file=sys.stderr)

    out = args.output or md_path.with_suffix(".pdf")
    out = out.resolve()
    markdown_to_pdf(md_path, out)
    print(f"PDF saved to: {out}")


if __name__ == "__main__":
    main()
