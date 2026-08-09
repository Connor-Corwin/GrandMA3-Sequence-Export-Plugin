--[[
  Minimal stand-in for the grandMA3 Lua environment, so SequenceExport.lua can
  be exercised on a plain Lua 5.4 interpreter.

  It mimics the parts the plugin actually touches:
    - handles that answer Get(name, role) and lowercase attribute access
    - Root().Temp.DriveCollect, Root().manetsocket.showfile
    - DataPool().Sequences
    - MessageBox, driven by a scripted queue of answers
    - Enums.Roles.Display, Printf, Echo, ErrEcho, GetFocusDisplay

  The synthetic show is built to stress the layout: wrapping notes, empty
  fields, missing appearances, very dark and very light section colors,
  decimal cue numbers, and text needing PDF escaping / WinAnsi mapping.
]]

local M = {}

--=============================================================================
-- Handles
--=============================================================================

local Handle = {}
Handle.__index = function(self, key)
  local method = rawget(Handle, key)
  if method then return method end
  return rawget(self, "_attrs")[key]
end

--- props: display-role values, keyed by their MA3 property name.
--- attrs: lowercase attribute access (cue.appearance, drive.path, ...).
--- kids:  child handles.
local function newHandle(props, attrs, kids)
  return setmetatable({
    _props = props or {},
    _attrs = attrs or {},
    _kids  = kids or {},
  }, Handle)
end
M.newHandle = newHandle

function Handle:Get(name, _role)
  return rawget(self, "_props")[name]
end

function Handle:Children()
  return rawget(self, "_kids")
end

--=============================================================================
-- Synthetic show
--=============================================================================

local APPEARANCES = {
  opening = { name = "01 Opening",   r = 32,  g = 78,  b = 168 },  -- dark blue
  ballad  = { name = "02 Ballad",    r = 250, g = 236, b = 130 },  -- very light yellow
  chorus  = { name = "03 Big Chorus", r = 198, g = 40,  b = 40  }, -- red
  encore  = { name = "04 Encore",    r = 18,  g = 18,  b = 18  },  -- near black
}

local function appearanceHandle(spec)
  if spec == nil then return nil end
  return newHandle(
    { Name = spec.name, BackR = spec.r, BackG = spec.g, BackB = spec.b, BackAlpha = 255 },
    { name = spec.name, backr = spec.r, backg = spec.g, backb = spec.b, backalpha = 255 })
end

local function cueHandle(no, name, fade, delay, note, appearanceSpec)
  local part = newHandle(
    { CueFade = fade, CueDelay = delay },
    { cuefade = fade, cuedelay = delay })

  local appearance = appearanceHandle(appearanceSpec)

  local cue = newHandle(
    { No = no, Name = name, Note = note },
    { no = no, name = name, note = note, appearance = appearance },
    { part })

  -- The plugin reads the first cue part as cue[1]; mirror that.
  rawget(cue, "_attrs")[1] = part
  return cue
end

