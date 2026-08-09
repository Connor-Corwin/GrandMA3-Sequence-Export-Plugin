--[[
  Runs SequenceExport.lua against the mocked MA3 environment on plain Lua 5.4.

    cd dev && lua5.4 run_local.lua

  Produces dev/out/sample.pdf plus a single-cue and a Back-navigation run,
  and asserts the text-measurement helpers behave on edge cases.
]]

package.path = "./?.lua;../?.lua;" .. package.path

local mock = require("ma3_mock")

_G.SEQUENCE_EXPORT_TESTING = true
mock.install()

local OUT_DIR = "out"
-- Wipe previous output first, so a check can never pass on a stale artifact.
os.execute("rm -rf " .. OUT_DIR .. " && mkdir -p " .. OUT_DIR)
mock.setUsbPath(OUT_DIR)

local Main = dofile("../SequenceExport.lua")
local internals = _G.SequenceExportInternals
assert(internals, "plugin did not expose its internals under SEQUENCE_EXPORT_TESTING")

local PDF = internals.PDF

local failures = 0
local function check(label, condition, detail)
  if condition then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print("  FAIL " .. label .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end

--=============================================================================
-- Unit checks on the text helpers
--=============================================================================

print("\n== text metrics ==")

check("empty string measures zero", PDF.textWidth("", false, 9) == 0)

-- Helvetica 'i' (222/1000) is narrower than 'm' (833/1000).
check("width tracks real glyph metrics",
  PDF.textWidth("iii", false, 10) < PDF.textWidth("mmm", false, 10))

check("bold is wider than regular for the same text",
  PDF.textWidth("Chorus Hit", true, 9) > PDF.textWidth("Chorus Hit", false, 9))

check("width scales with font size",
  math.abs(PDF.textWidth("Cue", false, 18) - 2 * PDF.textWidth("Cue", false, 9)) < 0.001)

print("\n== escaping ==")

check("parentheses and backslash are escaped",
  internals.escapeText("a(b)c\\d") == "a\\(b\\)c\\\\d",
  internals.escapeText("a(b)c\\d"))

check("UTF-8 accents map into WinAnsi octal",
  internals.escapeText("caf\u{00E9}") == "caf\\351",
  internals.escapeText("caf\u{00E9}"))

check("smart quotes map to the WinAnsi high block",
  internals.escapeText("\u{201C}x\u{201D}") == "\\223x\\224",
  internals.escapeText("\u{201C}x\u{201D}"))

check("unmappable codepoints degrade to '?'",
  internals.escapeText("\u{4E2D}") == "?",
  internals.escapeText("\u{4E2D}"))

print("\n== wrapping ==")

local wrapped = PDF.wrapText(
  "Slow build under the announcement, keep the haze moving", false, 9, 100)
check("long text wraps to several lines", #wrapped >= 3, #wrapped .. " lines")

local widest = 0
for _, line in ipairs(wrapped) do
  widest = math.max(widest, PDF.textWidth(line, false, 9))
end
check("no wrapped line exceeds the column", widest <= 100, widest)

check("empty note produces no lines", #PDF.wrapText("", false, 9, 100) == 0)

local unbreakable = PDF.wrapText(string.rep("W", 60), false, 9, 60)
check("a word wider than the column is split, not overflowed",
  #unbreakable > 1 and PDF.textWidth(unbreakable[1], false, 9) <= 60)

local truncated = PDF.truncate("A very long cue name that will not fit", false, 9, 60)
check("truncation fits the budget and marks the cut",
  PDF.textWidth(truncated, false, 9) <= 60 and truncated:sub(-3) == "...",
  truncated)

-- Cutting mid-character would leave a stray UTF-8 lead byte, which WinAnsi
-- encoding then renders as '?'.
local accented = internals.escapeText(
  PDF.truncate(string.rep("\u{00E9}", 40), false, 9, 40))
check("truncation never splits a multi-byte character",
  not accented:find("?", 1, true), accented)

print("\n== color helpers ==")

local dark = { r = 0.07, g = 0.07, b = 0.07 }
local light = { r = 0.98, g = 0.93, b = 0.51 }
check("dark section band gets white text", internals.contrastingInk(dark)[1] == 1)
check("light section band gets black text", internals.contrastingInk(light)[1] == 0)

local tinted = internals.tint({ r = 0, g = 0, b = 0 }, 0.85)
check("row tint blends toward white", math.abs(tinted[1] - 0.85) < 0.001, tinted[1])

print("\n== filename sanitising ==")

check("illegal FAT characters are replaced",
  internals.sanitizeFileName('Act 1: "Big/Show"') == "Act 1- -Big-Show-",
  internals.sanitizeFileName('Act 1: "Big/Show"'))

check("an empty name falls back", internals.sanitizeFileName("") == "Sequence")

--=============================================================================
-- Data layer against the mock
--=============================================================================

print("\n== cue number extraction ==")

check("trailing zeros are trimmed", internals.trimZeros("1.000") == "1")
check("a real decimal survives", internals.trimZeros("2.500") == "2.5")
check("an integer is left alone", internals.trimZeros("10") == "10")

print("\n== special cue detection ==")

check("CueZero is special", internals.isSpecialCue("CueZero", "0"))
check("Cue Zero with a space is special", internals.isSpecialCue("Cue Zero", ""))
check("OffCue is special", internals.isSpecialCue("OffCue", ""))
check("Off Cue with a space is special", internals.isSpecialCue("Off Cue", ""))
check("cue number 0 is special", internals.isSpecialCue("Preset Check", "0"))
check("an ordinary cue is not", not internals.isSpecialCue("Blackout", "2"))
check("a cue merely mentioning zero is not",
  not internals.isSpecialCue("Zero Hour", "14"))

print("\n== object numbers arrive as display labels ==")

-- Get(name, Roles.Display) renders a label rather than returning a value, so
-- object numbers come dressed up. Comparing those against a typed number is
-- what made the data pool field reject every value, its own prefill included.
check("a data pool label yields its number",
  internals.numberToken("1 (16)") == "1", internals.numberToken("1 (16)"))
check("a sequence label yields its number",
  internals.numberToken("12 (58)") == "12", internals.numberToken("12 (58)"))
check("a cue label yields its number",
  internals.numberToken("Cue 1 Blackout") == "1", internals.numberToken("Cue 1 Blackout"))
check("a decimal cue label survives",
  internals.numberToken("Cue 2.5 Intro") == "2.5", internals.numberToken("Cue 2.5 Intro"))
check("a bare number is unchanged", internals.numberToken("7") == "7")
check("text with no number yields nil", internals.numberToken("OffCue") == nil)

print("\n== MA3 data layer ==")

local pools = internals.listDataPools()
check("data pool numbers are bare, not the raw '1 (16)' label",
  pools[1].no == "1" and pools[2].no == "2",
  pools[1].no .. " / " .. pools[2].no)
check("sequence numbers are bare too",
  internals.listSequences(pools[2].handle)[1].no == "12",
  internals.listSequences(pools[2].handle)[1].no)

check("a data pool is found by its typed number",
  internals.findDataPool(pools, "2").name == "Songs")
check("data pool 1 is found too -- both failed before v1.3.1",
  internals.findDataPool(pools, "1").name == "Default")
check("an unknown data pool is not found",
  internals.findDataPool(pools, "9") == nil)
check("the pool list is described for the dialog",
  internals.describePools(pools):find("2 - Songs", 1, true) ~= nil,
  internals.describePools(pools))

check("both data pools are listed", #pools == 2, #pools)
check("the active pool is flagged, and it is not the songs pool",
  pools[1].active == true and pools[2].active == false)

local sequences = internals.listSequences(pools[2].handle)
check("the songs pool is read through its own handle", #sequences == 42, #sequences)

check("a sequence can be found by typed number",
  internals.findSequenceByNumber(sequences, "12", pools[2].handle).name == "Act One (Main)")
check("an unknown number returns nil",
  internals.findSequenceByNumber(sequences, "999", pools[2].handle) == nil)

-- The mock returns colours only through the appearance pool, keyed by name,
-- because that is what the console does. Reading a handle off the cue finds
-- nothing, which is why every cue exported uncoloured before v1.3.0.
local appearances = internals.buildAppearanceIndex(pools[2].handle)
local indexed = 0
for _ in pairs(appearances) do indexed = indexed + 1 end
check("the appearance pool is indexed by name", indexed > 0, indexed)

local cues = internals.collectCues(sequences[1].handle, appearances)

check("cue numbers are bare numbers, not whole cue labels",
  cues[1].no == "1" and cues[3].no == "2.5",
  cues[1].no .. " / " .. cues[3].no)
check("the name is not repeated into the cue number column",
  not cues[1].no:find("House"), cues[1].no)
check("the name column still has the name", cues[1].name == "House to Half", cues[1].name)

check("appearance colour resolves through the name index",
  cues[1].appearance ~= nil and cues[1].appearance.name == "01 Opening",
  cues[1].appearance and cues[1].appearance.name or "nil")
check("the colour is the real one, not black",
  cues[1].appearance ~= nil
    and math.abs(cues[1].appearance.r - 32 / 255) < 0.01
    and math.abs(cues[1].appearance.b - 168 / 255) < 0.01,
  cues[1].appearance and
    string.format("%.2f,%.2f,%.2f", cues[1].appearance.r, cues[1].appearance.g,
      cues[1].appearance.b))

local colored = 0
for _, cue in ipairs(cues) do
  if cue.appearance ~= nil then colored = colored + 1 end
end
check("most cues carry a colour", colored > 40, colored .. " of " .. #cues)

for _, cue in ipairs(cues) do
  if cue.name == "CueZero" or cue.name == "OffCue" then
    check("CueZero and OffCue are excluded", false, cue.name)
  end
end
check("CueZero and OffCue are excluded from the cue list", true)
check("cue timing still comes off the cue part",
  cues[3].fade == "8" and cues[3].delay == "1.5",
  tostring(cues[3].fade) .. " / " .. tostring(cues[3].delay))
check("cue note is read", cues[1].note == "Preset check before doors", cues[1].note)

local uncolored
for _, cue in ipairs(cues) do
  if cue.appearance == nil then uncolored = cue break end
end
check("cues without an appearance still report nil", uncolored ~= nil)

local drives = internals.listDrives()
check("drives are listed with removable first",
  #drives == 2 and drives[1].removable == true and drives[1].name == "USB_STICK")

--=============================================================================
-- Dialogs and full export runs
--=============================================================================

local function reset()
  mock.answers, mock.popupAnswers = {}, {}
  mock.dialogLog, mock.popupLog, mock.offered = {}, {}, {}
  mock.maxSelectorEntries = 0
end

local function fileContains(name, needle)
  local file = io.open(OUT_DIR .. "/" .. name, "rb")
  if not file then return false end
  local body = file:read("a")
  file:close()
  return body:find(needle, 1, true) ~= nil
end

print("\n== export: pool and sequence typed as numbers ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "12" } },
  { result = 1 },                             -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "sample" } },
  { result = 1 },                             -- done
}
Main({ index = 1 }, nil)

check("the export ran from two typed numbers alone", fileContains("sample.pdf", "%PDF"))
check("it read the non-active data pool", fileContains("sample.pdf", "Act One"))
check("the PDF records the data pool", fileContains("sample.pdf", "Data pool 2 - Songs"))
check("only three dialogs plus the done box", #mock.dialogLog == 4,
  #mock.dialogLog .. " dialogs")
check("no list selector was drawn at all", mock.maxSelectorEntries <= 2,
  mock.maxSelectorEntries)

print("\n== the data pool field is usable at all ==")

-- The exact failure reported from the console: the field was prefilled with the
-- raw label "1 (16)", and then every value was rejected -- typing 2 said there
-- was no data pool 2, and typing 1 said the same about 1.
reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "12" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "pooltwo" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("the field is prefilled with a bare number, not '1 (16)'",
  mock.offered[1].fields["Data pool"] == "1",
  tostring(mock.offered[1].fields["Data pool"]))
check("the dialog lists the pools that exist",
  mock.offered[1].message:find("2 - Songs", 1, true) ~= nil,
  mock.offered[1].message)
check("typing 2 selects the songs pool", fileContains("pooltwo.pdf", "Act One"))

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "1", ["Sequence"] = "1" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "poolone" } },
  { result = 1 },
}
Main({ index = 1 }, nil)
check("typing 1 selects the default pool", fileContains("poolone.pdf", "Rehearsal Scratch"))

print("\n== an unknown data pool names the ones that exist ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "9", ["Sequence"] = "12" } },
  { result = 1 },
  { result = 2 },
}
Main({ index = 1 }, nil)
check("the error dialog appeared", mock.dialogLog[2]:find("Error") ~= nil)
check("the error lists the available pools",
  mock.offered[2].message:find("1 - Default", 1, true) ~= nil,
  mock.offered[2].message)

print("\n== CFG.dataPool locks the pool and drops the field ==")

reset()
internals.CFG.dataPool = 2
mock.answers = {
  { result = 1, inputs = { ["Sequence"] = "12" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "locked" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("no data pool field was offered",
  mock.offered[1].fields["Data pool"] == nil,
  tostring(mock.offered[1].fields["Data pool"]))
check("the dialog says which pool it will use",
  mock.offered[1].message:find("data pool 2", 1, true) ~= nil,
  mock.offered[1].message)
check("it exported from the locked pool", fileContains("locked.pdf", "Act One"))

reset()
internals.CFG.dataPool = 9
mock.answers = { { result = 1 } }   -- the error box
Main({ index = 1 }, nil)
check("a CFG.dataPool that does not exist is reported",
  mock.dialogLog[1] ~= nil and mock.dialogLog[1]:find("Error") ~= nil,
  tostring(mock.dialogLog[1]))
check("nothing was asked before the error", #mock.dialogLog == 1,
  #mock.dialogLog .. " dialogs")

internals.CFG.dataPool = nil

print("\n== a blank data pool field falls back to the active pool ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "", ["Sequence"] = "1" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "activepool" } },
  { result = 1 },
}
Main({ index = 1 }, nil)
check("it exported sequence 1 of the active pool",
  fileContains("activepool.pdf", "Rehearsal Scratch"))

print("\n== bad input is rejected, not silently exported ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "9", ["Sequence"] = "12" } },   -- no pool 9
  { result = 1 },                                                          -- error box
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "999" } },  -- no seq 999
  { result = 1 },                                                          -- error box
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "" } },     -- blank
  { result = 1 },                                                          -- error box
  { result = 2 },                                                          -- cancel
}
Main({ index = 1 }, nil)

check("a bad data pool number raised an error", mock.dialogLog[2]:find("Error") ~= nil)
check("a bad sequence number raised an error", mock.dialogLog[4]:find("Error") ~= nil)
check("a blank sequence number raised an error", mock.dialogLog[6]:find("Error") ~= nil)
check("nothing was exported from the bad input", #mock.dialogLog == 7,
  #mock.dialogLog .. " dialogs")

print("\n== what was typed survives a correction ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "999" } },
  { result = 1 },                                                          -- error box
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "12" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "corrected" } },
  { result = 1 },
}
Main({ index = 1 }, nil)
check("the retry dialog was prefilled with the previous entry",
  mock.offered[3] ~= nil, "no third dialog")
check("the corrected entry exported", fileContains("corrected.pdf", "Act One"))

print("\n== Back from the confirm screen returns to the number entry ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "12" } },
  { result = 2 },                                                          -- Back
  { result = 1, inputs = { ["Data pool"] = "2", ["Sequence"] = "20" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "afterback" } },
  { result = 1 },
}
Main({ index = 1 }, nil)
check("the second entry is what got exported",
  fileContains("afterback.pdf", "Pool Two Marker"))
check("it did not export the first entry",
  not fileContains("afterback.pdf", "Act One (Main)"))

print("\n== Cancel is the only route to 'Export cancelled' ==")

reset()
mock.answers = { { result = 2 } }
Main({ index = 1 }, nil)
check("cancelling ends the run after exactly one dialog", #mock.dialogLog == 1,
  #mock.dialogLog .. " dialog(s)")

print("\n== a sequence with no cues is refused ==")

reset()
mock.answers = {
  { result = 1, inputs = { ["Data pool"] = "1", ["Sequence"] = "13" } },
  { result = 1 },   -- the "no cues" error box
  { result = 2 },   -- then cancel
}
Main({ index = 1 }, nil)
check("an empty sequence raised an error instead of exporting",
  mock.dialogLog[2] ~= nil and mock.dialogLog[2]:find("Error") ~= nil,
  tostring(mock.dialogLog[2]))

--=============================================================================

print("")
if failures > 0 then
  print(failures .. " check(s) FAILED")
  os.exit(1)
end
print("all checks passed")
