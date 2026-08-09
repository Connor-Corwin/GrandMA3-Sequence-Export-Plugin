--[[
  ProbeUI - a throwaway diagnostic for the Sequence Export plugin.

  Sequence Export drives its pickers through MessageBox, because PopupInput
  (MA3's scrollable list picker, which would be the nicer widget) returned nil
  without ever drawing on grandMA3 2.4. Its exact contract could not be
  confirmed from the documentation.

  This plugin tries every plausible PopupInput calling convention against every
  plausible UI caller and reports, on the command line, which combination
  actually draws a popup and what it returns.

  Run it, and for each popup that appears just pick "Banana". Combinations that
  draw nothing will scroll past on their own.

  Then read the summary at the end and set CFG.useNativePicker = true in
  SequenceExport.lua if a convention worked.
]]

local ITEMS = { "Apple", "Banana", "Cherry" }

local function log(fmt, ...)
  local args = { ... }
  pcall(function() Printf("ProbeUI: " .. string.format(fmt, table.unpack(args))) end)
end

--- Describe a value for the log without risking a tostring() error.
local function describe(value)
  local ok, text = pcall(tostring, value)
  if not ok then return "<untostringable>" end
  return string.format("%s(%s)", type(value), text)
end

--- The plausible UI callers, in the order the community suggests trying them.
local function callers(displayHandle)
  local list = {}

  list[#list + 1] = { name = "Main's displayHandle", value = displayHandle }

  local ok, focus = pcall(function() return GetFocusDisplay() end)
  list[#list + 1] = {
    name = "GetFocusDisplay()", value = ok and focus or nil, missing = not ok,
  }

  ok, focus = pcall(function() return GetDisplayByIndex(1) end)
  list[#list + 1] = {
    name = "GetDisplayByIndex(1)", value = ok and focus or nil, missing = not ok,
  }

  -- Custom popups are documented as living under a display's ScreenOverlay,
  -- so it is worth testing as a caller too.
  ok, focus = pcall(function() return GetFocusDisplay().ScreenOverlay end)
  list[#list + 1] = {
    name = "GetFocusDisplay().ScreenOverlay", value = ok and focus or nil, missing = not ok,
  }

  return list
end

--- Item tables in each documented shape.
local function itemShapes()
  local descriptors = {}
  for index, name in ipairs(ITEMS) do
    descriptors[index] = { "str", name }
  end
  return {
    { name = "plain strings", value = ITEMS },
    { name = "{'str', name} descriptors", value = descriptors },
  }
end

--- The two documented call forms.
local function conventions()
  return {
    {
      name = "positional: PopupInput(title, caller, items)",
      call = function(caller, items)
        return PopupInput("ProbeUI", caller, items)
      end,
    },
    {
      name = "table: PopupInput{title=, caller=, items=}",
      call = function(caller, items)
        return PopupInput({ title = "ProbeUI", caller = caller, items = items })
      end,
    },
  }
end

local function Main(displayHandle)
  log("---- start ----")
  log("PopupInput is %s", _G.PopupInput ~= nil and "present" or "MISSING")

  if _G.PopupInput == nil then
    log("Nothing to probe. Sequence Export's MessageBox picker is the only option.")
    return
  end

  local working = {}

  for _, caller in ipairs(callers(displayHandle)) do
    if caller.missing then
      log("caller %s -- not available on this build", caller.name)
    else
      log("caller %s = %s", caller.name, describe(caller.value))

      for _, convention in ipairs(conventions()) do
        for _, shape in ipairs(itemShapes()) do
          local label = string.format("%s + %s + %s",
            caller.name, convention.name, shape.name)

          local ok, first, second = pcall(convention.call, caller.value, shape.value)

          if not ok then
            log("  FAIL  %s -- error: %s", label, describe(first))
          elseif first == nil and second == nil then
            log("  nil   %s -- returned nothing (did a popup draw?)", label)
          else
            log("  OK    %s -> %s, %s", label, describe(first), describe(second))
            working[#working + 1] = label
          end
        end
      end
    end
  end

  log("---- summary ----")
  if #working == 0 then
    log("No PopupInput convention returned a value.")
    log("Keep CFG.useNativePicker = false in SequenceExport.lua.")
  else
    for _, label in ipairs(working) do
      log("WORKS: %s", label)
    end
    log("Report the WORKS line(s) above so the scrollable picker can be enabled.")
  end
  log("---- end ----")
end

return Main
