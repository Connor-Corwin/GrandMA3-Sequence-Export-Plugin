# GrandMA3 Sequence Export Plugin

Exports a grandMA3 sequence as a printable PDF cue sheet — cue number, name,
fade, delay and note — with the sequence name as the title and each cue's
**Appearance** color carried over so songs and sections stay visible at a glance.

Runs unchanged on a console or on onPC. No external tools, no dependencies:
the PDF bytes are generated in pure Lua, because MA3 ships no PDF library.

![example page](docs/example.png)

## What the export looks like

- Sequence name in **bold** at the top left, with a meta line underneath
  (sequence number, cue count, showfile, timestamp).
- A heavy separator bar, then the cue table.
- A **colored section band** every time the Appearance changes, labelled with the
  Appearance name. Band text flips between black and white automatically so a
  near-black or pale-yellow Appearance stays readable.
- Cue rows **tinted** with a light wash of their section color. Cues with no
  Appearance fall back to plain zebra striping.
- Long notes **word-wrap** and the row grows to fit. Page breaks repeat the
  column headers and re-draw the current section band marked `(cont.)`.

## Install

1. Copy **both** files into the plugins folder of your grandMA3 library:

   ```
   gma3_library/datapools/plugins/SequenceExport.xml
   gma3_library/datapools/plugins/SequenceExport.lua
   ```

   | Where | Path |
   |---|---|
   | USB stick (console) | `<USB>/gma3_library/datapools/plugins/` |
   | onPC, Windows | `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\` |
   | onPC, macOS | `~/MALightingTechnology/gma3_library/datapools/plugins/` |

   Both files must travel together — the XML is the plugin wrapper and points at
   the Lua file by name.

2. On the console or in onPC, open the **Plugins** pool, edit an empty pool
   slot, and **Import** `SequenceExport`. Pick the drive you copied the files to
   if you are importing from a USB stick.

3. The pool slot now runs the plugin when you tap it.

## Using it

Tap the plugin. Four steps, in order:

1. **Data pool** — a scrollable list of the show's data pools, shown as
   `2 - Songs`, with the pool you currently have active preselected. This step is
   **skipped automatically** when the show has only one data pool.
2. **Select sequence** — a scrollable list of every sequence in the chosen pool,
   shown as `12 - Act One`. The first entry, `Enter a number...`, opens a small
   number input if you would rather type it.
3. **Confirm** — shows the sequence number, its name, its data pool and how many
   cues will be exported. `Back` returns to the sequence list.
4. **Destination** — the storage devices currently attached (removable drives
   listed first), plus an editable file name prefilled with
   `<Sequence Name>_<date>.pdf`. `Back` returns to the confirmation.

The PDF is written to the root of the chosen drive, and a final dialog shows the
full path. The data pool it came from is recorded in the PDF's header line.

Dismissing a list steps back rather than quitting outright, so you can browse
pools and sequences freely without restarting the plugin.

## Configuration

Everything visual lives in the `CFG` table at the top of `SequenceExport.lua`:
page size, margins, font sizes, column widths, tint strength, and the luminance
cutoff that decides black-versus-white band text.

The page is **US Letter portrait** (612 × 792 pt). For A4, set
`pageWidth = 595`, `pageHeight = 842`. Column widths must sum to
`pageWidth - 2 * margin`.

## Known limitations

- **Multi-part cues** render as a single row using **part 1**'s fade and delay.
- Text is drawn with the base-14 Helvetica faces, which are **WinAnsi** only.
  Accented Latin, smart quotes, dashes and the like round-trip correctly;
  characters with no WinAnsi equivalent (CJK, Cyrillic) render as `?`.
- The PDF is **uncompressed** — larger files in exchange for zero dependencies.
- A note longer than a whole page is **clipped** with a trailing `...`, since a
  cue row is never split across pages.

## Development

The plugin can be exercised without a console. `dev/ma3_mock.lua` stands in for
the MA3 environment — handles that answer `Get(name, role)`, `Root()`,
`DataPool()`, and a scripted `MessageBox` — over a synthetic show built to
stress the layout.

```sh
cd dev
lua5.4 run_local.lua              # runs the plugin, writes dev/out/*.pdf
pip install pymupdf
python3 verify_pdf.py out/sample.pdf
```

`run_local.lua` asserts the text metrics, WinAnsi escaping, wrapping,
truncation, color helpers and the MA3 data layer, then drives the full UI flow:
exporting from a **non-active data pool**, a `Back`-navigation round trip via the
typed-number entry, a show with a single pool (pool step skipped), a dismissed
picker, a sequence with no cues, and — with `PopupInput` removed — the paged
fallback picker.

The mock deliberately makes `DataPool()` return pool 1 while the interesting
sequences live in pool 2, so a passing export proves the pool switch actually
happened instead of silently falling back to the active pool.

`verify_pdf.py` re-opens the output — which only succeeds if the hand-computed
cross-reference byte offsets are correct — and checks pagination, page size,
expected text, that the title is the largest bold run in the top-left, and that
nothing overflows the margins.

### API notes

Property spellings have moved between MA3 releases, so every read goes through
a defensive `getProp` helper that tries `Get(name, Enums.Roles.Display)` first
and falls back to direct attribute access. An unreadable property yields a blank
cell rather than aborting the export. Two specifics worth knowing:

- Cue timing lives on the **cue part**, not the cue. `cue.cuefade` is `nil`;
  `CueFade` is internally `CueInFade`/`CueOutFade`, so only the display role
  returns the combined string the sequence sheet shows.
- Appearance colors come from `BackR` / `BackG` / `BackB` in the range **0–255**.
- `DataPool()` returns only the pool that happens to be **selected**. Reaching
  any other pool means walking `ShowData().DataPools`.
- **MessageBox has no dropdown.** Its `selectors` offer exactly two widgets:
  `type = 0` is a swipe button showing one value at a time, and `type = 1` is a
  radio group that draws *every* value at once. Handing a radio group a whole
  sequence pool overflows the popup and renders as a black block. Long lists
  must use `PopupInput`, the console's scrollable list picker:

  ```lua
  PopupInput(title, uiCaller, items [, selectedValue [, x, y]])  -- -> string, or nil
  ```

  Note `uiCaller` is the display **handle**, whereas `MessageBox`'s `display`
  field wants the display **index**. `pickFromList()` wraps this and falls back
  to a paged radio group (8 entries per page) if `PopupInput` is unavailable.

To confirm which Lua functions exist in your exact build, run the **`HelpLua`**
keyword on the console — it writes `grandMA3_lua_functions.txt` into the
`gma3_library` folder.

## License

MIT
