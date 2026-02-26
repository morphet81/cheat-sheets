#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["pymupdf>=1.23.0"]
# ///
"""
Convert a PDF document to structured Markdown.

Extracts text from each page preserving headings, bold/italic formatting,
and tables. Tables are detected using PyMuPDF's find_tables() and rendered
as proper Markdown table syntax.

Usage:
    python pdf-to-markdown.py input.pdf [-o output.md]
    uv run pdf-to-markdown.py input.pdf

If no output path is given, the output file is named <input>.md.
"""

import argparse
import shutil
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    print("Error: the 'pymupdf' package is required but not installed.\n", file=sys.stderr)
    print("Install it with one of the following:\n", file=sys.stderr)
    print("  pip install 'pymupdf>=1.23.0'", file=sys.stderr)
    print("  pipx install 'pymupdf>=1.23.0'", file=sys.stderr)
    if shutil.which("uv"):
        print("\nOr run this script directly with uv (dependencies are handled automatically):\n", file=sys.stderr)
        print(f"  uv run {sys.argv[0]} <input.pdf>", file=sys.stderr)
    else:
        print("\nAlternatively, install uv (https://docs.astral.sh/uv/) and run with:\n", file=sys.stderr)
        print(f"  uv run {sys.argv[0]} <input.pdf>", file=sys.stderr)
    sys.exit(1)


def _rects_overlap(r1, r2, tolerance=2.0) -> bool:
    """Check if two rectangles (x0, y0, x1, y1) overlap within a tolerance."""
    return not (
        r1[2] < r2[0] - tolerance
        or r1[0] > r2[2] + tolerance
        or r1[3] < r2[1] - tolerance
        or r1[1] > r2[3] + tolerance
    )


def _table_to_markdown(table) -> str:
    """Convert a PyMuPDF table object to a Markdown table string."""
    rows = table.extract()
    if not rows:
        return ""

    cleaned = []
    for row in rows:
        cleaned.append([
            (cell.strip().replace("\n", " ") if cell else "")
            for cell in row
        ])

    if not cleaned:
        return ""

    col_count = max(len(row) for row in cleaned)

    for row in cleaned:
        while len(row) < col_count:
            row.append("")

    lines = []
    lines.append("| " + " | ".join(cleaned[0]) + " |")
    lines.append("| " + " | ".join("---" for _ in range(col_count)) + " |")
    for row in cleaned[1:]:
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines) + "\n\n"


def extract_pdf_to_markdown(pdf_path: Path) -> str:
    """Extract text from a PDF and return structured Markdown."""
    doc = fitz.open(str(pdf_path))
    md_parts: list[str] = []

    for page_num, page in enumerate(doc, start=1):
        md_parts.append(f"<!-- page {page_num} -->\n")

        # Detect tables on the page
        tables = []
        table_rects = []
        try:
            tab_finder = page.find_tables()
            for table in tab_finder.tables:
                tables.append(table)
                table_rects.append(table.bbox)
        except Exception:
            pass

        # Collect all items with their vertical position for reading order
        items: list[tuple[float, str]] = []

        for table, rect in zip(tables, table_rects):
            md_table = _table_to_markdown(table)
            if md_table:
                items.append((rect[1], md_table))

        blocks = page.get_text("dict", flags=fitz.TEXT_PRESERVE_WHITESPACE)["blocks"]

        for block in blocks:
            if block["type"] == 1:
                items.append((block["bbox"][1], "![image]()\n\n"))
                continue

            if block["type"] != 0:
                continue

            block_rect = block["bbox"]
            if any(_rects_overlap(block_rect, tr) for tr in table_rects):
                continue

            block_lines: list[str] = []
            for line in block["lines"]:
                spans = line["spans"]
                if not spans:
                    continue

                line_text = ""
                for span in spans:
                    text = span["text"]
                    if not text.strip():
                        line_text += text
                        continue

                    flags = span["flags"]
                    is_bold = flags & 2 ** 4
                    is_italic = flags & 2 ** 1

                    fragment = text
                    if is_bold and is_italic:
                        fragment = f"***{text.strip()}***"
                    elif is_bold:
                        fragment = f"**{text.strip()}**"
                    elif is_italic:
                        fragment = f"*{text.strip()}*"

                    line_text += fragment

                line_text = line_text.rstrip()
                if line_text:
                    block_lines.append(line_text)

            if not block_lines:
                continue

            first_span = block["lines"][0]["spans"][0] if block["lines"] and block["lines"][0]["spans"] else None
            if first_span:
                size = first_span["size"]
                combined = " ".join(block_lines)
                if size >= 20 and len(combined) < 200:
                    items.append((block_rect[1], f"# {combined}\n\n"))
                    continue
                elif size >= 16 and len(combined) < 200:
                    items.append((block_rect[1], f"## {combined}\n\n"))
                    continue
                elif size >= 13 and len(combined) < 200 and (first_span["flags"] & 2 ** 4):
                    items.append((block_rect[1], f"### {combined}\n\n"))
                    continue

            paragraph = " ".join(block_lines)
            items.append((block_rect[1], f"{paragraph}\n\n"))

        items.sort(key=lambda x: x[0])
        for _, content in items:
            md_parts.append(content)

        md_parts.append("\n---\n\n")

    doc.close()
    return "".join(md_parts)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert a PDF document to structured Markdown."
    )
    parser.add_argument("pdf", type=Path, help="Source PDF file")
    parser.add_argument("-o", "--output", type=Path, help="Output .md file (default: <input>.md)")

    args = parser.parse_args()

    pdf_path = args.pdf.resolve()
    if not pdf_path.exists():
        sys.exit(f"Error: PDF not found: {pdf_path}")
    if pdf_path.suffix.lower() != ".pdf":
        sys.exit(f"Error: expected a .pdf file, got: {pdf_path.suffix}")

    md_text = extract_pdf_to_markdown(pdf_path)

    out = args.output or pdf_path.with_suffix(".md")
    out = out.resolve()
    out.write_text(md_text, encoding="utf-8")
    print(f"Markdown saved to: {out}")


if __name__ == "__main__":
    main()