--- Build a sequence long enough to force several page breaks.
local function buildLongSequence()
  local cues = {}

  local function add(...) cues[#cues + 1] = cueHandle(...) end

  add("1",   "House to Half",  "3",   "0",   "Preset check before doors", APPEARANCES.opening)
  add("2",   "Blackout",       "2",   "0",   "",                          APPEARANCES.opening)
  add("2.5", "Intro Build",    "8",   "1.5", "Slow build under the announcement -- keep the haze moving, and hold the upstage wash until the downbeat lands.", APPEARANCES.opening)
  add("3",   "",               "0",   "0",   "Unnamed cue on purpose",    APPEARANCES.opening)

  for i = 1, 9 do
    add(tostring(3 + i), "Opening Look " .. i, tostring(i % 6), "0",
      i % 3 == 0 and "Follow spot pickup stage left" or "", APPEARANCES.opening)
  end

  add("14", "Ballad Wash",   "12",  "2",  "Cross to warm state (soft edges) \\ no movement", APPEARANCES.ballad)
  add("15", "Solo Special",  "1.5", "0",  "Tight iris; caf\u{00E9} amber gel \u{2014} \u{201C}slow burn\u{201D}", APPEARANCES.ballad)

  for i = 1, 12 do
    add(tostring(15 + i), "Ballad " .. i, "4", tostring(i % 3),
      i % 4 == 0 and "Hold for applause, then release on the conductor's cue and restore the previous state at the same speed." or "",
      APPEARANCES.ballad)
  end

  add("28", "Chorus Bump", "0", "0", "BUMP -- hard in, no fade", APPEARANCES.chorus)
  for i = 1, 14 do
    add(tostring(28 + i), "Chorus Hit " .. i, "0", "0",
      i % 5 == 0 and "Strobe burst (4 count)" or "", APPEARANCES.chorus)
  end

  -- A stretch with no appearance at all, to exercise zebra striping.
  for i = 1, 6 do
    add(tostring(50 + i), "Transition " .. i, "6", "0",
      i == 1 and "No appearance assigned to these cues" or "", nil)
  end

  -- A note far longer than one page, to prove the row gets clipped rather
  -- than running off the bottom edge.
  add("57", "Runaway Note", "3", "0",
    string.rep("This note is absurdly long and must be clipped to fit. ", 120), nil)

  add("60", "Encore In",  "5", "0", "Audience blinders at 40%", APPEARANCES.encore)
  for i = 1, 8 do
    add(tostring(60 + i), "Encore " .. i, "2", "0", "", APPEARANCES.encore)
  end
  add("70", "Final Blackout", "10", "3", "Hold blackout until house is up", APPEARANCES.encore)

  return cues
end

local SEQUENCES = {
  newHandle({ No = "1",  Name = "Rehearsal Scratch" }, { no = 1,  name = "Rehearsal Scratch" },
    { cueHandle("1", "Only Cue", "3", "0", "Single-cue sequence", nil) }),

  newHandle({ No = "12", Name = "Act One (Main)" }, { no = 12, name = "Act One (Main)" },
    buildLongSequence()),

  newHandle({ No = "13", Name = "Empty Sequence" }, { no = 13, name = "Empty Sequence" }, {}),
}

--=============================================================================
-- Globals the plugin expects
--=============================================================================

local DRIVES = {
  newHandle({ Name = "Internal", Path = "/tmp/ma3-internal", DriveType = "Internal" },
            { name = "Internal", path = "/tmp/ma3-internal", drivetype = "Internal" }),
  newHandle({ Name = "USB_STICK", Path = "", DriveType = "Removeable" },
            { name = "USB_STICK", path = "", drivetype = "Removeable" }),
}

--- Point the mock removable drive at a real directory for the test run.
function M.setUsbPath(path)
  rawget(DRIVES[2], "_props").Path = path
  rawget(DRIVES[2], "_attrs").path = path
end

--- Scripted MessageBox answers, consumed in order.
M.answers = {}
M.dialogLog = {}

function M.install()
  _G.Enums = { Roles = { Display = 2, Default = 0, Edit = 1 } }

  local driveCollect = newHandle({}, {}, DRIVES)
  local temp = newHandle({}, { drivecollect = driveCollect })
  rawget(temp, "_attrs").DriveCollect = driveCollect
  local manetsocket = newHandle({}, { showfile = "Demo Show 2026" })

  local root = newHandle({}, { temp = temp, manetsocket = manetsocket })
  rawget(root, "_attrs").Temp = temp

  local sequencePool = newHandle({}, {}, SEQUENCES)
  for _, sequence in ipairs(SEQUENCES) do
    local number = tonumber(rawget(sequence, "_props").No)
    rawget(sequencePool, "_attrs")[number] = sequence
  end
  local dataPool = newHandle({}, { sequences = sequencePool })
  rawget(dataPool, "_attrs").Sequences = sequencePool

  _G.Root     = function() return root end
  _G.DataPool = function() return dataPool end

  _G.Printf  = function(fmt, ...) print(string.format(fmt, ...)) end
  _G.Echo    = _G.Printf
  _G.ErrEcho = function(fmt, ...) print("ERR " .. string.format(fmt, ...)) end

  _G.GetFocusDisplay = function() return newHandle({}, { index = 1 }) end

  _G.MessageBox = function(spec)
    M.dialogLog[#M.dialogLog + 1] = spec.title
    local answer = table.remove(M.answers, 1)
    print(string.format("[dialog] %s -> %s", spec.title,
      answer and ("result=" .. tostring(answer.result)) or "no scripted answer"))
    if answer == nil then
      error("mock MessageBox: no scripted answer left for '" .. tostring(spec.title) .. "'")
    end
    return answer
  end
end

M.sequences = SEQUENCES
return M
