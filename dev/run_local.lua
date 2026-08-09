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
-- Picker and full export runs
--
-- Throughout, PopupInput exists but always returns nil without drawing --
-- exactly what grandMA3 2.4 does, and what silently aborted v1.1.0. Every
-- test below therefore also proves the default path no longer depends on it.
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

--- Find the labels a given picker dialog offered on its Nth appearance.
local function offeredLabels(titleFragment, occurrence)
  local seen = 0
  for _, dialog in ipairs(mock.offered) do
    if dialog.title:find(titleFragment, 1, true) then
      seen = seen + 1
      if seen == (occurrence or 1) then return dialog.labels, dialog.message end
    end
  end
  return nil
end

local function labelsInclude(labels, needle)
  for _, label in ipairs(labels or {}) do
    if label:find(needle, 1, true) then return true end
  end
  return false
end

print("\n== export: pool 2, browsing the paged list ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },   -- data pool: pick "2 - Songs"
  { result = 1, selectors = { Item = 1 } },   -- sequence: first entry on page 1
  { result = 1 },                             -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "sample" } },
  { result = 1 },                             -- done
}
Main({ index = 1 }, nil)

check("sample.pdf was written", fileContains("sample.pdf", "%PDF"))
check("it exported the pool-2 sequence", fileContains("sample.pdf", "Act One"))
check("the PDF records the data pool", fileContains("sample.pdf", "Data pool 2 - Songs"))
check("PopupInput returned nil and did not stop the export", #mock.popupLog == 0,
  #mock.popupLog .. " PopupInput call(s)")

local poolLabels = offeredLabels("Select data pool")
check("the pool picker offered both pools", poolLabels and #poolLabels == 2,
  poolLabels and #poolLabels)
check("the active pool is marked", labelsInclude(poolLabels, "(active)"))

local seqLabels, seqMessage = offeredLabels("Select sequence")
check("the sequence picker showed one page, not the whole pool",
  seqLabels and #seqLabels == 8, seqLabels and #seqLabels)
check("it reported the full match count and page position",
  seqMessage and seqMessage:find("42 matches") and seqMessage:find("page 1 of 6"),
  tostring(seqMessage))
check("no selector was ever handed more than one page",
  mock.maxSelectorEntries <= 8, mock.maxSelectorEntries)

print("\n== the filter narrows a 42-sequence pool ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },                          -- pool 2
  { result = 1, inputs = { Filter = "Encore" }, selectors = { Item = 1 } },
  { result = 1, selectors = { Item = 1 } },                          -- now pick the match
  { result = 1 },                                                    -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "filtered" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

local filtered, filteredMessage = offeredLabels("Select sequence", 2)
check("the filter narrowed the list to the one match",
  filtered and #filtered == 1 and labelsInclude(filtered, "Songs Only Encore"),
  filtered and #filtered)
check("the match count reflects the filter",
  filteredMessage and filteredMessage:find("1 entry"), tostring(filteredMessage))
check("the filtered sequence is what got exported",
  fileContains("filtered.pdf", "Pool Two Marker"))

print("\n== typing a filter does not resolve against the pre-filter list ==")

-- Round 2 sets the filter *and* presses Select. Item 1 of the unfiltered list
-- is "12 - Act One (Main)"; if the picker resolved against the old list it
-- would export that instead of redrawing.
check("Select alongside a new filter redraws instead of selecting",
  fileContains("filtered.pdf", "Songs Only Encore")
    or fileContains("filtered.pdf", "Pool Two Marker"))
check("it did not export the pre-filter selection",
  not fileContains("filtered.pdf", "Act One (Main)"))

print("\n== a filter matching nothing shows a placeholder ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },                             -- pool 2
  { result = 1, inputs = { Filter = "zzzznothing" }, selectors = { Item = 1 } },
  { result = 1, selectors = { Item = 0 } },   -- try to select the placeholder
  { result = 1, inputs = { Filter = "" }, selectors = { Item = 1 } },   -- clear it
  { result = 1, selectors = { Item = 1 } },                             -- pick again
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "recovered" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

local empty, emptyMessage = offeredLabels("Select sequence", 3)
check("an empty result set still offers exactly one placeholder row",
  empty and #empty == 1 and empty[1] == "(no matches)",
  empty and table.concat(empty, ","))
check("it says so in the message",
  emptyMessage and emptyMessage:find("No sequences match"), tostring(emptyMessage))
check("selecting the placeholder did not choose anything, and clearing recovered",
  fileContains("recovered.pdf", "Act One"))

print("\n== paging forward and wrapping ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },   -- pool 2
  { result = 3, selectors = { Item = 1 } },   -- Next -> page 2
  { result = 3, selectors = { Item = 1 } },   -- Next -> page 3
  { result = 2, selectors = { Item = 1 } },   -- Previous -> page 2
  { result = 1, selectors = { Item = 9 } },   -- select the first entry of page 2
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "paged" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

local _, page2 = offeredLabels("Select sequence", 2)
local _, page3 = offeredLabels("Select sequence", 3)
local _, backTo2 = offeredLabels("Select sequence", 4)
check("Next advanced the page", page2 and page2:find("page 2 of 6"), tostring(page2))
check("Next advanced again", page3 and page3:find("page 3 of 6"), tostring(page3))
check("Previous went back", backTo2 and backTo2:find("page 2 of 6"), tostring(backTo2))
check("paged.pdf was written", fileContains("paged.pdf", "%PDF"))

print("\n== a typed number outranks the list selection ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },                        -- pool 2
  -- Item 1 on screen is "12 - Act One (Main)", but 20 is typed.
  { result = 1, selectors = { Item = 1 }, inputs = { Number = "20" } },
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "bynumber" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("the typed number won over the highlighted row",
  fileContains("bynumber.pdf", "Pool Two Marker"))
check("the list selection was ignored",
  not fileContains("bynumber.pdf", "Act One (Main)"))

print("\n== an unknown typed number reports an error ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },
  { result = 1, selectors = { Item = 1 }, inputs = { Number = "999" } },
  { result = 1 },                             -- the error box
  { result = 4, selectors = { Item = 1 } },   -- Back to the pool picker
  { result = 4, selectors = { Item = 1 } },   -- then cancel out of that
}
Main({ index = 1 }, nil)
check("an unknown number raised an error rather than exporting",
  mock.dialogLog[3] ~= nil and mock.dialogLog[3]:find("Error") ~= nil,
  tostring(mock.dialogLog[3]))

print("\n== Back from the confirm screen returns to the sequence list ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 2 } },   -- pool 2
  { result = 1, selectors = { Item = 1 } },   -- sequence
  { result = 2 },                             -- confirm -> Back
  { result = 1, selectors = { Item = 2 } },   -- a different sequence
  { result = 1 },                             -- confirm
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "afterback" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("Back reopened the sequence picker, not the pool picker",
  offeredLabels("Select sequence", 2) ~= nil and offeredLabels("Select data pool", 2) == nil)
check("the second choice is what got exported",
  fileContains("afterback.pdf", "Pool Two Marker"))

print("\n== the pool step is skipped when the show has one pool ==")

mock.twoDataPools = false
mock.install()
mock.setUsbPath(OUT_DIR)
reset()
mock.answers = {
  { result = 1, selectors = { Item = 1 } },   -- straight to the sequence picker
  { result = 1 },
  { result = 1, selectors = { Drive = 1 }, inputs = { ["File name"] = "single" } },
  { result = 1 },
}
Main({ index = 1 }, nil)

check("no data pool picker appeared", offeredLabels("Select data pool") == nil)
check("single.pdf was written", fileContains("single.pdf", "%PDF"))

local soleLabels = offeredLabels("Select sequence")
check("a short list gets no filter box and no paging",
  soleLabels and #soleLabels == 2, soleLabels and #soleLabels)

mock.twoDataPools = true
mock.install()
mock.setUsbPath(OUT_DIR)

print("\n== Cancel is the only route to 'Export cancelled' ==")

reset()
mock.answers = { { result = 4, selectors = { Item = 1 } } }
Main({ index = 1 }, nil)
check("cancelling the first picker ends the run after exactly one dialog",
  #mock.dialogLog == 1, #mock.dialogLog .. " dialog(s)")

print("\n== a sequence with no cues is refused ==")

reset()
mock.answers = {
  { result = 1, selectors = { Item = 1 } },   -- pool 1 (Default)
  { result = 1, selectors = { Item = 2 } },   -- "13 - Empty Sequence"
  { result = 1 },                             -- the "no cues" error box
  { result = 4, selectors = { Item = 1 } },   -- Back to the pool picker
  { result = 4, selectors = { Item = 1 } },   -- then cancel
}
Main({ index = 1 }, nil)
check("an empty sequence raised an error instead of exporting",
  mock.dialogLog[3] ~= nil and mock.dialogLog[3]:find("Error") ~= nil,
  tostring(mock.dialogLog[3]))

--=============================================================================

print("")
if failures > 0 then
  print(failures .. " check(s) FAILED")
  os.exit(1)
end
print("all checks passed")
