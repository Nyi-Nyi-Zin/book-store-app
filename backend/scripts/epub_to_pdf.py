#!/usr/bin/env python3
"""Convert a basic EPUB package to PDF for the admin conversion queue.

This intentionally treats EPUB content as document data: scripts are removed and
only XHTML/text content is rendered into the output PDF.
"""
from __future__ import annotations

import re
import sys
import tempfile
import zipfile
from pathlib import Path

from bs4 import BeautifulSoup
from weasyprint import HTML


def clean_fragment(raw: bytes) -> str:
    soup = BeautifulSoup(raw, "html.parser")
    for tag in soup(["script", "style", "iframe", "object", "embed"]):
        tag.decompose()
    body = soup.body or soup
    return str(body)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: epub_to_pdf.py INPUT_EPUB OUTPUT_PDF", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    if not source.is_file():
        print("source must be an existing EPUB file", file=sys.stderr)
        return 2

    fragments: list[str] = []
    with zipfile.ZipFile(source) as archive:
        names = [name for name in archive.namelist() if re.search(r"\.(x?html?|htm)$", name, re.I)]
        for name in sorted(names):
            fragments.append(clean_fragment(archive.read(name)))

    if not fragments:
        print("no XHTML/HTML content found in EPUB", file=sys.stderr)
        return 1

    output.parent.mkdir(parents=True, exist_ok=True)
    html = """<!doctype html><html><head><meta charset='utf-8'><style>
    @page { size: A5; margin: 18mm 16mm 20mm; }
    body { font-family: sans-serif; font-size: 12pt; line-height: 1.65; color: #202124; }
    h1, h2, h3 { page-break-after: avoid; line-height: 1.25; }
    p { orphans: 3; widows: 3; }
    img { max-width: 100%; height: auto; }
    .chapter { page-break-before: always; }
    </style></head><body>""" + "".join(f"<section class='chapter'>{fragment}</section>" for fragment in fragments) + "</body></html>"
    HTML(string=html, base_url=str(source.parent)).write_pdf(str(output))
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
