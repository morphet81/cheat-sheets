#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["pypdf>=4.0"]
# ///
"""
Reorder pages of a PDF scanned from a single-sided auto-document feeder (ADF).

When a scanner doesn't support duplex (double-sided) scanning, you scan a
two-sided document in two passes:
  1. Place the stack face-up → scans all FRONT (odd) pages in order: 1, 3, 5, ...
  2. Flip the stack face-up → scans all BACK (even) pages in reverse: N, N-2, ..., 4, 2

This script takes the resulting PDF and reorders the pages to the correct
sequential order: 1, 2, 3, 4, 5, ..., N.

Usage:
    python reorder-duplex-pdf.py input.pdf [-o output.pdf]
    python reorder-duplex-pdf.py input.pdf --dry-run

If no output path is given, the output file is named <input>-reordered.pdf.
"""

import argparse
import math
import shutil
import sys
from pathlib import Path

try:
    from pypdf import PdfReader, PdfWriter
except ImportError:
    print("Error: the 'pypdf' package is required but not installed.\n", file=sys.stderr)
    print("Install it with one of the following:\n", file=sys.stderr)
    print("  pip install 'pypdf>=4.0'", file=sys.stderr)
    print("  pipx install 'pypdf>=4.0'", file=sys.stderr)
    if shutil.which("uv"):
        print("\nOr run this script directly with uv (dependencies are handled automatically):\n", file=sys.stderr)
        print(f"  uv run {sys.argv[0]} <input.pdf>", file=sys.stderr)
    else:
        print("\nAlternatively, install uv (https://docs.astral.sh/uv/) and run with:\n", file=sys.stderr)
        print(f"  uv run {sys.argv[0]} <input.pdf>", file=sys.stderr)
    sys.exit(1)


def compute_page_order(total_pages: int) -> list[int]:
    """
    Compute the correct page order from a single-sided ADF duplex scan.

    The scanned PDF contains:
      - First ceil(T/2) pages: odd pages in ascending order  (1, 3, 5, ...)
      - Last floor(T/2) pages: even pages in descending order (N, N-2, ..., 4, 2)

    Returns a list of 0-based indices in the correct reading order.
    """
    if total_pages <= 1:
        return list(range(total_pages))

    odd_count = math.ceil(total_pages / 2)
    even_count = total_pages - odd_count

    # Indices into the scanned PDF (0-based)
    odd_indices = list(range(odd_count))                          # [0, 1, 2, ...]
    even_indices = list(range(total_pages - 1, odd_count - 1, -1))  # [T-1, T-2, ..., odd_count]

    # Interleave: odd[0], even[0], odd[1], even[1], ...
    result = []
    for i in range(odd_count):
        result.append(odd_indices[i])
        if i < even_count:
            result.append(even_indices[i])

    return result


def reorder_pdf(input_path: Path, output_path: Path, dry_run: bool = False) -> None:
    reader = PdfReader(input_path)
    total = len(reader.pages)

    if total < 2:
        print(f"PDF has {total} page(s) — nothing to reorder.")
        return

    order = compute_page_order(total)

    if dry_run:
        print(f"Input:  {input_path} ({total} pages)")
        print(f"Output: {output_path}")
        print(f"\nScanned page order (1-based): {', '.join(str(i + 1) for i in range(total))}")
        print(f"Reordered to (1-based):        {', '.join(str(i + 1) for i in order)}")
        print(f"\nMapping:")
        for new_pos, old_idx in enumerate(order):
            print(f"  Output page {new_pos + 1} ← Scanned page {old_idx + 1}")
        return

    writer = PdfWriter()
    for idx in order:
        writer.add_page(reader.pages[idx])

    writer.write(output_path)
    print(f"Reordered {total} pages → {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Reorder a PDF scanned from a single-sided ADF for duplex documents.",
        epilog=(
            "Example:\n"
            "  Scan a 6-page document in two passes:\n"
            "    Pass 1 (fronts): pages 1, 3, 5\n"
            "    Pass 2 (backs):  pages 6, 4, 2\n"
            "  The scanned PDF has pages: 1, 3, 5, 6, 4, 2\n"
            "  This script reorders them to: 1, 2, 3, 4, 5, 6"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("input", type=Path, help="Path to the scanned PDF file")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Output PDF path (default: <input>-reordered.pdf)")
    parser.add_argument("--dry-run", action="store_true", help="Show the page mapping without writing a file")

    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    output = args.output or args.input.with_stem(args.input.stem + "-reordered")

    reorder_pdf(args.input, output, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
