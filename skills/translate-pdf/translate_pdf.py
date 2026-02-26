#!/usr/bin/env python3
"""
Translate a PDF document while preserving its structure.

Steps:
  1. Extract text from the source PDF into structured Markdown.
  2. Accept a pre-translated Markdown file.
  3. Build a new PDF from the translated Markdown.

Dependencies (install via pip):
  pip install pymupdf markdown weasyprint
"""

import argparse
import re
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    sys.exit(
        "ERROR: 'pymupdf' is not installed.\n"
        "Install it with:  pip install pymupdf"
    )


# ---------------------------------------------------------------------------
# Step 1 – Extract PDF to structured Markdown
# ---------------------------------------------------------------------------

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

    # Clean cell values: replace None with empty string, strip whitespace
    cleaned = []
    for row in rows:
        cleaned.append([
            (cell.strip().replace("\n", " ") if cell else "")
            for cell in row
        ])

    if not cleaned:
        return ""

    col_count = max(len(row) for row in cleaned)

    # Pad rows to uniform column count
    for row in cleaned:
        while len(row) < col_count:
            row.append("")

    # Build Markdown table
    lines = []
    # Header row
    lines.append("| " + " | ".join(cleaned[0]) + " |")
    # Separator
    lines.append("| " + " | ".join("---" for _ in range(col_count)) + " |")
    # Data rows
    for row in cleaned[1:]:
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines) + "\n\n"


def extract_pdf_to_markdown(pdf_path: Path) -> str:
    """Extract text from a PDF and return structured Markdown."""
    doc = fitz.open(str(pdf_path))
    md_parts: list[str] = []

    for page_num, page in enumerate(doc, start=1):
        md_parts.append(f"<!-- page {page_num} -->\n")

        # --- Table detection ---
        # Detect tables on the page so we can render them as Markdown tables
        # and skip text blocks that overlap with table regions.
        tables = []
        table_rects = []
        try:
            tab_finder = page.find_tables()
            for table in tab_finder.tables:
                tables.append(table)
                table_rects.append(table.bbox)  # (x0, y0, x1, y1)
        except Exception:
            # find_tables() may not be available in older PyMuPDF versions;
            # fall back to no table detection.
            pass

        # Collect all items (text blocks + tables) with their vertical position
        # so we can output them in reading order.
        items: list[tuple[float, str]] = []

        # Add tables as Markdown
        for table, rect in zip(tables, table_rects):
            md_table = _table_to_markdown(table)
            if md_table:
                items.append((rect[1], md_table))  # y0 as sort key

        # Process text blocks, skipping those that overlap with tables
        blocks = page.get_text("dict", flags=fitz.TEXT_PRESERVE_WHITESPACE)["blocks"]

        for block in blocks:
            if block["type"] == 1:
                # Image block – note it but skip content
                items.append((block["bbox"][1], "![image]()\n\n"))
                continue

            if block["type"] != 0:
                continue

            # Skip blocks that overlap with any detected table
            block_rect = block["bbox"]  # (x0, y0, x1, y1)
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

                    size = span["size"]
                    flags = span["flags"]
                    is_bold = flags & 2 ** 4  # bit 4 = bold
                    is_italic = flags & 2 ** 1  # bit 1 = italic

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

            # Heuristic: detect headings by font size of the first span
            first_span = block["lines"][0]["spans"][0] if block["lines"] and block["lines"][0]["spans"] else None
            if first_span:
                size = first_span["size"]
                combined = " ".join(block_lines)
                # Large text and short → likely a heading
                if size >= 20 and len(combined) < 200:
                    items.append((block_rect[1], f"# {combined}\n\n"))
                    continue
                elif size >= 16 and len(combined) < 200:
                    items.append((block_rect[1], f"## {combined}\n\n"))
                    continue
                elif size >= 13 and len(combined) < 200 and (first_span["flags"] & 2 ** 4):
                    items.append((block_rect[1], f"### {combined}\n\n"))
                    continue

            # Regular paragraph – join lines
            paragraph = " ".join(block_lines)
            items.append((block_rect[1], f"{paragraph}\n\n"))

        # Sort all items by vertical position to preserve reading order
        items.sort(key=lambda x: x[0])
        for _, content in items:
            md_parts.append(content)

        md_parts.append("\n---\n\n")

    doc.close()
    return "".join(md_parts)


