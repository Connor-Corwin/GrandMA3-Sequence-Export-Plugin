--[[
  ProbeCue - a diagnostic for the Sequence Export plugin.

  Reading cue data out of MA3 is the one part of the plugin that cannot be
  tested away from a console, and it has surprised us twice: cue numbers came
  back as whole labels ("Cue 1 Blackout") and Appearance colours did not come
  back at all.

  Run this against a sequence and it prints, for the first few cues, every way
  of reading each property -- Get() plain, Get() with the display role, and
  direct attribute access -- plus the Appearance pool contents. If something is
  still wrong, this says what MA3 actually returns instead of guessing.

  Install alongside SequenceExport, run it, enter a data pool and sequence
  number, and copy the command line output.
]]

local CUES_TO_SHOW = 4

local function log(fmt, ...)
  local args = { ... }
  pcall(function() Printf("ProbeCue: " .. string.format(fmt, table.unpack(args))) end)
end

local function describe(value)
  local ok, text = pcall(tostring, value)
  if not ok then return "<untostringable>" end
  if type(value) == "string" then return string.format("string %q", value) end
  return string.format("%s %s", type(value), text)
end

--- Every way of reading one property, so the working one is obvious.
local function readEveryWay(label, handle, property)
  local role
  local ok, value = pcall(function() return Enums.Roles.Display end)
  if ok then role = value end

  local results = {}

  ok, value = pcall(function() return handle:Get(property) end)
  results[#results + 1] = "Get() = " .. (ok and describe(value) or "ERROR")

  if role ~= nil then
    ok, value = pcall(function() return handle:Get(property, role) end)
    results[#results + 1] = "Get(Display) = " .. (ok and describe(value) or "ERROR")
  end

  ok, value = pcall(function() return handle[property:lower()] end)
  results[#results + 1] = "." .. property:lower() .. " = " .. (ok and describe(value) or "ERROR")

  log("  %s %s:  %s", label, property, table.concat(results, "   |   "))
end

local function children(handle)
  local ok, kids = pcall(function() return handle:Children() end)
  if ok and type(kids) == "table" then return kids end
  return {}
end

local function findDataPool(number)
  local ok, collection = pcall(function() return ShowData().DataPools end)
  if not ok or collection == nil then
    ok, collection = pcall(function() return Root().ShowData.DataPools end)
  end
  if not ok or collection == nil then return nil end

  for _, pool in ipairs(children(collection)) do
    local ok2, no = pcall(function() return pool:Get("No") end)
    if ok2 and tonumber(no) == tonumber(number) then return pool end
  end
  return nil
end

local function Main(displayHandle)
  local result = MessageBox({
    title   = "ProbeCue",
    message = "Which sequence should be inspected?",
    display = (function()
      local ok, index = pcall(function() return displayHandle.index end)
      return ok and index or 1
    end)(),
    inputs = {
      { name = "Data pool", value = "1",  vkPlugin = "TextInputNumOnly" },
      { name = "Sequence",  value = "1",  vkPlugin = "TextInputNumOnly" },
    },
    commands = { { value = 1, name = "Probe" }, { value = 2, name = "Cancel" } },
  })

  if not result or result.result ~= 1 then return end

  local poolNumber     = tostring(result.inputs["Data pool"] or "1")
  local sequenceNumber = tostring(result.inputs["Sequence"] or "1")

  log("---- start ----")

  local pool = findDataPool(poolNumber)
  if pool == nil then
    log("Could not find data pool %s.", poolNumber)
    return
  end
  log("data pool %s found", poolNumber)

  -- Appearance pool: what colours exist, and under what names.
  local ok, appearances = pcall(function() return pool.Appearances end)
  if not ok or appearances == nil then
    log("pool.Appearances is NOT readable -- colours cannot be resolved by name")
  else
    local list = children(appearances)
    log("pool.Appearances holds %d appearance(s)", #list)
    for index, appearance in ipairs(list) do
      if index > 8 then log("  ... and %d more", #list - 8) break end
      local name = select(2, pcall(function() return appearance:Get("Name") end))
      local r = select(2, pcall(function() return appearance:Get("BackR") end))
      local g = select(2, pcall(function() return appearance:Get("BackG") end))
      local b = select(2, pcall(function() return appearance:Get("BackB") end))
      log("  appearance %s: name=%s BackR=%s BackG=%s BackB=%s",
        index, describe(name), describe(r), describe(g), describe(b))
    end
  end

  -- The sequence and its cues.
  local sequences
  ok, sequences = pcall(function() return pool.Sequences end)
  if not ok or sequences == nil then
    log("pool.Sequences is NOT readable")
    return
  end

  local sequence
  for _, candidate in ipairs(children(sequences)) do
    local ok2, no = pcall(function() return candidate:Get("No") end)
    if ok2 and tonumber(no) == tonumber(sequenceNumber) then sequence = candidate end
  end
  if sequence == nil then
    log("Could not find sequence %s in data pool %s.", sequenceNumber, poolNumber)
    return
  end

  local cues = children(sequence)
  log("sequence %s holds %d child object(s) -- note CueZero and OffCue are in here",
    sequenceNumber, #cues)

  for index, cue in ipairs(cues) do
    if index > CUES_TO_SHOW then
      log("... and %d more", #cues - CUES_TO_SHOW)
      break
    end

    log("child %d:", index)
    readEveryWay("cue", cue, "No")
    readEveryWay("cue", cue, "Name")
    readEveryWay("cue", cue, "Note")
    readEveryWay("cue", cue, "Appearance")

    local part = children(cue)[1]
    if part ~= nil then
      readEveryWay("part", part, "CueFade")
      readEveryWay("part", part, "CueDelay")
    else
      log("  cue has no part children")
    end
  end

  -- A full property dump of the first cue, for anything the above missed.
  if cues[1] ~= nil then
    log("---- Dump() of the first child ----")
    pcall(function() cues[1]:Dump() end)
  end

  log("---- end ----")
end

return Main
