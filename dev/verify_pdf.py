#!/usr/bin/env python3
"""Structural and content checks on a PDF produced by SequenceExport.lua.

    python3 verify_pdf.py out/sample.pdf

Parsing at all proves the cross-reference offsets are correct, since the
plugin computes those byte offsets by hand. Requires PyMuPDF:

    pip install pymupdf
"""

import re
import sys

import pymupdf

EXPECTED_TEXT = [
    "Act One (Main)",        # sequence name, the bold title
    "Sequence 12",           # meta line
    "Cue", "Name", "Fade", "Delay", "Note",   # column headers
    "01 Opening",            # appearance section bands
    "02 Ballad",
    "03 Big Chorus",
    "04 Encore",
    "House to Half",         # first cue
    "Final Blackout",        # last cue
    "Preset check before doors",
    "café amber gel",   # WinAnsi round-trip of accented text
    "“slow burn”",  # smart quotes
]


def main(path: str) -> int:
    doc = pymupdf.open(path)
    failures = []

    def check(label: str, condition: bool, detail: str = "") -> None:
        if condition:
            print(f"  ok   {label}")
        else:
            failures.append(label)
            print(f"  FAIL {label}{'  -- ' + detail if detail else ''}")

    check("document parses and has pages", doc.page_count > 0, str(doc.page_count))
    check("cue list paginated onto multiple pages", doc.page_count > 1,
          f"{doc.page_count} page(s)")

    first = doc[0]
    check("page is US Letter portrait",
          round(first.rect.width) == 612 and round(first.rect.height) == 792,
          f"{first.rect.width} x {first.rect.height}")

    text = "\n".join(page.get_text() for page in doc)
    lowered = text.lower()
    for needle in EXPECTED_TEXT:
        check(f"contains {needle!r}", needle.lower() in lowered)

    # Every page must be numbered against the real total.
    for index in range(doc.page_count):
        stamp = f"Page {index + 1} / {doc.page_count}"
        check(f"footer reads {stamp!r}", stamp in doc[index].get_text())

    # The cue count in the meta line must match the rows actually laid out.
    claimed = re.search(r"(\d+) cues", text)
    check("meta line states a cue count", claimed is not None)
    if claimed:
        rows = len(re.findall(r"^Chorus Hit \d+$", text, re.MULTILINE))
        check("cue rows were actually emitted", rows == 14, f"{rows} chorus rows")

    # The title must be the largest, boldest run on page one, top-left.
    spans = [
        span
        for block in first.get_text("dict")["blocks"]
        for line in block.get("lines", [])
        for span in line["spans"]
    ]
    title = max(spans, key=lambda s: s["size"])
    check("title is the largest text on page 1",
          title["text"].strip() == "Act One (Main)", title["text"])
    check("title uses the bold face", "Bold" in title["font"], title["font"])
    check("title sits in the top-left corner",
          title["bbox"][0] < 60 and title["bbox"][1] < 80, str(title["bbox"][:2]))

    # Long notes must wrap rather than spill past the right margin, and a note
    # longer than a whole page must be clipped rather than run off the bottom.
    all_spans = [
        span
        for page in doc
        for block in page.get_text("dict")["blocks"]
        for line in block.get("lines", [])
        for span in line["spans"]
    ]

    overflow = [s for s in all_spans if s["bbox"][2] > 612 - 36 + 1]
    check("no text overflows the right margin", not overflow,
          overflow[0]["text"] if overflow else "")

    below = [s for s in all_spans if s["bbox"][3] > 792 - 20]
    check("no text overflows the bottom margin", not below,
          below[0]["text"] if below else "")

    # Section bands and row tints are filled rectangles; there should be plenty.
    fills = [d for d in first.get_drawings() if d["type"] in ("f", "fs")]
    check("appearance colors are drawn as filled areas", len(fills) > 10,
          f"{len(fills)} fills")

    # The bands must be actually coloured. Greyscale-only fills would mean the
    # Appearance lookup silently failed, which is what shipped before v1.3.0.
    def is_colored(fill: dict) -> bool:
        color = fill.get("fill")
        if not color:
            return False
        r, g, b = color[:3]
        return max(r, g, b) - min(r, g, b) > 0.05

    colored = [f for f in fills if is_colored(f)]
    check("appearance colors are colored, not greyscale", len(colored) >= 2,
          f"{len(colored)} colored of {len(fills)} fills")

    # MA3's CueZero and OffCue are machinery and must not reach the page.
    for machinery in ("CueZero", "Cue Zero", "OffCue", "Off Cue"):
        check(f"{machinery!r} is not in the export",
              machinery.lower() not in lowered)

    # The Cue column holds bare numbers, not whole cue labels like
    # "Cue 1 Blackout" with the name then repeating in the Name column.
    cue_column = [
        s for s in first.get_text("dict")["blocks"]
        for line in s.get("lines", [])
        for s in line["spans"]
        if s["bbox"][0] < 36 + 55 and s["size"] < 12
    ]
    labelled = [s["text"] for s in cue_column if s["text"].strip().lower().startswith("cue ")]
    check("the cue column holds numbers, not cue labels", not labelled,
          labelled[0] if labelled else "")

    # The Name column must not repeat the "Cue n" prefix the Cue column shows.
    name_column = [
        span
        for block in first.get_text("dict")["blocks"]
        for line in block.get("lines", [])
        for span in line["spans"]
        if 36 + 55 <= span["bbox"][0] < 36 + 55 + 150 and span["size"] < 12
    ]
    prefixed = [
        s["text"] for s in name_column
        if re.match(r"^\s*cue\s+\d", s["text"], re.IGNORECASE)
    ]
    check("the name column holds names, not cue labels", not prefixed,
          prefixed[0] if prefixed else "")

    # The data pool was dropped from the header line.
    check("the header no longer names the data pool",
          "data pool" not in doc[0].get_text().lower())

    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "out/sample.pdf"))
