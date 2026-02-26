---
name: translate-pdf
version: 1.0.0
description: Translate a PDF document from one language to another. Extracts text to structured Markdown, translates it, and builds a new translated PDF. Requires a Python environment with pymupdf, markdown, and weasyprint.
argument-hint: "<path-to-pdf> <source-language> <target-language>"
---

Translate a PDF document end-to-end: extract structured Markdown from the source PDF, translate the content, and build a new PDF in the target language.

**Usage:**
- `/translate-pdf ./report.pdf French English` — Translate a French PDF to English
- `/translate-pdf /path/to/manual.pdf English Spanish` — Translate an English PDF to Spanish
- `/translate-pdf invoice.pdf German French` — Translate a German PDF to French

**Instructions:**

1. **Parse arguments from $ARGUMENTS:**
   - Expect exactly three arguments: `<path-to-pdf>` `<source-language>` `<target-language>`
   - `<path-to-pdf>` is the path to the source PDF file
   - `<source-language>` is the language the PDF is currently written in
   - `<target-language>` is the language to translate into
   - If fewer than three arguments are provided, display the following and **STOP**:
     ```
     ## Missing Arguments

     Usage: /translate-pdf <path-to-pdf> <source-language> <target-language>

     Examples:
       /translate-pdf ./report.pdf French English
       /translate-pdf /path/to/manual.pdf English Spanish
       /translate-pdf invoice.pdf German French
     ```

2. **Validate the PDF file exists:**
   - Resolve the path and verify the file exists and has a `.pdf` extension
   - If the file does not exist, display the error and **STOP**:
     ```
     File not found: "<path>"
     Please provide a valid path to a PDF file.
     ```

3. **Check Python dependencies:**

   The skill relies on a Python script located at `skills/translate-pdf/translate_pdf.py` (relative to this repo). The script requires:
   - `pymupdf` — PDF text extraction
   - `markdown` — Markdown to HTML conversion
   - `weasyprint` — HTML to PDF rendering (also requires system libraries: cairo, pango, gdk-pixbuf)

   **a) Check if the dependencies are installed:**
   Run `python3 -c "import fitz; import markdown; from weasyprint import HTML; print('OK')"` via the Bash tool.

   **b) If the check fails**, use `AskUserQuestion` to ask the developer:
   > The following Python packages are required but not all are installed:
   > - `pymupdf` (PDF extraction)
   > - `markdown` (Markdown → HTML)
   > - `weasyprint` (HTML → PDF, also needs system libs: cairo, pango, gdk-pixbuf)
   >
   > Would you like me to install them now?

   Provide two options:
   - **Yes — install with pip** → Run `pip install pymupdf markdown weasyprint`
   - **No — I'll handle it myself** → Display manual installation instructions and **STOP**:
     ```
     ## Manual Installation

     Install the Python packages:
       pip install pymupdf markdown weasyprint

     weasyprint also requires system libraries. Install them for your OS:

     macOS (Homebrew):
       brew install cairo pango gdk-pixbuf libffi

     Ubuntu/Debian:
       sudo apt install libcairo2-dev libpango1.0-dev libgdk-pixbuf2.0-dev libffi-dev

     Then re-run the skill.
     ```

4. **Step 1 — Extract PDF to Markdown:**

   Determine the output directory — use the same directory as the source PDF.

   Run the extraction script:
   ```bash
   python3 <repo-root>/skills/translate-pdf/translate_pdf.py extract "<pdf-path>" -o "<output-dir>/<filename>_source.md"
   ```

   Where `<filename>` is the PDF filename without extension.

   After extraction, read the generated Markdown file to verify it looks reasonable. If the Markdown is mostly empty or garbled (e.g., the PDF is scanned/image-based), warn the developer:
   > The PDF appears to be image-based or has very little extractable text. The translation may be incomplete or inaccurate. Consider using an OCR tool first.

5. **Step 2 — Translate the Markdown:**

   Read the extracted Markdown file (`<filename>_source.md`).

   Translate **all text content** from `<source-language>` to `<target-language>`, following these rules:
   - **Preserve all Markdown formatting** — headings, bold, italic, lists, tables, code blocks, links, image references
   - **Preserve page comment markers** (`<!-- page N -->`) and horizontal rules (`---`) that act as page separators
   - **Do NOT translate:** code snippets, URLs, file paths, proper nouns that are universally recognized (brand names, product names), or technical identifiers
   - **Translate naturally** — produce fluent, natural-sounding text in the target language, not word-for-word translation
   - **Preserve document structure** — the translated Markdown should have the same number of sections, paragraphs, and structural elements as the source

   Write the translated content to `<output-dir>/<filename>_<target-language>.md` (e.g., `report_English.md`).

6. **Step 3 — Build the translated PDF:**

   Run the build script:
   ```bash
   python3 <repo-root>/skills/translate-pdf/translate_pdf.py build "<output-dir>/<filename>_<target-language>.md" -o "<output-dir>/<filename>_<target-language>.pdf"
   ```

   Verify the output PDF was created successfully.

7. **Report results:**

   Display a summary:
   ```
   ## Translation Complete

   **Source:** <pdf-path> (<source-language>)
   **Target language:** <target-language>

   ### Generated Files
   - Source Markdown: `<filename>_source.md`
   - Translated Markdown: `<filename>_<target-language>.md`
   - Translated PDF: `<filename>_<target-language>.pdf`

   All files saved in: `<output-directory>/`
   ```

8. **Handle edge cases:**
   - If the PDF is password-protected, display an error and **STOP**
   - If the PDF has no extractable text at all, warn the developer and **STOP**
   - If the build step fails due to missing system libraries (weasyprint dependency), display the platform-specific installation instructions from step 3
   - If the source and target languages are the same, warn the developer and ask for confirmation before proceeding
