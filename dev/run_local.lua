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
os.execute("mkdir -p " .. OUT_DIR)
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

local sequences = internals.listSequences()
check("all mock sequences are listed", #sequences == 3, #sequences)
check("sequence numbers and names are read",
  sequences[2].no == "12" and sequences[2].name == "Act One (Main)",
  sequences[2].no .. " / " .. sequences[2].name)

local cues = internals.collectCues(sequences[2].handle)
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

print("\n== export: multi-page sequence, chosen from the dropdown ==")

mock.answers = {
  { result = 1, selectors = { Sequence = 2 }, inputs = { ["Sequence number"] = "" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 },    inputs = { ["File name"] = "sample" } },
  { result = 1 },
}
Main({ index = 1 }, nil)
check("sample.pdf was written",
  (function() local f = io.open(OUT_DIR .. "/sample.pdf", "rb")
     if f then f:close() return true end return false end)())

print("\n== export: sequence chosen by typed number, after going Back ==")

mock.answers = {
  -- Pick the wrong sequence, then use Back from the confirm screen.
  { result = 1, selectors = { Sequence = 1 }, inputs = { ["Sequence number"] = "" } },
  { result = 2 },
  -- Second time round, type the number instead of using the dropdown.
  { result = 1, selectors = { Sequence = 1 }, inputs = { ["Sequence number"] = "12" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 },    inputs = { ["File name"] = "typed" } },
  { result = 1 },
}
mock.dialogLog = {}
Main({ index = 1 }, nil)
check("Back returned to the picker before exporting",
  #mock.dialogLog == 6 and mock.dialogLog[3]:find("Sequence Export"),
  #mock.dialogLog .. " dialogs")
check("typed number selected the right sequence",
  (function() local f = io.open(OUT_DIR .. "/typed.pdf", "rb")
     if not f then return false end
     local body = f:read("a") f:close()
     return body:find("Act One", 1, true) ~= nil end)())

print("\n== export: single-cue sequence ==")

mock.answers = {
  { result = 1, selectors = { Sequence = 1 }, inputs = { ["Sequence number"] = "" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 },    inputs = { ["File name"] = "single" } },
  { result = 1 },
}
Main({ index = 1 }, nil)
check("single.pdf was written",
  (function() local f = io.open(OUT_DIR .. "/single.pdf", "rb")
     if f then f:close() return true end return false end)())

print("\n== export: sequence with no cues is refused ==")

mock.answers = {
  { result = 1, selectors = { Sequence = 3 }, inputs = { ["Sequence number"] = "" } },
  { result = 1 },  -- the "no cues" error box
  { result = 2 },  -- cancel out of the picker on the retry
}
mock.dialogLog = {}
Main({ index = 1 }, nil)
check("empty sequence raised an error dialog instead of exporting",
  mock.dialogLog[2] ~= nil and mock.dialogLog[2]:find("Error") ~= nil,
  tostring(mock.dialogLog[2]))

--=============================================================================

print("")
if failures > 0 then
  print(failures .. " check(s) FAILED")
  os.exit(1)
end
print("all checks passed")
