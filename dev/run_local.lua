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

print("\n== MA3 data layer ==")

local pools = internals.listDataPools()
check("both data pools are listed", #pools == 2, #pools)
check("pool numbers and names are read",
  pools[2].no == "2" and pools[2].name == "Songs",
  pools[2].no .. " / " .. pools[2].name)
check("the active pool is flagged, and it is not the songs pool",
  pools[1].active == true and pools[2].active == false)

-- The whole point of the data pool step: DataPool() returns pool 1, so pool 2's
-- sequences are only reachable by walking ShowData.
local activePoolSequences = internals.listSequences(nil)
check("the active pool holds only its own sequences",
  #activePoolSequences == 2, #activePoolSequences)

local sequences = internals.listSequences(pools[2].handle)
check("the songs pool is read through its own handle", #sequences == 42, #sequences)
check("sequence numbers and names are read",
  sequences[1].no == "12" and sequences[1].name == "Act One (Main)",
  sequences[1].no .. " / " .. sequences[1].name)

local marker
for _, sequence in ipairs(sequences) do
  if sequence.name == "Songs Only Encore" then marker = sequence end
end
check("a pool-2-only sequence is visible", marker ~= nil)

check("a sequence can be found by typed number",
  internals.findSequenceByNumber(sequences, "12", pools[2].handle).name == "Act One (Main)")
check("an unknown number returns nil",
  internals.findSequenceByNumber(sequences, "999", pools[2].handle) == nil)

local cues = internals.collectCues(sequences[1].handle)
check("cues are collected", #cues > 50, #cues)
check("cue timing comes off the cue part",
  cues[3].fade == "8" and cues[3].delay == "1.5",
  tostring(cues[3].fade) .. " / " .. tostring(cues[3].delay))
check("cue note is read", cues[1].note == "Preset check before doors", cues[1].note)
check("appearance color is normalised to 0-1",
  cues[1].appearance ~= nil
    and math.abs(cues[1].appearance.r - 32 / 255) < 0.001
    and cues[1].appearance.name == "01 Opening")

local uncolored
for _, cue in ipairs(cues) do
  if cue.appearance == nil then uncolored = cue break end
end
check("cues without an appearance report nil", uncolored ~= nil)

local drives = internals.listDrives()
check("drives are listed with removable first",
  #drives == 2 and drives[1].removable == true and drives[1].name == "USB_STICK")

--=============================================================================
-- Full export runs
--=============================================================================

local function reset()
  mock.answers, mock.popupAnswers = {}, {}
  mock.dialogLog, mock.popupLog = {}, {}
  mock.maxSelectorEntries = 0
end

local function fileContains(name, needle)
  local file = io.open(OUT_DIR .. "/" .. name, "rb")
  if not file then return false end
  local body = file:read("a")
  file:close()
  return body:find(needle, 1, true) ~= nil
end

print("\n== export: sequence from data pool 2, picked from the scrollable list ==")

reset()
mock.popupAnswers = { "2 - Songs", "12 - Act One (Main)" }
mock.answers = {
  { result = 1 },                                                        -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "sample" } },
  { result = 1 },                                                        -- done
}
Main({ index = 1 }, nil)

check("sample.pdf was written", fileContains("sample.pdf", "%PDF"))
check("it exported the pool-2 sequence", fileContains("sample.pdf", "Act One"))
check("the PDF records which data pool it came from",
  fileContains("sample.pdf", "Data pool 2 - Songs"))
check("the data pool picker ran first",
  mock.popupLog[1] and mock.popupLog[1].title:find("data pool") ~= nil,
  mock.popupLog[1] and mock.popupLog[1].title)
check("the active pool was preselected",
  mock.popupLog[1] and mock.popupLog[1].selected == "1 - Default",
  mock.popupLog[1] and tostring(mock.popupLog[1].selected))
check("the whole sequence list went to PopupInput, not a radio group",
  mock.popupLog[2] and #mock.popupLog[2].items == 43,
  mock.popupLog[2] and #mock.popupLog[2].items)
check("no MessageBox selector was handed a long list",
  mock.maxSelectorEntries <= 2, mock.maxSelectorEntries)
check("the number-entry option is pinned to the top of the list",
  mock.popupLog[2] and mock.popupLog[2].items[1] == "Enter a number...",
  mock.popupLog[2] and mock.popupLog[2].items[1])

print("\n== export: typed number, after Back from the confirm screen ==")

reset()
mock.popupAnswers = {
  "2 - Songs", "20 - Songs Only Encore",   -- pick the wrong one
  "Enter a number...",                     -- Back lands on the sequence picker
}
mock.answers = {
  { result = 2 },                                                    -- confirm -> Back
  { result = 1, inputs = { ["Sequence number"] = "12" } },           -- number entry
  { result = 1 },                                                    -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "typed" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("Back re-opened the sequence picker, not the pool picker",
  #mock.popupLog == 3 and mock.popupLog[3].title:find("sequence") ~= nil,
  #mock.popupLog .. " popups")
check("the typed number resolved to the right sequence",
  fileContains("typed.pdf", "Act One"))

print("\n== the data pool step is skipped when the show has only one pool ==")

mock.twoDataPools = false
mock.install()
mock.setUsbPath(OUT_DIR)
reset()
mock.popupAnswers = { "1 - Rehearsal Scratch" }
mock.answers = {
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "single" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("only one popup appeared, and it was the sequence picker",
  #mock.popupLog == 1 and mock.popupLog[1].title:find("sequence") ~= nil,
  #mock.popupLog .. " popup(s)")
check("single.pdf was written", fileContains("single.pdf", "%PDF"))

mock.twoDataPools = true
mock.install()
mock.setUsbPath(OUT_DIR)

print("\n== dismissing the picker cancels cleanly ==")

reset()
mock.popupAnswers = { "<dismiss>" }
Main({ index = 1 }, nil)
check("no dialogs followed a dismissed data pool picker", #mock.dialogLog == 0,
  #mock.dialogLog .. " dialog(s)")

print("\n== a sequence with no cues is refused ==")

reset()
mock.popupAnswers = {
  "1 - Default", "13 - Empty Sequence",
  "<dismiss>",   -- back out of the sequence picker
  "<dismiss>",   -- and out of the pool picker
}
mock.answers = { { result = 1 } }   -- the "no cues" error box
Main({ index = 1 }, nil)
check("an empty sequence raised an error instead of exporting",
  mock.dialogLog[1] ~= nil and mock.dialogLog[1]:find("Error") ~= nil,
  tostring(mock.dialogLog[1]))
check("the error returned the user to the picker rather than exporting",
  #mock.popupLog == 4, #mock.popupLog .. " popups")

print("\n== fallback: a build without PopupInput still works ==")

mock.hasPopupInput = false
mock.install()
mock.setUsbPath(OUT_DIR)
reset()

-- Paged radio picker: pool 2, then page forward to reach sequence 12.
mock.answers = {
  { result = 1, selectors = { Item = 2 } },                          -- data pool 2
  { result = 1, selectors = { Item = 2 } },                          -- sequence 12
  { result = 1 },                                                    -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "fallback" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("the fallback picker completed the export", fileContains("fallback.pdf", "Act One"))
check("no fallback page exceeded the radio-group cap",
  mock.maxSelectorEntries <= 8, mock.maxSelectorEntries)

mock.hasPopupInput = true
mock.install()
mock.setUsbPath(OUT_DIR)

--=============================================================================

print("")
if failures > 0 then
  print(failures .. " check(s) FAILED")
  os.exit(1)
end
print("all checks passed")
