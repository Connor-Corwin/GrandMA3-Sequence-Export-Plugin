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
  local value = rawget(self, "_props")[name]
  -- A function value is resolved on read, so switches like M.appearanceRef
  -- take effect without rebuilding the whole synthetic show.
  if type(value) == "function" then return value() end
  return value
end

function Handle:Children()
  return rawget(self, "_kids")
end

--- MA3 exposes property enumeration, 0-based, which is the only way to find a
--- property whose name is not known in advance.
function Handle:PropertyCount()
  local names = rawget(self, "_order")
  if names == nil then
    names = {}
    for name in pairs(rawget(self, "_props")) do names[#names + 1] = name end
    table.sort(names)
    rawset(self, "_order", names)
  end
  return #names
end

function Handle:PropertyName(index)
  self:PropertyCount()
  return rawget(self, "_order")[index + 1]
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

--- How this mock console exposes an appearance's colour. Which one a real
--- build uses is not known, so the suite runs the colour tests against all of
--- them rather than betting on one.
---   "numbers"  - Get("BackR") returns 0-255, the documented behaviour
---   "display"  - only the display role reads, returning strings
---   "percent"  - display role, rendered as percentages
---   "combined" - one BackColor property holding all three channels
M.appearanceMode = "numbers"

--- What a cue reports for its Appearance:
---   "name"      - the appearance's name, e.g. "01 Opening"
---   "number"    - its pool number, e.g. "3"
---   "reference" - a reference, e.g. "Appearance 3"
---   "none"      - nothing at all, the case that triggers the report
M.appearanceRef = "name"

--- Where the Appearances collection hangs off the data pool:
---   "Appearances" | "Appearance" | "children" (found only by scanning)
M.appearanceCollection = "Appearances"

--- Which property on a cue holds the appearance. "Appearance" is the obvious
--- one; "CueAppearanceRef" stands in for a build that names it something else,
--- reachable only by enumerating properties.
M.appearanceProperty = "Appearance"

--- Where the Appearances pool lives: "datapool" or "showdata". A diagnostic
--- from a real console found nothing under the data pool, so show level is
--- the case that matters.
M.appearanceScope = "datapool"

--- Stable pool number per appearance, so a cue can reference it by number.
local APPEARANCE_NUMBERS = {}
do
  local names = {}
  for _, spec in pairs(APPEARANCES) do names[#names + 1] = spec.name end
  table.sort(names)
  for position, name in ipairs(names) do APPEARANCE_NUMBERS[name] = position end
end

--- How a cue refers to its appearance, per M.appearanceRef.
local function appearanceReference(spec)
  if spec == nil then return "" end
  local number = APPEARANCE_NUMBERS[spec.name]
  if M.appearanceRef == "number" then return tostring(number) end
  if M.appearanceRef == "reference" then return "Appearance " .. number end
  if M.appearanceRef == "none" then return "" end
  return spec.name
end

local function appearanceHandle(spec)
  if spec == nil then return nil end

  local mode = M.appearanceMode
  local number = tostring(APPEARANCE_NUMBERS[spec.name] or 0)

  if mode == "display" then
    return newHandle(
      { No = number, Name = spec.name, BackR = tostring(spec.r),
        BackG = tostring(spec.g), BackB = tostring(spec.b), BackAlpha = "255" },
      { name = spec.name })
  end

  if mode == "percent" then
    local function pct(value) return string.format("%.1f%%", value / 255 * 100) end
    return newHandle(
      { No = number, Name = spec.name, BackR = pct(spec.r), BackG = pct(spec.g),
        BackB = pct(spec.b), BackAlpha = "100%" }, { name = spec.name })
  end

  if mode == "combined" then
    return newHandle(
      { No = number, Name = spec.name,
        BackColor = string.format("%d,%d,%d", spec.r, spec.g, spec.b) },
      { name = spec.name })
  end

  return newHandle(
    { No = number, Name = spec.name, BackR = spec.r, BackG = spec.g,
      BackB = spec.b, BackAlpha = 255 },
    { name = spec.name, backr = spec.r, backg = spec.g, backb = spec.b, backalpha = 255 })
end

--- Every appearance in the show, as the Appearances pool holds them.
local APPEARANCE_POOL = {}

local function cueHandle(no, name, fade, delay, note, appearanceSpec)
  local part = newHandle(
    { CueFade = fade, CueDelay = delay },
    { cuefade = fade, cuedelay = delay })

  -- Reproduce what the console actually does, which is what broke v1.2.0:
  --
  --   * Get("No", Display) returns the cue's whole label, "Cue 1 Blackout",
  --     not the number -- so the Cue column printed the label and the name
  --     appeared twice.
  --   * cue.appearance is nil and Get("Appearance", Display) returns only the
  --     appearance's *name*, so reading colour off a handle finds nothing and
  --     every cue exported uncoloured.
  -- The display role quotes names: Cue 1 'House to Half'.
  local label = "Cue " .. no
  if name ~= "" then label = label .. " '" .. name .. "'" end

  -- Name comes back through the display role as well, so it arrives as the
  -- whole label too -- which is why the Name column read "Cue 1 Blackout"
  -- while the Cue column beside it already said 1.
  local cue = newHandle(
    {
      No         = label,
      Name       = label,
      Note       = note,
      Appearance = function()
        if M.appearanceProperty ~= "Appearance" then return nil end
        return appearanceReference(appearanceSpec)
      end,
      -- Some builds expose it under another name entirely, findable only by
      -- enumerating properties.
      CueAppearanceRef = function()
        if M.appearanceProperty ~= "CueAppearanceRef" then return nil end
        return appearanceReference(appearanceSpec)
      end,
    },
    { note = note },
    { part })

  -- The plugin reads the first cue part as cue[1]; mirror that.
  rawget(cue, "_attrs")[1] = part
  return cue
end

--- MA3 hangs these off every sequence; they must not reach the PDF. They do
--- not carry a "Cue n" label the way ordinary cues do.
local function specialCueHandles()
  local function special(no, name)
    local part = newHandle({ CueFade = "0", CueDelay = "0" }, {})
    local cue = newHandle({ No = no, Name = name, Note = "" }, {}, { part })
    rawget(cue, "_attrs")[1] = part
    return cue
  end

  return { special("0", "CueZero"), special("OffCue", "OffCue") }
end

--- Rebuilt on every install() so a changed appearanceMode takes effect.
local function rebuildAppearancePool()
  local specs = {}
  for _, spec in pairs(APPEARANCES) do specs[#specs + 1] = spec end
  -- pairs() order is arbitrary; sort so the pool is deterministic.
  table.sort(specs, function(a, b) return a.name < b.name end)

  APPEARANCE_POOL = {}
  for _, spec in ipairs(specs) do
    APPEARANCE_POOL[#APPEARANCE_POOL + 1] = appearanceHandle(spec)
  end
end

--- Build a sequence long enough to force several page breaks.
local function buildLongSequence()
  local cues = specialCueHandles()

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

  -- Shaped like the real show: a song-header cue carries the Appearance and
  -- holds the song title, its sub-cues carry none. The two songs deliberately
  -- share one Appearance -- they must still come out as two sections, which
  -- only works because the sub-cues between them break the run.
  add("58", "It Really Is Amazing Grace", "3", "0", "Band starts", APPEARANCES.ballad)
  add("58.001", "Words ON",     "0", "0", "", nil)
  add("58.002", "Intro ALL IN", "2", "0", "", nil)
  add("58.003", "Verse 1/2",    "2", "0", "", nil)

  add("59", "Great Are You Lord", "3", "0", "Same appearance as the song above",
    APPEARANCES.ballad)
  add("59.001", "Verse 1", "0", "0", "", nil)
  add("59.002", "Chorus",  "2", "0", "", nil)

  -- A section-opening cue with no name, which must fall back to "Cue 59.5".
  add("59.5", "", "1", "0", "Unnamed section head", APPEARANCES.chorus)
  add("59.501", "After the unnamed head", "0", "0", "", nil)

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

-- Data pool 1 is the active one. The interesting sequences live in pool 2, so
-- any test that exports them proves the pool switch really happened rather
-- than silently falling back to DataPool().
local POOL_1_SEQUENCES = {
  newHandle({ No = "1 (1)",  Name = "Rehearsal Scratch" }, { no = 1,  name = "Rehearsal Scratch" },
    { cueHandle("1", "Only Cue", "3", "0", "Single-cue sequence", nil) }),

  newHandle({ No = "13 (0)", Name = "Empty Sequence" }, { no = 13, name = "Empty Sequence" }, {}),
}

local POOL_2_SEQUENCES = {
  -- Sequence numbers arrive dressed up too, so the same fix has to cover them.
  newHandle({ No = "12 (58)", Name = "Act One (Main)" }, { no = 12, name = "Act One (Main)" },
    buildLongSequence()),

  newHandle({ No = "20 (1)", Name = "Songs Only Encore" }, { no = 20, name = "Songs Only Encore" },
    { cueHandle("1", "Pool Two Marker", "2", "0", "Exists only in data pool 2", nil) }),
}

-- Enough sequences to overflow a radio group, which is what broke on hardware.
for i = 1, 40 do
  POOL_2_SEQUENCES[#POOL_2_SEQUENCES + 1] = newHandle(
    { No = tostring(100 + i), Name = "Song " .. i },
    { no = 100 + i, name = "Song " .. i },
    { cueHandle("1", "Go", "3", "0", "", nil) })
end

local SEQUENCES = POOL_2_SEQUENCES

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
--- Scripted PopupInput answers: a label string, or nil to dismiss.
M.popupAnswers = {}
M.dialogLog = {}
--- Every item list PopupInput was handed, so tests can assert on it.
M.popupLog = {}
--- What each MessageBox selector offered: { title, labels, message }.
M.offered = {}
--- Largest number of radio entries any MessageBox selector was given.
M.maxSelectorEntries = 0

--- Set to false before install() to simulate a build without PopupInput.
M.hasPopupInput = true
--- Reproduces the grandMA3 2.4 behaviour that broke v1.1.0: PopupInput exists
--- and can be called, but returns nil without ever drawing anything.
M.popupInputAlwaysNil = true

local function buildDataPool(sequences)
  local sequencePool = newHandle({}, {}, sequences)
  for _, sequence in ipairs(sequences) do
    -- No reads "12 (58)", so index on the number inside it.
    local number = tonumber(tostring(rawget(sequence, "_props").No):match("%d+"))
    rawget(sequencePool, "_attrs")[number] = sequence
  end

  -- Colours live here. Where the collection hangs off the data pool varies,
  -- so M.appearanceCollection decides which route exposes it.
  local appearancePool = newHandle({ Name = "Appearances" }, {}, APPEARANCE_POOL)

  local children = {}
  local pool = newHandle({}, { sequences = sequencePool }, children)
  rawget(pool, "_attrs").Sequences = sequencePool

  -- On a real console the pool was found nowhere under the data pool; it is a
  -- show-level pool. In that mode nothing is hung here at all.
  if M.appearanceScope == "showdata" then
    return pool
  end

  if M.appearanceCollection == "Appearance" then
    rawget(pool, "_attrs").Appearance = appearancePool
  elseif M.appearanceCollection == "children" then
    -- Reachable only by scanning the data pool's children for one named
    -- Appearances, the accessor-independent catch-all.
    children[#children + 1] = appearancePool
  else
    rawget(pool, "_attrs").Appearances = appearancePool
    rawget(pool, "_attrs").appearances = appearancePool
  end

  return pool
end

function M.install()
  _G.Enums = { Roles = { Display = 2, Default = 0, Edit = 1 } }

  rebuildAppearancePool()

  local driveCollect = newHandle({}, {}, DRIVES)
  local temp = newHandle({}, { drivecollect = driveCollect })
  rawget(temp, "_attrs").DriveCollect = driveCollect
  local manetsocket = newHandle({}, { showfile = "Demo Show 2026" })

  local poolOne = buildDataPool(POOL_1_SEQUENCES)
  local poolTwo = buildDataPool(POOL_2_SEQUENCES)

  -- The console reports a data pool's No as a rendered label, "1 (16)", not a
  -- number. Comparing that against a typed "1" is what made the data pool
  -- field reject every value, including its own prefill.
  rawget(poolOne, "_props").No   = "1 (16)"
  rawget(poolOne, "_props").Name = "Default"
  rawget(poolTwo, "_props").No   = "2 (17)"
  rawget(poolTwo, "_props").Name = "Songs"

  local pools = { poolOne }
  if M.twoDataPools ~= false then pools[#pools + 1] = poolTwo end

  local dataPools = newHandle({}, {}, pools)

  local showChildren = {}
  local showData = newHandle({}, { datapools = dataPools }, showChildren)
  rawget(showData, "_attrs").DataPools = dataPools

  if M.appearanceScope == "showdata" then
    local showAppearances = newHandle({ Name = "Appearances" }, {}, APPEARANCE_POOL)
    if M.appearanceCollection == "children" then
      showChildren[#showChildren + 1] = showAppearances
    else
      rawget(showData, "_attrs").Appearances = showAppearances
    end
  end

  local root = newHandle({}, {
    temp = temp, manetsocket = manetsocket, showdata = showData,
  })
  rawget(root, "_attrs").Temp = temp
  rawget(root, "_attrs").ShowData = showData

  _G.Root     = function() return root end
  _G.ShowData = function() return showData end
  -- The *active* pool is pool 1, deliberately not the one holding the songs.
  _G.DataPool = function() return poolOne end

  _G.Printf  = function(fmt, ...) print(string.format(fmt, ...)) end
  _G.Echo    = _G.Printf
  _G.ErrEcho = function(fmt, ...) print("ERR " .. string.format(fmt, ...)) end

  _G.GetFocusDisplay = function() return newHandle({}, { index = 1 }) end

  _G.MessageBox = function(spec)
    M.dialogLog[#M.dialogLog + 1] = spec.title

    -- Track how many radio entries a selector was handed. Overflowing this is
    -- what rendered as a black square on the console.
    local labels = {}
    for _, selector in ipairs(spec.selectors or {}) do
      local count = 0
      for label in pairs(selector.values or {}) do
        count = count + 1
        labels[#labels + 1] = label
      end
      if count > M.maxSelectorEntries then M.maxSelectorEntries = count end
    end

    -- Record what the picker actually offered, so tests can assert on the
    -- filtering and paging rather than just on the outcome.
    local fields = {}
    for _, input in ipairs(spec.inputs or {}) do fields[input.name] = input.value end

    M.offered[#M.offered + 1] = {
      title = spec.title, labels = labels, message = spec.message, fields = fields,
    }

    local answer = table.remove(M.answers, 1)
    print(string.format("[dialog] %s -> %s", spec.title,
      answer and ("result=" .. tostring(answer.result)) or "no scripted answer"))
    if answer == nil then
      error("mock MessageBox: no scripted answer left for '" .. tostring(spec.title) .. "'")
    end

    -- The real dialog echoes back whatever is sitting in its fields, so a
    -- scripted answer that omits `inputs` must return the values it was given.
    if answer.inputs == nil and spec.inputs ~= nil then
      local echoed = {}
      for _, input in ipairs(spec.inputs) do echoed[input.name] = input.value end
      answer = {
        result = answer.result, selectors = answer.selectors, inputs = echoed,
      }
    end

    return answer
  end

  if M.hasPopupInput then
    _G.PopupInput = function(title, caller, items, selectedValue)
      M.popupLog[#M.popupLog + 1] = { title = title, items = items, selected = selectedValue }

      if M.popupInputAlwaysNil then
        print(string.format("[popup]  %s -> nil (never drew, as on MA3 2.4)", title))
        return nil
      end

      local answer = table.remove(M.popupAnswers, 1)
      if answer == nil then
        error("mock PopupInput: no scripted answer left for '" .. tostring(title) .. "'")
      end
      if answer == "<dismiss>" then
        print(string.format("[popup]  %s -> dismissed", title))
        return nil
      end
      print(string.format("[popup]  %s -> %s", title, tostring(answer)))
      return answer
    end
  else
    _G.PopupInput = nil
  end
end

M.sequences = SEQUENCES
return M
