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
   the Lua file by name. `tools/ProbeUI.*` is an optional diagnostic, not needed
   for normal use; install it the same way if you want to run it.

2. On the console or in onPC, open the **Plugins** pool, edit an empty pool
   slot, and **Import** `SequenceExport`. Pick the drive you copied the files to
   if you are importing from a USB stick.

3. The pool slot now runs the plugin when you tap it.

## Using it

Tap the plugin. Four steps, in order:

1. **Data pool** — a scrollable list of the show's data pools, shown as
   `2 - Songs`, with the pool you currently have active preselected. This step is
   **skipped automatically** when the show has only one data pool.
2. **Select sequence** — the sequences in the chosen pool, shown as
   `12 - Act One`, eight at a time with `Previous` / `Next`. A **Filter** box
   appears once a pool holds more than eight: type a few letters to narrow the
   list instantly. There is also a **Number** field if you would rather type the
   sequence number — a number you type wins over whatever row is highlighted.
3. **Confirm** — shows the sequence number, its name, its data pool and how many
   cues will be exported. `Back` returns to the sequence list.
4. **Destination** — the storage devices currently attached (removable drives
   listed first), plus an editable file name prefilled with
   `<Sequence Name>_<date>.pdf`. `Back` returns to the confirmation.

The PDF is written to the root of the chosen drive, and a final dialog shows the
full path. The data pool it came from is recorded in the PDF's header line.

On shows with several data pools, the sequence list's dismiss button reads
`Back` and returns you to the pool list rather than quitting, so you can browse
freely without restarting the plugin.

### If something goes wrong

Set `debug = true` in the `CFG` table at the top of `SequenceExport.lua` and run
the plugin again. It logs each step — data pools found, sequences found, filter
changes — to the command line.

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
exporting from a **non-active data pool**, filtering a 42-sequence pool down to
one match, a filter that matches nothing, paging forward and back, a typed
number outranking the highlighted row, `Back` from the confirm screen, a show
with a single pool (pool step skipped), an empty sequence, and cancelling.

Two invariants in there exist because both have already broken in production:

- The mock makes `DataPool()` return pool 1 while the interesting sequences live
  in pool 2, so a passing export proves the pool switch really happened rather
  than falling back to the active pool.
- The mock's `PopupInput` is present but always returns `nil` without drawing —
  exactly what grandMA3 2.4 does. Every export test therefore also proves the
  plugin no longer depends on it. A test asserts no selector is ever handed more
  than 8 values.

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
  sequence pool overflows the popup and renders as a black block — this is why
  `pickFromList()` never puts more than `PAGE_SIZE` (8) entries in a selector,
  and why the filter exists.
- **`PopupInput` does not work here, and is disabled.** It is MA3's scrollable
  list picker and would be the better widget, but on grandMA3 2.4 it returns
  `nil` without ever drawing, which made the plugin exit silently. Its exact
  contract could not be confirmed — the documented signature wants item
  *descriptors*, `{ {'str', name}, ... }`, rather than the plain string array
  older examples show, and it reportedly gained a named-parameter form
  (`PopupInput{title=, caller=, items=}`) at some point. `caller` is also a UI
  handle, not the display index `MessageBox` takes.

  `CFG.useNativePicker` gates it, off by default. To find out what your build
  actually wants, install **`tools/ProbeUI`** and run it: it tries every
  convention against every plausible caller and prints which combination draws
  a popup and what it returns. If one works, set `useNativePicker = true`.

To confirm which Lua functions exist in your exact build, run the **`HelpLua`**
keyword on the console — it writes `grandMA3_lua_functions.txt` into the
`gma3_library` folder.

## License

MIT
