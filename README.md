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
- **The cue that carries an Appearance becomes the section header.** Its own row
  — number, name, fade, delay and note — is drawn bold on the full Appearance
  color, so the song title heads the block and the cue appears only once. Text
  flips between black and white automatically so a near-black or pale-yellow
  Appearance stays readable.
- A new section starts at every Appearance-carrying cue, so two songs back to
  back on the **same** color are still two sections.
- **Sub-cues** — `58.001`, `58.002` under cue `58` — are tinted with their
  song's color. Cues that are not sub-cues of the section head end the block and
  fall back to plain zebra striping, so a color never bleeds past its song.
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
   the Lua file by name. `tools/ProbeCue.*` is an optional diagnostic, not needed
   for normal use; install it the same way if you want to run it.

2. On the console or in onPC, open the **Plugins** pool, edit an empty pool
   slot, and **Import** `SequenceExport`. Pick the drive you copied the files to
   if you are importing from a USB stick.

3. The pool slot now runs the plugin when you tap it.

## Using it

Tap the plugin. Three steps, in order:

1. **Data pool and sequence** — type both numbers. The dialog lists the data
   pools that exist, and the field is prefilled with the pool you currently have
   active; leave it blank to use that pool. A number that does not exist is
   reported — along with the pools that do — rather than exported, and the dialog
   reopens with what you typed still in it.

   To skip this every run, set **`dataPool`** in the `CFG` table at the top of
   `SequenceExport.lua` (editable straight from the console's plugin editor):

   ```lua
   dataPool = 2,   -- always export from data pool 2; nil asks each time
   ```

   With it set, the data pool field disappears and the dialog only asks for a
   sequence number.
2. **Confirm** — shows the sequence number, its name, its data pool and how many
   cues will be exported, so you can check you got the right one. `Back` returns
   to the number entry.
3. **Destination** — the storage devices currently attached (removable drives
   listed first), plus an editable file name prefilled with
   `<Sequence Name>_<date>.pdf`. `Back` returns to the confirmation.

The PDF is written to the root of the chosen drive, and a final dialog shows the
full path.

### If the colors don't come through

Appearance colors have been the stubborn part of this plugin, so there are two
answers to that.

**First**, an export that reads no Appearance color at all writes a
`<name>-appearance-report.txt` next to the PDF and says so in the final dialog.
That file records every place the plugin looked for the Appearance pool, what
each Appearance reported for `Name` / `BackR` / `BackG` / `BackB` / `BackColor`
read three different ways, and what each cue reported for its Appearance. It
turns "colors don't work" into a specific answer.

**Second**, `CFG.sections` colors the sheet without MA3's help at all. Fill in
your songs by cue range and the export uses them:

```lua
sections = {
  { from = 1,  to = 13, name = "Opening",    color = {  32,  78, 168 } },
  { from = 14, to = 27, name = "Ballad",     color = { 250, 236, 130 } },
  { from = 28, to = 49, name = "Big Chorus", color = { 198,  40,  40 } },
},
```

Colors are `{ r, g, b }` in 0–255. Any cue inside a range gets that section's
band and row tint, and these **win** over whatever the show reports. Cues outside
every range fall back to the show's Appearances, then to plain zebra striping.
Leave the table empty to rely on the show alone.

MA3's **CueZero** and **OffCue** are filtered out — they are machinery rather
than cues anyone wants on a printed sheet. Set `hideSpecialCues = false` in
`CFG` to keep them.

### If something goes wrong

Set `debug = true` in the `CFG` table at the top of `SequenceExport.lua` and run
the plugin again. It logs each step — data pools found, sequences found, cues
skipped — to the command line.

For anything involving cue data itself (wrong numbers, missing colors), install
**`tools/ProbeCue`** and run it against the sequence. It prints every way of
reading each cue property — `Get()`, `Get()` with the display role, and direct
attribute access — plus the Appearance pool contents, which shows what MA3 is
actually returning rather than what it is expected to return.

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
truncation, color helpers and the MA3 data layer, then drives the full flow:
exporting from a **non-active data pool** by typed number, a blank pool field
falling back to the active pool, rejected input (bad pool, bad sequence, blank),
`Back` from the confirm screen, an empty sequence, and cancelling.

The mock deliberately reproduces the console's real behaviour rather than the
convenient version, because each of these has already shipped as a bug:

- `DataPool()` returns pool 1 while the interesting sequences live in pool 2, so
  a passing export proves the pool switch really happened.
- Object numbers come back as rendered labels — `1 (16)` for a data pool,
  `12 (58)` for a sequence, `Cue 1 Blackout` for a cue — so tests cover typing
  both `1` and `2` into the data pool field, the two values that failed on
  hardware, as well as the Cue column rendering `1`.
- A cue's `Name` arrives as that same label, so a test asserts the Name column
  reads `Blackout` rather than repeating `Cue 1 Blackout`.
- Appearance colour is exercised across a **matrix**, because which combination
  a real build uses is still unknown: four value exposures
  (`mock.appearanceMode` — plain numbers, display strings, percentages, combined
  `BackColor`), three ways a cue refers to its Appearance (`mock.appearanceRef`
  — name, number, `Appearance 3`), and three places the pool hangs
  (`mock.appearanceCollection`, including reachable only by child scan). All ten
  must read the same colour.
- `mock.appearanceRef = "none"` reproduces the console's actual behaviour to
  date, and asserts the diagnostic report is written, that it is *not* written
  when colours work, and that `CFG.sections` colours the export on its own.
- Appearance colors resolve **only** through the pool's `Appearances` collection
  by name — `cue.appearance` is nil, exactly as on hardware — so a passing color
  test proves the fallback path, not the handle path that never worked.
- The mock sequence carries a `CueZero` and an `OffCue`, asserted absent from the
  PDF text.

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
- **`Get(name, Roles.Display)` returns a rendered display string, not a value**,
  and this bites everywhere object numbers are read. A data pool's `No` comes
  back as `1 (16)`, a sequence's as `12 (58)`, a cue's as `Cue 1 Blackout`.
  Comparing any of those against a typed `1` fails, which is why the data pool
  field once rejected every value including its own prefill. `numberToken()`
  pulls the first number out and everything — pools, sequences, cues — goes
  through it. By the same mechanism `Appearance` comes back as the appearance's
  *name*, never a handle.
- **Appearance colors are the least reliable thing here.** Nothing about them
  is consistent: not the property route, not the value scale, not how a cue
  refers to its Appearance, not where the Appearance pool hangs. The plugin
  therefore covers a matrix rather than one path — `colorChannel()` reads a
  plain value then the display role and detects percentages, `combinedColor()`
  handles a single `BackColor`, `findAppearanceCollection()` tries six
  accessors then scans children, and `buildAppearanceIndex()`
  keys each Appearance by name, number, `appearance <n>` and position so any
  form a cue reports resolves. Position is claimed in a second pass so it can
  never shadow a real pool number — pool order is not the same as numbering.
- **Appearances are a show-level pool**, `ShowData().Appearances`, not a data
  pool one. A diagnostic from a real console found nothing under the data pool
  by any route.
- **A cue's appearance property is not reliably called `Appearance`** — on a real
  console it reads `nil` through `Get()`, the display role and attribute access
  alike. MA3 exposes `handle:PropertyCount()` and `handle:PropertyName(i)`
  (0-based), so `findProperties()` enumerates a cue's and its part's properties
  and tries *every* one whose name contains `appear`, rather than assuming.
- **Names come back quoted** — `Cue 4.001 'Words ON'`. `stripQuotes()` runs after
  the cue-label prefix is removed, so the quotes do not survive into the PDF.
- When an export reads no color at all it writes an
  `-appearance-report.txt` beside the PDF dumping every one of those routes and
  what MA3 returned, so a failure explains itself instead of costing a round of
  inference. `CFG.sections` is the guaranteed fallback.
  `buildAppearanceIndex()` therefore indexes the data pool's `Appearances` by
  name once per export, and `readAppearance()` falls back to looking the cue's
  appearance *name* up in it. That fallback is the path that actually works on
  grandMA3 2.4 — without it every cue exports uncolored.
- `DataPool()` returns only the pool that happens to be **selected**. Reaching
  any other pool means walking `ShowData().DataPools`.
- Every sequence has a **CueZero** and an **OffCue** among its children. They are
  real cue objects and will land in the export unless filtered.
- **MessageBox has no dropdown.** Its `selectors` offer exactly two widgets:
  `type = 0` is a swipe button showing one value at a time, and `type = 1` is a
  radio group that draws *every* value at once. Handing a radio group a whole
  sequence pool overflows the popup and renders as a black block. The drive
  selector is the only selector left, and it holds a handful of entries.
- **`PopupInput` does not work here.** It is MA3's scrollable list picker, but on
  grandMA3 2.4 it returns `nil` without ever drawing, which made the plugin exit
  silently in v1.1.0. Its contract could not be confirmed — the documented
  signature wants item *descriptors*, `{ {'str', name}, ... }`, rather than the
  plain string array older examples show, and it reportedly gained a
  named-parameter form at some point. Since sequences are now entered by number,
  no list widget is needed and the code is gone.

To confirm which Lua functions exist in your exact build, run the **`HelpLua`**
keyword on the console — it writes `grandMA3_lua_functions.txt` into the
`gma3_library` folder.

## License

MIT