# ---------------------------------------------------------------------------
# Step 3 – Build PDF from translated Markdown
# ---------------------------------------------------------------------------

def markdown_to_pdf(md_path: Path, pdf_path: Path) -> None:
    """Convert a Markdown file to a styled PDF."""
    try:
        import markdown as md_lib
    except ImportError:
        sys.exit(
            "ERROR: 'markdown' is not installed.\n"
            "Install it with:  pip install markdown"
        )

    try:
        from weasyprint import HTML
    except ImportError:
        sys.exit(
            "ERROR: 'weasyprint' is not installed.\n"
            "Install it with:  pip install weasyprint\n"
            "Note: weasyprint also requires system libraries (cairo, pango, gdk-pixbuf).\n"
            "See https://doc.courtbouillon.org/weasyprint/stable/first_steps.html"
        )

    md_text = md_path.read_text(encoding="utf-8")

    # Strip page markers and horizontal rules used as page separators
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
  @page {{
    size: A4;
    margin: 2cm;
  }}
  body {{
    font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    color: #222;
  }}
  h1 {{ font-size: 22pt; margin-top: 1.5em; margin-bottom: 0.5em; }}
  h2 {{ font-size: 17pt; margin-top: 1.3em; margin-bottom: 0.4em; }}
  h3 {{ font-size: 13pt; margin-top: 1.1em; margin-bottom: 0.3em; }}
  p  {{ margin-bottom: 0.8em; }}
  ul, ol {{ margin-bottom: 0.8em; padding-left: 1.5em; }}
  table {{ border-collapse: collapse; width: 100%; margin-bottom: 1em; }}
  th, td {{ border: 1px solid #ccc; padding: 6px 10px; text-align: left; }}
  th {{ background: #f5f5f5; }}
  hr {{ border: none; border-top: 1px solid #ddd; margin: 2em 0; }}
  code {{ background: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-size: 0.9em; }}
  pre {{ background: #f4f4f4; padding: 12px; border-radius: 5px; overflow-x: auto; }}
  img {{ max-width: 100%; }}
</style>
</head>
<body>
{html_body}
</body>
</html>"""

    HTML(string=full_html).write_pdf(str(pdf_path))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Translate PDF helper – extract or rebuild."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # extract
    p_extract = sub.add_parser("extract", help="Extract PDF to Markdown")
    p_extract.add_argument("pdf", type=Path, help="Source PDF file")
    p_extract.add_argument("-o", "--output", type=Path, help="Output .md file")

    # build
    p_build = sub.add_parser("build", help="Build PDF from Markdown")
    p_build.add_argument("md", type=Path, help="Source Markdown file")
    p_build.add_argument("-o", "--output", type=Path, help="Output .pdf file")

    args = parser.parse_args()

    if args.command == "extract":
        pdf_path = args.pdf.resolve()
        if not pdf_path.exists():
            sys.exit(f"ERROR: PDF not found: {pdf_path}")

        md_text = extract_pdf_to_markdown(pdf_path)

        out = args.output or pdf_path.with_suffix(".md")
        out.write_text(md_text, encoding="utf-8")
        print(f"Extracted Markdown saved to: {out}")

    elif args.command == "build":
        md_path = args.md.resolve()
        if not md_path.exists():
            sys.exit(f"ERROR: Markdown file not found: {md_path}")

        out = args.output or md_path.with_suffix(".pdf")
        markdown_to_pdf(md_path, out)
        print(f"PDF saved to: {out}")


if __name__ == "__main__":
    main()
