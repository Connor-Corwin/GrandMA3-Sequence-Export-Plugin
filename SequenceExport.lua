--[[
  Sequence Export - exports a grandMA3 sequence as a printable PDF cue sheet.

  Columns: cue number, name, fade, delay, note.
  Appearance colors are carried over as section bands with tinted cue rows,
  so songs / sections in the sequence stay visible at a glance.

  Runs unchanged on a console and on onPC: no external tools, no hard-coded
  paths, no OS-specific calls. The PDF bytes are generated here in pure Lua
  because MA3 ships no PDF library.

  Author: Connor Corwin
  License: MIT
]]

--=============================================================================
-- CONFIG
--=============================================================================

local CFG = {
  -- US Letter portrait, in PDF points (1/72 inch).
  pageWidth   = 612,
  pageHeight  = 792,
  margin      = 36,

  titleSize   = 20,   -- sequence name
  metaSize    = 8,    -- date / showfile / cue count line
  headerSize  = 9,    -- column headers
  bodySize    = 9,    -- cue rows
  bandSize    = 9,    -- appearance / section band label
  footerSize  = 8,

  lineGap     = 11,   -- baseline-to-baseline inside a wrapped cell
  rowPadding  = 5,    -- vertical padding inside a cue row
  bandHeight  = 16,   -- height of an appearance section band
  bandGapAbove = 6,   -- breathing room before a section band

  separatorWeight = 2.5,  -- the bar under the title block
  ruleWeight      = 0.4,  -- hairline between cue rows

  -- Column widths, in points. Must sum to (pageWidth - 2*margin) = 540.
  colCue   = 55,
  colName  = 150,
  colFade  = 45,
  colDelay = 45,
  colNote  = 245,

  cellPad = 4,        -- horizontal padding inside a column

  -- How far the appearance color is blended toward white for row tints.
  -- 0 = full saturation, 1 = pure white.
  tintStrength = 0.85,

  -- Luminance above which band text flips from white to black.
  bandTextLuminanceCutoff = 0.6,

  zebra = { 0.96, 0.96, 0.96 },  -- striping for rows with no appearance
  rule  = { 0.80, 0.80, 0.80 },
  ink   = { 0.00, 0.00, 0.00 },
  muted = { 0.45, 0.45, 0.45 },

  -- Set true to log every step to the command line while diagnosing a problem.
  debug = false,

  -- MA3 keeps a CueZero and an OffCue on every sequence. They are machinery,
  -- not cues anyone wants on a printed cue sheet.
  hideSpecialCues = true,

  -- Which data pool to export from. Leave nil to be asked each run, with the
  -- field prefilled from whichever pool is active. Set a number -- dataPool = 2
  -- -- to lock it in; the field then disappears and the dialog only asks for a
  -- sequence. Editable from the console's plugin editor.
  dataPool = nil,

  -- Sections by hand, for when MA3 will not hand its Appearance colours over.
  -- Any cue whose number falls in a range gets that section's band and row
  -- tint, and these win over whatever the plugin reads from the show. Colours
  -- are 0-255, the same scale MA3 reports. Leave empty to use the show's own
  -- Appearances. Editable from the console's plugin editor.
  sections = {
    -- { from = 1,  to = 13, name = "Opening",    color = {  32,  78, 168 } },
    -- { from = 14, to = 27, name = "Ballad",     color = { 250, 236, 130 } },
    -- { from = 28, to = 49, name = "Big Chorus", color = { 198,  40,  40 } },
  },
}

local PLUGIN_NAME    = "Sequence Export"
local PLUGIN_VERSION = "1.4.0"

--- Step-by-step logging, off unless CFG.debug is set. Diagnosing a plugin that
--- misbehaves only on a console is otherwise pure guesswork.
local function trace(fmt, ...)
  if not CFG.debug then return end
  local args = { ... }
  pcall(function()
    Printf("%s [trace]: %s", PLUGIN_NAME, string.format(fmt, table.unpack(args)))
  end)
end

--=============================================================================
-- FONT METRICS
--
-- Adobe base-14 Helvetica / Helvetica-Bold advance widths, in 1/1000 em.
-- Needed so the Note column can be word-wrapped for real rather than guessed
-- at by character count.
--=============================================================================

local WIDTH_REGULAR = {
  [32]=278,[33]=278,[34]=355,[35]=556,[36]=556,[37]=889,[38]=667,[39]=191,
  [40]=333,[41]=333,[42]=389,[43]=584,[44]=278,[45]=333,[46]=278,[47]=278,
  [48]=556,[49]=556,[50]=556,[51]=556,[52]=556,[53]=556,[54]=556,[55]=556,
  [56]=556,[57]=556,[58]=278,[59]=278,[60]=584,[61]=584,[62]=584,[63]=556,
  [64]=1015,[65]=667,[66]=667,[67]=722,[68]=722,[69]=667,[70]=611,[71]=778,
  [72]=722,[73]=278,[74]=500,[75]=667,[76]=556,[77]=833,[78]=722,[79]=778,
  [80]=667,[81]=778,[82]=722,[83]=667,[84]=611,[85]=722,[86]=667,[87]=944,
  [88]=667,[89]=667,[90]=611,[91]=278,[92]=278,[93]=278,[94]=469,[95]=556,
  [96]=333,[97]=556,[98]=556,[99]=500,[100]=556,[101]=556,[102]=278,[103]=556,
  [104]=556,[105]=222,[106]=222,[107]=500,[108]=222,[109]=833,[110]=556,
  [111]=556,[112]=556,[113]=556,[114]=333,[115]=500,[116]=278,[117]=556,
  [118]=500,[119]=722,[120]=500,[121]=500,[122]=500,[123]=334,[124]=260,
  [125]=334,[126]=584,
}

local WIDTH_BOLD = {
  [32]=278,[33]=333,[34]=474,[35]=556,[36]=556,[37]=889,[38]=722,[39]=238,
  [40]=333,[41]=333,[42]=389,[43]=584,[44]=278,[45]=333,[46]=278,[47]=278,
  [48]=556,[49]=556,[50]=556,[51]=556,[52]=556,[53]=556,[54]=556,[55]=556,
  [56]=556,[57]=556,[58]=333,[59]=333,[60]=584,[61]=584,[62]=584,[63]=611,
  [64]=975,[65]=722,[66]=722,[67]=722,[68]=722,[69]=667,[70]=611,[71]=778,
  [72]=722,[73]=278,[74]=556,[75]=722,[76]=611,[77]=833,[78]=722,[79]=778,
  [80]=667,[81]=778,[82]=722,[83]=667,[84]=611,[85]=722,[86]=667,[87]=944,
  [88]=667,[89]=667,[90]=611,[91]=333,[92]=278,[93]=333,[94]=584,[95]=556,
  [96]=333,[97]=556,[98]=611,[99]=556,[100]=611,[101]=556,[102]=333,[103]=611,
  [104]=611,[105]=278,[106]=278,[107]=556,[108]=278,[109]=889,[110]=611,
  [111]=611,[112]=611,[113]=611,[114]=389,[115]=556,[116]=333,[117]=611,
  [118]=556,[119]=778,[120]=556,[121]=556,[122]=500,[123]=389,[124]=280,
  [125]=389,[126]=584,
}

-- Accented Latin letters in WinAnsi advance the same as their base letter in
-- both Helvetica faces, so derive the 0xC0-0xFF range instead of listing it.
local ACCENT_BASE = {
  [0xC0]=65,[0xC1]=65,[0xC2]=65,[0xC3]=65,[0xC4]=65,[0xC5]=65,[0xC7]=67,
  [0xC8]=69,[0xC9]=69,[0xCA]=69,[0xCB]=69,[0xCC]=73,[0xCD]=73,[0xCE]=73,
  [0xCF]=73,[0xD1]=78,[0xD2]=79,[0xD3]=79,[0xD4]=79,[0xD5]=79,[0xD6]=79,
  [0xD9]=85,[0xDA]=85,[0xDB]=85,[0xDC]=85,[0xDD]=89,
  [0xE0]=97,[0xE1]=97,[0xE2]=97,[0xE3]=97,[0xE4]=97,[0xE5]=97,[0xE7]=99,
  [0xE8]=101,[0xE9]=101,[0xEA]=101,[0xEB]=101,[0xEC]=105,[0xED]=105,
  [0xEE]=105,[0xEF]=105,[0xF1]=110,[0xF2]=111,[0xF3]=111,[0xF4]=111,
  [0xF5]=111,[0xF6]=111,[0xF9]=117,[0xFA]=117,[0xFB]=117,[0xFC]=117,
  [0xFD]=121,[0xFF]=121,
}

for code, base in pairs(ACCENT_BASE) do
  WIDTH_REGULAR[code] = WIDTH_REGULAR[base]
  WIDTH_BOLD[code]    = WIDTH_BOLD[base]
end

-- Remaining WinAnsi punctuation / symbols that see real use in cue notes.
local EXTRA_WIDTHS = {
  -- code = { regular, bold }
  [0x91] = { 222, 278 },  -- left single quote
  [0x92] = { 222, 278 },  -- right single quote
  [0x93] = { 333, 500 },  -- left double quote
  [0x94] = { 333, 500 },  -- right double quote
  [0x95] = { 350, 350 },  -- bullet
  [0x96] = { 556, 556 },  -- en dash
  [0x97] = { 1000, 1000 },-- em dash
  [0x85] = { 1000, 1000 },-- ellipsis
  [0xA0] = { 278, 278 },  -- nbsp
  [0xB0] = { 400, 400 },  -- degree
  [0xA9] = { 737, 737 },  -- copyright
  [0xAE] = { 737, 737 },  -- registered
  [0xB1] = { 584, 584 },  -- plus-minus
  [0xBD] = { 834, 834 },  -- one half
  [0xDF] = { 611, 611 },  -- sharp s
}

for code, pair in pairs(EXTRA_WIDTHS) do
  WIDTH_REGULAR[code] = pair[1]
  WIDTH_BOLD[code]    = pair[2]
end

local DEFAULT_WIDTH = 556

--=============================================================================
-- UTF-8 -> WinAnsi
--
-- The base-14 fonts are single-byte WinAnsiEncoding. Cue text out of MA3 is
-- UTF-8, so decode it and re-encode; anything with no WinAnsi equivalent
-- becomes '?' rather than corrupting the stream.
--=============================================================================

-- Codepoints that live in WinAnsi's 0x80-0x9F block, which Latin-1 leaves empty.
local WINANSI_HIGH = {
  [0x20AC]=0x80,[0x201A]=0x82,[0x0192]=0x83,[0x201E]=0x84,[0x2026]=0x85,
  [0x2020]=0x86,[0x2021]=0x87,[0x02C6]=0x88,[0x2030]=0x89,[0x0160]=0x8A,
  [0x2039]=0x8B,[0x0152]=0x8C,[0x017D]=0x8E,[0x2018]=0x91,[0x2019]=0x92,
  [0x201C]=0x93,[0x201D]=0x94,[0x2022]=0x95,[0x2013]=0x96,[0x2014]=0x97,
  [0x02DC]=0x98,[0x2122]=0x99,[0x0161]=0x9A,[0x203A]=0x9B,[0x0153]=0x9C,
  [0x017E]=0x9E,[0x0178]=0x9F,
}

--- Decode a UTF-8 string into an array of WinAnsi byte values.
local function toWinAnsi(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local cp, size

    if b < 0x80 then
      cp, size = b, 1
    elseif b >= 0xC0 and b < 0xE0 then
      cp, size = (b - 0xC0) * 0x40 + ((s:byte(i + 1) or 0x80) - 0x80), 2
    elseif b >= 0xE0 and b < 0xF0 then
      cp = (b - 0xE0) * 0x1000
         + (((s:byte(i + 1) or 0x80) - 0x80) * 0x40)
         + ((s:byte(i + 2) or 0x80) - 0x80)
      size = 3
    elseif b >= 0xF0 then
      cp, size = -1, 4   -- outside the BMP, no WinAnsi equivalent
    else
      cp, size = -1, 1   -- stray continuation byte
    end

    if cp >= 0x20 and cp <= 0x7E then
      out[#out + 1] = cp
    elseif cp >= 0xA0 and cp <= 0xFF then
      out[#out + 1] = cp
    elseif WINANSI_HIGH[cp] then
      out[#out + 1] = WINANSI_HIGH[cp]
    elseif cp == 0x09 then
      out[#out + 1] = 32   -- tab -> space
    else
      out[#out + 1] = 63   -- '?'
    end

    i = i + size
  end
  return out
end

--=============================================================================
-- PDF WRITER
--=============================================================================

local PDF = {}
PDF.__index = PDF

local FONT_REGULAR = "F1"
local FONT_BOLD    = "F2"

-- Matches one whole UTF-8 character, so cutting text never splits a multi-byte
-- sequence and turns an accented letter into a stray '?'.
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

function PDF.new(width, height)
  return setmetatable({
    width  = width,
    height = height,
    pages  = {},
  }, PDF)
end

function PDF:newPage()
  local page = { ops = {} }
  self.pages[#self.pages + 1] = page
  return page
end

--- Measure a string, in points, for the given font and size.
function PDF.textWidth(text, bold, size)
  if not text or text == "" then return 0 end
  local widths = bold and WIDTH_BOLD or WIDTH_REGULAR
  local codes  = toWinAnsi(text)
  local total  = 0
  for i = 1, #codes do
    total = total + (widths[codes[i]] or DEFAULT_WIDTH)
  end
  return total * size / 1000
end

--- Escape a string for a PDF literal, emitting WinAnsi bytes as octal.
local function escapeText(text)
  local codes = toWinAnsi(text or "")
  local out = {}
  for i = 1, #codes do
    local c = codes[i]
    if c == 40 or c == 41 or c == 92 then        -- ( ) \
      out[#out + 1] = "\\" .. string.char(c)
    elseif c < 32 or c > 126 then
      out[#out + 1] = string.format("\\%03o", c)
    else
      out[#out + 1] = string.char(c)
    end
  end
  return table.concat(out)
end

--- Break text into lines that each fit within maxWidth.
--- Words longer than the column are split mid-word rather than overflowing.
function PDF.wrapText(text, bold, size, maxWidth)
  if not text or text == "" then return {} end
  text = text:gsub("[\r\n]+", " ")

  local lines, current = {}, ""

  local function flush()
    if current ~= "" then
      lines[#lines + 1] = current
      current = ""
    end
  end

  local function pushLongWord(word)
    -- Consume the word a character at a time until it fits.
    local chunk = ""
    for ch in word:gmatch(UTF8_CHAR) do
      if PDF.textWidth(chunk .. ch, bold, size) > maxWidth and chunk ~= "" then
        lines[#lines + 1] = chunk
        chunk = ch
      else
        chunk = chunk .. ch
      end
    end
    current = chunk
  end

  for word in text:gmatch("%S+") do
    local candidate = (current == "") and word or (current .. " " .. word)
    if PDF.textWidth(candidate, bold, size) <= maxWidth then
      current = candidate
    else
      flush()
      if PDF.textWidth(word, bold, size) > maxWidth then
        pushLongWord(word)
      else
        current = word
      end
    end
  end
  flush()

  return lines
end

--- Shorten text with a trailing ellipsis so it fits maxWidth.
function PDF.truncate(text, bold, size, maxWidth)
  if not text or text == "" then return "" end
  if PDF.textWidth(text, bold, size) <= maxWidth then return text end

  local ellipsis = "..."
  local budget = maxWidth - PDF.textWidth(ellipsis, bold, size)
  if budget <= 0 then return "" end

  local out = ""
  for ch in text:gmatch(UTF8_CHAR) do
    if PDF.textWidth(out .. ch, bold, size) > budget then break end
    out = out .. ch
  end
  return out .. ellipsis
end

-- Drawing helpers. Callers work in top-down coordinates (y grows downward
-- from the top edge); these convert to PDF's bottom-left origin.

function PDF:_flipY(y)
  return self.height - y
end

function PDF:text(page, x, y, str, bold, size, color)
  if str == nil or str == "" then return end
  color = color or CFG.ink
  page.ops[#page.ops + 1] = string.format(
    "%.3f %.3f %.3f rg BT /%s %.2f Tf 1 0 0 1 %.2f %.2f Tm (%s) Tj ET",
    color[1], color[2], color[3],
    bold and FONT_BOLD or FONT_REGULAR, size,
    x, self:_flipY(y), escapeText(str))
end

function PDF:rect(page, x, y, w, h, color)
  page.ops[#page.ops + 1] = string.format(
    "%.3f %.3f %.3f rg %.2f %.2f %.2f %.2f re f",
    color[1], color[2], color[3], x, self:_flipY(y + h), w, h)
end

function PDF:line(page, x1, y1, x2, y2, color, weight)
  page.ops[#page.ops + 1] = string.format(
    "%.3f %.3f %.3f RG %.2f w %.2f %.2f m %.2f %.2f l S",
    color[1], color[2], color[3], weight,
    x1, self:_flipY(y1), x2, self:_flipY(y2))
end

--- Serialize the whole document to a PDF byte string.
function PDF:build(title)
  local objects = {}   -- objects[n] = body string for object n

  local function addObject(body)
    objects[#objects + 1] = body
    return #objects
  end

  -- Reserve 1 for the catalog and 2 for the page tree so their numbers can be
  -- referenced before their bodies are known.
  addObject("")   -- 1 catalog
  addObject("")   -- 2 pages

  local fontRegular = addObject(
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
  local fontBold = addObject(
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")

  local resources = string.format(
    "<< /Font << /%s %d 0 R /%s %d 0 R >> /ProcSet [/PDF /Text] >>",
    FONT_REGULAR, fontRegular, FONT_BOLD, fontBold)

  local kids = {}
  for i = 1, #self.pages do
    local content = table.concat(self.pages[i].ops, "\n")
    local contentNum = addObject(string.format(
      "<< /Length %d >>\nstream\n%s\nendstream", #content, content))
    local pageNum = addObject(string.format(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Resources %s /Contents %d 0 R >>",
      self.width, self.height, resources, contentNum))
    kids[#kids + 1] = string.format("%d 0 R", pageNum)
  end

  local infoNum = addObject(string.format(
    "<< /Title (%s) /Producer (%s %s) /Creator (grandMA3) >>",
    escapeText(title or "Sequence Export"), escapeText(PLUGIN_NAME), PLUGIN_VERSION))

  objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
  objects[2] = string.format("<< /Type /Pages /Kids [%s] /Count %d >>",
    table.concat(kids, " "), #self.pages)

  -- Assemble, tracking byte offsets for the cross-reference table.
  local out     = { "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n" }
  local length  = #out[1]
  local offsets = {}

  for num = 1, #objects do
    offsets[num] = length
    local chunk = string.format("%d 0 obj\n%s\nendobj\n", num, objects[num])
    out[#out + 1] = chunk
    length = length + #chunk
  end

  local xrefOffset = length
  local xref = { string.format("xref\n0 %d\n", #objects + 1), "0000000000 65535 f \n" }
  for num = 1, #objects do
    xref[#xref + 1] = string.format("%010d 00000 n \n", offsets[num])
  end
  out[#out + 1] = table.concat(xref)
  out[#out + 1] = string.format(
    "trailer\n<< /Size %d /Root 1 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n",
    #objects + 1, infoNum, xrefOffset)

  return table.concat(out)
end

--- Write the document to disk. Returns ok, errorMessage.
function PDF:writeFile(path, title)
  local file, err = io.open(path, "wb")
  if not file then
    return false, tostring(err or "could not open file for writing")
  end
  local ok, writeErr = pcall(function()
    file:write(self:build(title))
  end)
  file:close()
  if not ok then
    return false, tostring(writeErr)
  end
  return true
end

--=============================================================================
-- MA3 DATA ACCESS
--
-- The official Lua reference is not something a plugin can consult at runtime,
-- and property spellings have moved between MA3 releases. Every read goes
-- through getProp, which tries the documented Get(name, Display) call first
-- and falls back to direct attribute access. A property that cannot be read
-- yields an empty cell instead of aborting the export.
--=============================================================================

local function displayRole()
  local ok, role = pcall(function() return Enums.Roles.Display end)
  if ok then return role end
  return nil
end

--- Read a property off an MA3 handle as a display string.
local function getProp(handle, name)
  if handle == nil then return "" end

  local role = displayRole()
  if role ~= nil then
    local ok, value = pcall(function() return handle:Get(name, role) end)
    if ok and value ~= nil and value ~= "" then
      return tostring(value)
    end
  end

  local ok, value = pcall(function() return handle:Get(name) end)
  if ok and value ~= nil and value ~= "" then
    return tostring(value)
  end

  ok, value = pcall(function() return handle[name:lower()] end)
  if ok and value ~= nil and value ~= "" then
    return tostring(value)
  end

  return ""
end

--- Read a numeric property, returning nil when unreadable.
local function getNumber(handle, name)
  if handle == nil then return nil end
  local ok, value = pcall(function() return handle:Get(name) end)
  if ok and tonumber(value) then return tonumber(value) end
  ok, value = pcall(function() return handle[name:lower()] end)
  if ok and tonumber(value) then return tonumber(value) end
  return nil
end

--- Children of a handle, as a plain array. Empty on failure.
local function childrenOf(handle)
  if handle == nil then return {} end
  local ok, kids = pcall(function() return handle:Children() end)
  if ok and type(kids) == "table" then return kids end
  return {}
end

--- MA3 shows "None" for unset properties; treat that as empty.
local function clean(value)
  if value == nil then return "" end
  value = tostring(value)
  if value == "None" or value == "none" then return "" end
  return value
end

--- Drop trailing zeros so 1.000 prints as 1 and 2.500 as 2.5.
local function trimZeros(text)
  if not text:find("%.") then return text end
  return (text:gsub("0+$", ""):gsub("%.$", ""))
end

--- The first number in a display string.
---
--- Get(name, Roles.Display) returns a rendered label, not a value, so object
--- numbers arrive dressed up: a data pool's No reads "1 (16)", a sequence's
--- "12 (58)", a cue's "Cue 1 Blackout". Comparing those against a typed "1"
--- never matches, which made the data pool field reject every value including
--- the one it was prefilled with.
local function numberToken(text)
  if text == nil or text == "" then return nil end
  local token = text:match("(%d+%.?%d*)")
  if token == nil then return nil end
  return trimZeros(token)
end

--- Number and name for a pool object, tolerating an unreadable No.
local function identify(handle)
  local no = numberToken(clean(getProp(handle, "No")))
  if no == nil then
    local value = getNumber(handle, "No")
    no = value and trimZeros(string.format("%.3f", value)) or "?"
  end
  return no, clean(getProp(handle, "Name"))
end

--- Every data pool in the show: { {no, name, handle, active}, ... }
--- DataPool() only ever returns the pool that happens to be selected, so a
--- sequence living in another pool is unreachable without walking ShowData.
local function listDataPools()
  local pools = {}

  local ok, collection = pcall(function() return ShowData().DataPools end)
  if not ok or collection == nil then
    ok, collection = pcall(function() return Root().ShowData.DataPools end)
  end
  if not ok or collection == nil then return pools end

  local activeHandle
  local activeOk, active = pcall(function() return DataPool() end)
  if activeOk then activeHandle = active end

  for _, handle in ipairs(childrenOf(collection)) do
    local no, name = identify(handle)
    pools[#pools + 1] = {
      no     = no,
      name   = name,
      handle = handle,
      active = activeHandle ~= nil and handle == activeHandle,
    }
  end

  return pools
end

--- The Sequences collection of a specific data pool, or of the active pool.
local function sequencePoolOf(dataPoolHandle)
  if dataPoolHandle ~= nil then
    local ok, pool = pcall(function() return dataPoolHandle.Sequences end)
    if ok and pool ~= nil then return pool end
  end
  local ok, pool = pcall(function() return DataPool().Sequences end)
  if ok then return pool end
  return nil
end

--- All sequences in the given data pool: { {no, name, handle}, ... }
local function listSequences(dataPoolHandle)
  local sequences = {}

  local pool = sequencePoolOf(dataPoolHandle)
  if pool == nil then return sequences end

  for _, handle in ipairs(childrenOf(pool)) do
    local no, name = identify(handle)
    sequences[#sequences + 1] = {
      no     = no,
      name   = name,
      handle = handle,
    }
  end

  return sequences
end

--- Find a sequence by its pool number, as typed by the user.
local function findSequenceByNumber(sequences, number, dataPoolHandle)
  local wanted = tostring(number)
  for _, seq in ipairs(sequences) do
    if seq.no == wanted or tonumber(seq.no) == tonumber(wanted) then
      return seq
    end
  end

  -- Fall back to direct indexing, in case the listing missed it. Index the
  -- chosen pool, not the active one.
  local ok, handle = pcall(function()
    return sequencePoolOf(dataPoolHandle)[tonumber(number)]
  end)
  if ok and handle ~= nil then
    return { no = wanted, name = clean(getProp(handle, "Name")), handle = handle }
  end

  return nil
end

--- Read one colour channel.
--- Returns value, scale -- where scale is the maximum the value can reach, so
--- a percentage and an 8-bit number can be told apart.
local function colorChannel(handle, name)
  local spellings = { name, name:upper(), name:lower() }

  -- A plain value, if this build hands one over.
  for _, spelling in ipairs(spellings) do
    local value = getNumber(handle, spelling)
    if value ~= nil then return value, nil end
  end

  -- Otherwise the display role, which on some builds is the only reader that
  -- works at all -- it is what every other property on this plugin relies on.
  -- The rendered value may carry a unit, so read the scale off it too.
  for _, spelling in ipairs(spellings) do
    local display = getProp(handle, spelling)
    if display ~= "" then
      local token = numberToken(display)
      if token ~= nil then
        return tonumber(token), display:find("%%") and 100 or nil
      end
    end
  end

  return nil, nil
end

--- Some builds expose the colour as one property rather than three channels.
local function combinedColor(handle)
  for _, name in ipairs({ "BackColor", "Color", "BackRGB" }) do
    local text = getProp(handle, name)
    if text ~= "" then
      local values = {}
      for token in text:gmatch("%d+%.?%d*") do
        values[#values + 1] = tonumber(token)
      end
      if #values >= 3 then
        return values[1], values[2], values[3], text:find("%%") and 100 or nil
      end
    end
  end
  return nil
end

--- Turn an Appearance handle into a normalized colour, or nil.
local function colorFromAppearance(appearance)
  if appearance == nil then return nil end

  local r, rScale = colorChannel(appearance, "BackR")
  local g, gScale = colorChannel(appearance, "BackG")
  local b, bScale = colorChannel(appearance, "BackB")

  local reportedScale = rScale or gScale or bScale

  if r == nil and g == nil and b == nil then
    r, g, b, reportedScale = combinedColor(appearance)
    if r == nil then return nil end
  end

  r, g, b = r or 0, g or 0, b or 0

  -- A fully transparent appearance carries no colour.
  local alpha = colorChannel(appearance, "BackAlpha")
  if alpha ~= nil and alpha <= 0 then return nil end

  -- Documented as 0-255, but a build that renders percentages or fractions
  -- would otherwise come out almost black.
  local scale = reportedScale or 255
  if reportedScale == nil then
    if r <= 1 and g <= 1 and b <= 1 and (r > 0 or g > 0 or b > 0) then
      scale = 1
    elseif r <= 100 and g <= 100 and b <= 100 and math.max(r, g, b) > 1 then
      -- Ambiguous between 0-100 and a dark 0-255 colour. 0-255 is documented,
      -- so keep it; CFG.debug reports the raw values if this is ever wrong.
      scale = 255
    end
  end

  local name = clean(getProp(appearance, "Name"))

  return {
    r    = math.min(1, r / scale),
    g    = math.min(1, g / scale),
    b    = math.min(1, b / scale),
    name = name,
    key  = name ~= "" and name or string.format("%d,%d,%d", r, g, b),
  }
end

--- Name -> colour for every Appearance in a data pool.
---
--- Needed because reading a cue's Appearance as a *handle* does not work on
--- every build: getProp() goes through Get(name, Roles.Display), which returns
--- a display string. That is why cue numbers arrive as "Cue 1 Blackout" rather
--- than 1, and by the same token an Appearance arrives as its name. Indexing
--- the pool by name turns that string back into a colour.
--- Every route to a data pool's Appearances collection, in order of likelihood.
--- Returns collection, routeName.
local function findAppearanceCollection(dataPoolHandle)
  local routes = {}

  if dataPoolHandle ~= nil then
    routes[#routes + 1] = { name = "pool.Appearances",
      get = function() return dataPoolHandle.Appearances end }
    routes[#routes + 1] = { name = "pool.Appearance",
      get = function() return dataPoolHandle.Appearance end }
  end
  routes[#routes + 1] = { name = "DataPool().Appearances",
    get = function() return DataPool().Appearances end }
  routes[#routes + 1] = { name = "DataPool().Appearance",
    get = function() return DataPool().Appearance end }

  for _, route in ipairs(routes) do
    local ok, collection = pcall(route.get)
    if ok and collection ~= nil and #childrenOf(collection) > 0 then
      return collection, route.name
    end
  end

  -- Catch-all that does not depend on the accessor spelling: walk the data
  -- pool's own children looking for the one called Appearances.
  for _, handle in ipairs(childrenOf(dataPoolHandle)) do
    local name = clean(getProp(handle, "Name")):lower()
    if name == "appearances" or name == "appearance" then
      return handle, "child scan"
    end
  end

  return nil, nil
end

--- Name -> colour for every Appearance in a data pool.
local function buildAppearanceIndex(dataPoolHandle)
  local index = {}

  local collection, route = findAppearanceCollection(dataPoolHandle)
  if collection == nil then
    trace("no appearance collection found")
    return index
  end
  trace("appearance collection found via %s", route)

  local entries = {}
  for position, handle in ipairs(childrenOf(collection)) do
    local color = colorFromAppearance(handle)
    if color ~= nil then
      entries[#entries + 1] = {
        color    = color,
        position = position,
        name     = clean(getProp(handle, "Name")),
        number   = numberToken(clean(getProp(handle, "No"))),
      }
    end
  end

  local function claim(key, color)
    if key ~= nil and key ~= "" and index[key] == nil then
      index[key] = color
    end
  end

  -- Name and pool number are authoritative, so they are claimed first. A cue
  -- may report any of these forms and which one is not knowable from here.
  for _, entry in ipairs(entries) do
    claim(entry.name, entry.color)
    claim(entry.name:lower(), entry.color)
    if entry.number ~= nil then
      claim(entry.number, entry.color)
      claim("appearance " .. entry.number, entry.color)
    end
  end

  -- Position is a weak fallback for appearances with no readable number, and
  -- must never shadow a real one -- pool order is not the same as numbering.
  for _, entry in ipairs(entries) do
    claim(tostring(entry.position), entry.color)
  end

  return index
end

--- Look a cue's reported appearance up under every form it might take.
local function lookupAppearance(index, reported)
  if index == nil or reported == nil or reported == "" then return nil end

  local candidates = { reported, reported:lower() }

  local token = numberToken(reported)
  if token ~= nil then
    candidates[#candidates + 1] = token
    candidates[#candidates + 1] = "appearance " .. token
  end

  for _, key in ipairs(candidates) do
    if index[key] ~= nil then return index[key] end
  end

  return nil
end

--- The colour for a cue, from a handle when that works and from the appearance
--- name index when it does not.
local function readAppearance(cueHandle, appearanceIndex)
  local candidates = {
    function() return cueHandle.appearance end,
    function() return cueHandle.Appearance end,
    function() return cueHandle:Get("Appearance") end,
  }

  for index, get in ipairs(candidates) do
    local ok, value = pcall(get)
    if ok and value ~= nil and type(value) ~= "string" then
      local color = colorFromAppearance(value)
      if color ~= nil then
        trace("appearance read from handle (strategy %d)", index)
        return color
      end
    end
  end

  -- Fall back to the display string, which names or references the appearance.
  local reported = clean(getProp(cueHandle, "Appearance"))
  if reported ~= "" then
    local color = lookupAppearance(appearanceIndex, reported)
    if color ~= nil then
      trace("appearance %q resolved through the pool index", reported)
      return color
    end
    trace("appearance %q is not in the pool index", reported)
  else
    trace("cue reports no appearance at all")
  end

  return nil
end

--- The cue's number on its own.
---
--- The display string is the cue's whole label -- "Cue 1 Blackout" -- so take
--- the number out of it rather than printing the label into a column that
--- already has the name beside it.
local function cueNumber(cueHandle)
  local token = numberToken(getProp(cueHandle, "No"))
  if token then return token end

  local value = getNumber(cueHandle, "No")
  if value then return trimZeros(string.format("%.3f", value)) end

  return ""
end

--- Strip a leading "Cue 12 " from a cue's name.
---
--- Name comes back through the display role too, so it arrives as the cue's
--- whole label rather than just the name -- putting "Cue 12 Blackout" in a Name
--- column that already has 12 in the Cue column beside it. Only strip when the
--- number in the prefix is this cue's own, so a cue genuinely called
--- "Cue 5 Standby" sitting at cue 9 keeps its name.
local function stripCueLabel(name, number)
  if name == "" or number == "" then return name end

  local prefix = name:match("^%s*[Cc][Uu][Ee]%s+(%d+%.?%d*)")
  if prefix == nil then return name end
  if trimZeros(prefix) ~= number then return name end

  local stripped = name:gsub("^%s*[Cc][Uu][Ee]%s+%d+%.?%d*%s*", "")
  return (stripped:match("^%s*(.-)%s*$"))
end

--- MA3 hangs a CueZero and an OffCue off every sequence. Neither belongs on a
--- printed cue sheet.
local function isSpecialCue(name, number)
  local squashed = name:lower():gsub("%s+", "")
  if squashed == "cuezero" or squashed == "offcue" then return true end
  if tonumber(number) == 0 then return true end
  return false
end

--=============================================================================
-- APPEARANCE REPORT
--
-- Appearance colours have failed to export three times running, and none of it
-- is reproducible away from a console. Rather than guess a fourth time, an
-- export that reads no colour at all writes this alongside the PDF: every
-- route tried and everything MA3 handed back. One export then answers the
-- question instead of another round of inference.
--=============================================================================

--- Render a value with its type, without risking a tostring() error.
local function describeValue(value)
  local ok, text = pcall(tostring, value)
  if not ok then return "<untostringable>" end
  if type(value) == "string" then return string.format("string %q", value) end
  return string.format("%s %s", type(value), text)
end

--- Read one property every way there is, for the report.
local function readEveryWay(handle, property)
  local parts = {}

  local ok, value = pcall(function() return handle:Get(property) end)
  parts[#parts + 1] = "Get() = " .. (ok and describeValue(value) or "ERROR")

  local role = displayRole()
  if role ~= nil then
    ok, value = pcall(function() return handle:Get(property, role) end)
    parts[#parts + 1] = "Get(Display) = " .. (ok and describeValue(value) or "ERROR")
  end

  ok, value = pcall(function() return handle[property:lower()] end)
  parts[#parts + 1] = "." .. property:lower() .. " = " ..
    (ok and describeValue(value) or "ERROR")

  return table.concat(parts, "   |   ")
end

--- Build the diagnostic text for a data pool and a sequence's cues.
local function buildAppearanceReport(dataPoolHandle, sequenceHandle, index)
  local lines = {}
  local function add(fmt, ...)
    local args = { ... }
    local ok, text = pcall(string.format, fmt, table.unpack(args))
    lines[#lines + 1] = ok and text or fmt
  end

  add("%s %s - appearance diagnostic", PLUGIN_NAME, PLUGIN_VERSION)
  add("No cue in this sequence reported an Appearance colour, so this file")
  add("records everything the plugin tried and what grandMA3 returned.")
  add("")

  add("== where the Appearance pool was looked for ==")
  local collection, route = findAppearanceCollection(dataPoolHandle)
  if collection == nil then
    add("  NOT FOUND by any route -- colours cannot be resolved by name.")
  else
    add("  found via %s, holding %d appearance(s)", route, #childrenOf(collection))
  end
  add("")

  if collection ~= nil then
    add("== what each Appearance reports ==")
    for position, handle in ipairs(childrenOf(collection)) do
      if position > 8 then
        add("  ... and %d more", #childrenOf(collection) - 8)
        break
      end
      add("  appearance %d:", position)
      for _, property in ipairs({ "Name", "No", "BackR", "BackG", "BackB", "BackColor" }) do
        add("    %-10s %s", property, readEveryWay(handle, property))
      end
      local color = colorFromAppearance(handle)
      add("    -> plugin read: %s", color and
        string.format("r=%.3f g=%.3f b=%.3f", color.r, color.g, color.b) or "NO COLOUR")
    end
    add("")
  end

  add("== the lookup keys that were built ==")
  local keys = {}
  for key in pairs(index or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  if #keys == 0 then
    add("  none -- the index is empty")
  else
    add("  %s", table.concat(keys, ", "))
  end
  add("")

  add("== what each cue reports for its Appearance ==")
  local shown = 0
  for _, cueHandle in ipairs(childrenOf(sequenceHandle)) do
    local number = cueNumber(cueHandle)
    local name   = clean(getProp(cueHandle, "Name"))

    -- Skip CueZero and OffCue so the sample is real cues.
    if not isSpecialCue(name, number) then
      shown = shown + 1
      if shown > 8 then break end
      add("  cue %s (%s):", number, stripCueLabel(name, number))
      add("    Appearance %s", readEveryWay(cueHandle, "Appearance"))
    end
  end
  add("")
  add("Send this file back and the colour question is settled.")

  return table.concat(lines, "\n") .. "\n"
end

--- Write the report next to the PDF. Never lets a failure break the export.
local function writeAppearanceReport(pdfPath, text)
  local path = pdfPath:gsub("%.[Pp][Dd][Ff]$", "") .. "-appearance-report.txt"
  local ok = pcall(function()
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
  end)
  if ok then return path end
  return nil
end

--- The hand-configured section covering a cue number, if there is one.
--- These win over whatever the show reports, so a user who cannot get MA3 to
--- hand its Appearances over still gets coloured sections.
local function manualSection(number)
  local value = tonumber(number)
  if value == nil then return nil end

  for _, section in ipairs(CFG.sections or {}) do
    local from = tonumber(section.from) or -math.huge
    local to   = tonumber(section.to) or math.huge
    if value >= from and value <= to then
      local color = section.color or { 128, 128, 128 }
      local name  = section.name or ""
      return {
        r    = (tonumber(color[1]) or 0) / 255,
        g    = (tonumber(color[2]) or 0) / 255,
        b    = (tonumber(color[3]) or 0) / 255,
        name = name,
        key  = "manual:" .. (name ~= "" and name or tostring(from)),
      }
    end
  end

  return nil
end

--- Every cue of a sequence, in sheet order.
local function collectCues(sequenceHandle, appearanceIndex)
  local cues = {}

  for _, cueHandle in ipairs(childrenOf(sequenceHandle)) do
    -- Timing lives on the cue part, not the cue: CueFade is internally
    -- CueInFade/CueOutFade, so only the display role yields the combined
    -- string the sequence sheet shows.
    local part
    local ok, first = pcall(function() return cueHandle[1] end)
    if ok and first ~= nil then
      part = first
    else
      part = childrenOf(cueHandle)[1]
    end

    local number = cueNumber(cueHandle)
    local name   = stripCueLabel(clean(getProp(cueHandle, "Name")), number)

    if CFG.hideSpecialCues and isSpecialCue(name, number) then
      trace("skipping special cue %q (no %q)", name, number)
    else
      local fromShow = readAppearance(cueHandle, appearanceIndex)

      cues[#cues + 1] = {
        no             = number,
        name           = name,
        note           = clean(getProp(cueHandle, "Note")),
        fade           = clean(getProp(part, "CueFade")),
        delay          = clean(getProp(part, "CueDelay")),
        appearance     = manualSection(number) or fromShow,
        -- Tracked separately so the export can tell whether the show gave up
        -- anything at all, and write a diagnostic report when it did not.
        fromShow       = fromShow ~= nil,
      }
    end
  end

  return cues
end

--- Storage devices currently attached, removable ones first.
local function listDrives()
  local drives = {}

  local ok, collection = pcall(function() return Root().Temp.DriveCollect end)
  if not ok or collection == nil then return drives end

  local items = childrenOf(collection)
  if #items == 0 then
    -- Some releases expose DriveCollect as a plain iterable rather than a
    -- handle with Children().
    local iterOk = pcall(function()
      for _, drive in ipairs(collection) do items[#items + 1] = drive end
    end)
    if not iterOk then return drives end
  end

  for _, drive in ipairs(items) do
    local path = clean(getProp(drive, "Path"))
    if path ~= "" then
      local driveType = clean(getProp(drive, "DriveType"))
      drives[#drives + 1] = {
        name      = clean(getProp(drive, "Name")),
        path      = path,
        driveType = driveType,
        removable = driveType:lower():find("remove") ~= nil,
      }
    end
  end

  table.sort(drives, function(a, b)
    if a.removable ~= b.removable then return a.removable end
    return a.name < b.name
  end)

  return drives
end

--=============================================================================
-- LAYOUT
--=============================================================================

local COLUMNS = {
  { key = "no",    label = "Cue",   width = CFG.colCue,   wrap = false },
  { key = "name",  label = "Name",  width = CFG.colName,  wrap = false },
  { key = "fade",  label = "Fade",  width = CFG.colFade,  wrap = false },
  { key = "delay", label = "Delay", width = CFG.colDelay, wrap = false },
  { key = "note",  label = "Note",  width = CFG.colNote,  wrap = true  },
}

--- Blend a color toward white. amount 0 = unchanged, 1 = white.
local function tint(color, amount)
  return {
    color.r + (1 - color.r) * amount,
    color.g + (1 - color.g) * amount,
    color.b + (1 - color.b) * amount,
  }
end

--- Pick black or white text for legibility on the given background.
local function contrastingInk(color)
  local luminance = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
  if luminance > CFG.bandTextLuminanceCutoff then
    return { 0, 0, 0 }
  end
  return { 1, 1, 1 }
end

--- Build the PDF for a sequence. Returns the PDF object.
local function renderDocument(sequenceName, sequenceNumber, cues, showfile)
  local pdf = PDF.new(CFG.pageWidth, CFG.pageHeight)

  local left        = CFG.margin
  local right       = CFG.pageWidth - CFG.margin
  local contentWidth = right - left
  local bottomLimit = CFG.pageHeight - CFG.margin - CFG.footerSize - 6

  -- Precompute each column's x offset.
  local columnX, x = {}, left
  for i, column in ipairs(COLUMNS) do
    columnX[i] = x
    x = x + column.width
  end

  local page, y

  local function drawColumnHeader()
    for i, column in ipairs(COLUMNS) do
      pdf:text(page, columnX[i] + CFG.cellPad, y + CFG.headerSize,
        column.label, true, CFG.headerSize, CFG.ink)
    end
    y = y + CFG.headerSize + CFG.rowPadding
    pdf:line(page, left, y, right, y, CFG.ink, 0.8)
    y = y + 2
  end

  local function drawSectionBand(appearance, continued)
    local label = appearance.name ~= "" and appearance.name or "(unnamed appearance)"
    if continued then label = label .. "  (cont.)" end

    y = y + CFG.bandGapAbove
    pdf:rect(page, left, y, contentWidth, CFG.bandHeight, { appearance.r, appearance.g, appearance.b })
    pdf:text(page, left + CFG.cellPad + 2, y + CFG.bandHeight - 5,
      PDF.truncate(label, true, CFG.bandSize, contentWidth - CFG.cellPad * 2 - 4),
      true, CFG.bandSize, contrastingInk(appearance))
    y = y + CFG.bandHeight
  end

  local pageCount = 0
  local currentSection = nil

  -- A cue row is never split across pages, so a note longer than one whole
  -- page has to be clipped or it would run off the bottom. Derive the cap from
  -- the page geometry rather than hard-coding it.
  local continuationHeaderHeight =
    CFG.margin + CFG.metaSize + 8 + CFG.separatorWeight + 8
    + CFG.headerSize + CFG.rowPadding + 2 + CFG.bandHeight + CFG.bandGapAbove
  local maxNoteLines = math.max(1,
    math.floor((bottomLimit - continuationHeaderHeight - CFG.rowPadding) / CFG.lineGap))

  local function startPage(isFirst)
    page = pdf:newPage()
    pageCount = pageCount + 1
    y = CFG.margin

    if isFirst then
      -- Sequence name, bold, top left.
      pdf:text(page, left, y + CFG.titleSize,
        PDF.truncate(sequenceName, true, CFG.titleSize, contentWidth),
        true, CFG.titleSize, CFG.ink)
      y = y + CFG.titleSize + 6

      local meta = {}
      if sequenceNumber and sequenceNumber ~= "" then
        meta[#meta + 1] = "Sequence " .. sequenceNumber
      end
      meta[#meta + 1] = #cues .. (#cues == 1 and " cue" or " cues")
      if showfile and showfile ~= "" then meta[#meta + 1] = showfile end
      local stampOk, stamp = pcall(function() return os.date("%Y-%m-%d %H:%M") end)
      if stampOk and type(stamp) == "string" then meta[#meta + 1] = stamp end

      pdf:text(page, left, y + CFG.metaSize,
        PDF.truncate(table.concat(meta, "   \194\183   "), false, CFG.metaSize, contentWidth),
        false, CFG.metaSize, CFG.muted)
      y = y + CFG.metaSize + 8
    else
      pdf:text(page, left, y + CFG.metaSize,
        PDF.truncate(sequenceName .. "  (continued)", true, CFG.metaSize, contentWidth),
        true, CFG.metaSize, CFG.muted)
      y = y + CFG.metaSize + 8
    end

    -- The bar separating the header block from the cues.
    pdf:rect(page, left, y, contentWidth, CFG.separatorWeight, CFG.ink)
    y = y + CFG.separatorWeight + 8

    drawColumnHeader()
  end

  startPage(true)

  local zebraIndex = 0

  for _, cue in ipairs(cues) do
    local sectionKey = cue.appearance and cue.appearance.key or nil

    -- Measure the row before committing it, so a row never straddles a page.
    local values = {
      no    = cue.no,
      name  = cue.name,
      fade  = cue.fade,
      delay = cue.delay,
      note  = cue.note,
    }

    local cells, lineCount = {}, 1
    for i, column in ipairs(COLUMNS) do
      local available = column.width - CFG.cellPad * 2
      if column.wrap then
        local lines = PDF.wrapText(values[column.key], false, CFG.bodySize, available)
        if #lines == 0 then lines = { "" } end
        if #lines > maxNoteLines then
          local clipped = {}
          for index = 1, maxNoteLines do clipped[index] = lines[index] end
          clipped[maxNoteLines] =
            PDF.truncate(clipped[maxNoteLines] .. " ...", false, CFG.bodySize, available)
          lines = clipped
        end
        cells[i] = lines
        if #lines > lineCount then lineCount = #lines end
      else
        cells[i] = { PDF.truncate(values[column.key], false, CFG.bodySize, available) }
      end
    end

    local rowHeight = lineCount * CFG.lineGap + CFG.rowPadding
    local needsBand = sectionKey ~= currentSection and cue.appearance ~= nil
    local needed = rowHeight + (needsBand and (CFG.bandHeight + CFG.bandGapAbove) or 0)

    if y + needed > bottomLimit then
      startPage(false)
      -- Carry the section context onto the new page.
      if cue.appearance ~= nil then
        drawSectionBand(cue.appearance, sectionKey == currentSection)
        currentSection = sectionKey
        needsBand = false
      else
        currentSection = nil
      end
      zebraIndex = 0
    end

    if needsBand then
      drawSectionBand(cue.appearance, false)
      currentSection = sectionKey
      zebraIndex = 0
    elseif cue.appearance == nil then
      currentSection = nil
    end

    -- Row background: appearance tint, or zebra striping when uncolored.
    if cue.appearance ~= nil then
      pdf:rect(page, left, y, contentWidth, rowHeight, tint(cue.appearance, CFG.tintStrength))
    elseif zebraIndex % 2 == 1 then
      pdf:rect(page, left, y, contentWidth, rowHeight, CFG.zebra)
    end

    for i, lines in ipairs(cells) do
      for lineIndex, lineText in ipairs(lines) do
        pdf:text(page,
          columnX[i] + CFG.cellPad,
          y + CFG.rowPadding * 0.5 + lineIndex * CFG.lineGap - 2,
          lineText, false, CFG.bodySize, CFG.ink)
      end
    end

    y = y + rowHeight
    pdf:line(page, left, y, right, y, CFG.rule, CFG.ruleWeight)
    zebraIndex = zebraIndex + 1
  end

  -- Footers go on last, once the total page count is known.
  local footerY = CFG.pageHeight - CFG.margin + CFG.footerSize
  for index, footerPage in ipairs(pdf.pages) do
    pdf:text(footerPage, left, footerY,
      PLUGIN_NAME .. " " .. PLUGIN_VERSION, false, CFG.footerSize, CFG.muted)
    local label = string.format("Page %d / %d", index, pageCount)
    pdf:text(footerPage, right - PDF.textWidth(label, false, CFG.footerSize), footerY,
      label, false, CFG.footerSize, CFG.muted)
  end

  return pdf
end

--=============================================================================
-- DIALOGS
--=============================================================================

local function displayIndex(displayHandle)
  local ok, index = pcall(function() return displayHandle.index end)
  if ok and index ~= nil then return index end
  ok, index = pcall(function() return GetFocusDisplay().index end)
  if ok and index ~= nil then return index end
  return 1
end

local function say(message)
  pcall(function() Printf("%s: %s", PLUGIN_NAME, message) end)
end

local function complain(message)
  pcall(function() ErrEcho("%s: %s", PLUGIN_NAME, message) end)
end
local function showError(display, message)
  complain(message)
  pcall(function()
    MessageBox({
      title    = PLUGIN_NAME .. " - Error",
      message  = message,
      display  = display,
      commands = { { value = 1, name = "Ok" } },
    })
  end)
end
--=============================================================================
-- TARGET DIALOG
--
-- Sequences are chosen by typing their number. Earlier versions offered a
-- list, but MessageBox has no scrollable widget: type 0 is a swipe button and
-- type 1 a radio group that draws every value at once, so a whole pool either
-- overflowed the popup or had to be paged eight at a time. Typing the number
-- is both simpler and faster when you already know it.
--=============================================================================

--- A human list of the data pools that exist, for prompts and errors.
local function describePools(pools)
  local parts = {}
  for _, pool in ipairs(pools) do
    local label = pool.no
    if pool.name ~= "" then label = label .. " - " .. pool.name end
    parts[#parts + 1] = label
  end
  return table.concat(parts, ",  ")
end

--- Resolve a typed data pool number, forgivingly.
local function findDataPool(pools, typed)
  for _, candidate in ipairs(pools) do
    if candidate.no == typed or tonumber(candidate.no) == tonumber(typed) then
      return candidate
    end
  end

  -- Data pools run 1..N in order, so position still finds the right one if the
  -- No property reads oddly on some build.
  local position = tonumber(typed)
  if position and pools[position] then return pools[position] end

  -- Last resort, mirroring the fallback findSequenceByNumber already has.
  local ok, handle = pcall(function()
    return ShowData().DataPools[tonumber(typed)]
  end)
  if ok and handle ~= nil then
    local no, name = identify(handle)
    return { no = no, name = name, handle = handle, active = false }
  end

  return nil
end

--- Step 1: which data pool, and which sequence.
--- Returns pool, sequence, errorMessage. All nil means the user cancelled.
local function askForTarget(display, pools, activePool, lastPool, lastSequence, lockedPool)
  local poolDefault = lastPool
    or (activePool and activePool.no)
    or (pools[1] and pools[1].no)
    or ""

  local inputs = {}
  local message

  if lockedPool ~= nil then
    -- CFG.dataPool is set, so there is nothing to ask about.
    local label = lockedPool.no
    if lockedPool.name ~= "" then label = label .. " - " .. lockedPool.name end
    message = "Exporting from data pool " .. label .. "."
  else
    message = "Enter the data pool and the sequence to export.\n\nData pools: "
      .. describePools(pools)
    inputs[#inputs + 1] =
      { name = "Data pool", value = poolDefault, vkPlugin = "TextInputNumOnly" }
  end

  inputs[#inputs + 1] =
    { name = "Sequence", value = lastSequence or "", vkPlugin = "TextInputNumOnly" }

  local result = MessageBox({
    title    = PLUGIN_NAME,
    message  = message,
    display  = display,
    inputs   = inputs,
    commands = {
      { value = 1, name = "Next" },
      { value = 2, name = "Cancel" },
    },
  })

  if not result or result.result ~= 1 then return nil, nil, nil end

  local function field(name)
    local value = result.inputs and result.inputs[name]
    if value == nil then return "" end
    return tostring(value):match("^%s*(.-)%s*$")
  end

  local poolNumber     = field("Data pool")
  local sequenceNumber = field("Sequence")

  -- An empty data pool field means whichever pool is currently active.
  local pool = lockedPool or activePool
  if lockedPool == nil and poolNumber ~= "" then
    pool = findDataPool(pools, poolNumber)
    if pool == nil then
      return nil, nil, string.format(
        "There is no data pool %s in this show.\n\nData pools: %s",
        poolNumber, describePools(pools)),
        poolNumber, sequenceNumber
    end
  end

  if pool == nil then
    return nil, nil, "Could not determine which data pool to read.",
      poolNumber, sequenceNumber
  end

  if sequenceNumber == "" then
    return nil, nil, "Enter the number of the sequence to export.",
      poolNumber, sequenceNumber
  end

  local sequences = listSequences(pool.handle)
  local sequence  = findSequenceByNumber(sequences, sequenceNumber, pool.handle)
  if sequence == nil then
    local where = pool.no ~= "" and ("data pool " .. pool.no) or "this data pool"
    return nil, nil, string.format("There is no sequence %s in %s.", sequenceNumber, where),
      poolNumber, sequenceNumber
  end

  return pool, sequence, nil, poolNumber, sequenceNumber
end

--- Step 3: confirm by name. Returns "continue", "back" or "cancel".
local function confirmSequence(display, sequence, cueCount, pool)
  local name = sequence.name ~= "" and ('"' .. sequence.name .. '"') or "(unnamed)"

  local where = ""
  if pool and pool.no ~= "" then
    where = "\nData pool " .. pool.no
    if pool.name ~= "" then where = where .. " - " .. pool.name end
  end

  local result = MessageBox({
    title   = PLUGIN_NAME .. " - Confirm",
    message = string.format(
      "Sequence %s: %s%s\n\n%d %s will be exported.\n\nIs this the right sequence?",
      sequence.no, name, where, cueCount, cueCount == 1 and "cue" or "cues"),
    display  = display,
    commands = {
      { value = 1, name = "Continue" },
      { value = 2, name = "Back" },
      { value = 3, name = "Cancel" },
    },
  })

  if not result then return "cancel" end
  if result.result == 2 then return "back" end
  if result.result == 1 then return "continue" end
  return "cancel"
end

--- Step 3: choose a drive and filename.
--- Returns action, path, where action is "export", "back" or "cancel".
local function askForDestination(display, drives, defaultFileName)
  local values = {}
  for index, drive in ipairs(drives) do
    local label = drive.name
    if label == "" then label = drive.path end
    if drive.driveType ~= "" then label = label .. " (" .. drive.driveType .. ")" end
    values[label] = index
  end

  local result = MessageBox({
    title   = PLUGIN_NAME .. " - Destination",
    message = "Choose a storage device and file name.",
    display = display,
    selectors = {
      {
        name          = "Drive",
        selectedValue = 1,
        type          = 1,
        values        = values,
      },
    },
    inputs = {
      { name = "File name", value = defaultFileName },
    },
    commands = {
      { value = 1, name = "Export" },
      { value = 2, name = "Back" },
      { value = 3, name = "Cancel" },
    },
  })

  if not result then return "cancel" end
  if result.result == 2 then return "back" end
  if result.result ~= 1 then return "cancel" end

  local index = tonumber(result.selectors and result.selectors["Drive"]) or 1
  local drive = drives[index] or drives[1]

  local fileName = result.inputs and result.inputs["File name"] or defaultFileName
  fileName = tostring(fileName):match("^%s*(.-)%s*$")
  if fileName == "" then fileName = defaultFileName end
  if not fileName:lower():match("%.pdf$") then fileName = fileName .. ".pdf" end

  local base = drive.path:gsub("[/\\]+$", "")
  return "export", base .. "/" .. fileName
end

--=============================================================================
-- MAIN
--=============================================================================

--- Strip characters that FAT/exFAT volumes reject in file names.
local function sanitizeFileName(name)
  local safe = (name or ""):gsub('[\\/:%*%?"<>|]', "-"):gsub("%s+", " ")
  safe = safe:match("^%s*(.-)%s*$")
  if safe == "" then safe = "Sequence" end
  return safe
end

local function defaultFileNameFor(sequence)
  local base = sanitizeFileName(
    sequence.name ~= "" and sequence.name or ("Sequence " .. sequence.no))
  local ok, stamp = pcall(function() return os.date("%Y-%m-%d") end)
  if ok and type(stamp) == "string" then
    base = base .. "_" .. stamp
  end
  return base .. ".pdf"
end

local function Main(displayHandle, argument)
  local display = displayIndex(displayHandle)

  local pools = listDataPools()
  trace("display index %s, %d data pool(s)", tostring(display), #pools)

  local activePool
  for _, candidate in ipairs(pools) do
    if candidate.active then activePool = candidate end
  end

  if #pools == 0 then
    -- ShowData was unreadable; fall back to whichever pool is selected.
    complain("Could not read the data pool list; using the selected pool.")
    pools = { { no = "", name = "", handle = nil, active = true } }
    activePool = pools[1]
  end

  -- CFG.dataPool locks the export to one pool and drops the field entirely.
  local lockedPool
  if CFG.dataPool ~= nil then
    lockedPool = findDataPool(pools, tostring(CFG.dataPool))
    if lockedPool == nil then
      showError(display, string.format(
        "CFG.dataPool is set to %s, but there is no such data pool.\n\nData pools: %s",
        tostring(CFG.dataPool), describePools(pools)))
      return
    end
    trace("locked to data pool %s by CFG.dataPool", lockedPool.no)
  end

  local step = "target"
  local pool, sequence, cues, appearances
  local lastPool, lastSequence

  while true do
    if step == "target" then
      local chosenPool, chosenSequence, err, typedPool, typedSequence =
        askForTarget(display, pools, activePool, lastPool, lastSequence, lockedPool)

      -- Keep whatever they typed so a correction starts from it, not blank.
      lastPool, lastSequence = typedPool or lastPool, typedSequence or lastSequence

      if err then
        showError(display, err)
      elseif chosenSequence == nil then
        say("Export cancelled.")
        return
      else
        pool, sequence = chosenPool, chosenSequence
        trace("reading sequence %s from data pool %s", sequence.no, pool.no)

        appearances = buildAppearanceIndex(pool.handle)
        trace("appearance index built")

        cues = collectCues(sequence.handle, appearances)
        if #cues == 0 then
          showError(display, string.format(
            "Sequence %s has no cues to export.", sequence.no))
        else
          step = "confirm"
        end
      end

    elseif step == "confirm" then
      local answer = confirmSequence(display, sequence, #cues, pool)
      if answer == "back" then
        step = "target"
      elseif answer == "continue" then
        step = "destination"
      else
        say("Export cancelled.")
        return
      end

    elseif step == "destination" then
      local drives = listDrives()
      if #drives == 0 then
        showError(display,
          "No storage devices found. Plug in a USB drive and try again.")
        step = "confirm"
      else
        local action, path = askForDestination(display, drives, defaultFileNameFor(sequence))
        if action == "back" then
          step = "confirm"
        elseif action ~= "export" then
          say("Export cancelled.")
          return
        else
          local showfile = ""
          local ok, value = pcall(function() return Root().manetsocket.showfile end)
          if ok and value then showfile = tostring(value) end

          local title = sequence.name ~= "" and sequence.name
            or ("Sequence " .. sequence.no)

          local pdf = renderDocument(title, sequence.no, cues, showfile)
          local written, err = pdf:writeFile(path, title)

          if written then
            say(string.format("Exported %d cues to %s", #cues, path))

            -- If the show handed over no colour at all, say why in a file
            -- next to the PDF rather than leaving it a mystery.
            local anyFromShow = false
            for _, cue in ipairs(cues) do
              if cue.fromShow then anyFromShow = true break end
            end

            local reportPath
            if not anyFromShow then
              reportPath = writeAppearanceReport(path,
                buildAppearanceReport(pool.handle, sequence.handle, appearances))
              if reportPath then
                complain("No Appearance colours were readable; wrote " .. reportPath)
              end
            end

            local message = string.format("Exported %d %s to:\n\n%s",
              #cues, #cues == 1 and "cue" or "cues", path)
            if reportPath then
              message = message ..
                "\n\nNo Appearance colours could be read from the show." ..
                "\nA diagnostic was written next to it:\n\n" .. reportPath
            end

            pcall(function()
              MessageBox({
                title    = PLUGIN_NAME .. " - Done",
                message  = message,
                display  = display,
                commands = { { value = 1, name = "Ok" } },
              })
            end)
          else
            showError(display, "Could not write the PDF:\n\n" .. tostring(err))
          end
          return
        end
      end
    end
  end
end

-- Exposed for the local test harness in dev/; MA3 itself only uses the return.
if _G.SEQUENCE_EXPORT_TESTING then
  _G.SequenceExportInternals = {
    PDF              = PDF,
    CFG              = CFG,
    toWinAnsi        = toWinAnsi,
    escapeText       = escapeText,
    tint             = tint,
    contrastingInk   = contrastingInk,
    sanitizeFileName = sanitizeFileName,
    listDataPools    = listDataPools,
    listSequences    = listSequences,
    findSequenceByNumber = findSequenceByNumber,
    buildAppearanceIndex = buildAppearanceIndex,
    cueNumber        = cueNumber,
    numberToken      = numberToken,
    stripCueLabel    = stripCueLabel,
    colorFromAppearance = colorFromAppearance,
    lookupAppearance = lookupAppearance,
    findAppearanceCollection = findAppearanceCollection,
    manualSection    = manualSection,
    buildAppearanceReport = buildAppearanceReport,
    findDataPool     = findDataPool,
    describePools    = describePools,
    isSpecialCue     = isSpecialCue,
    trimZeros        = trimZeros,
    askForTarget     = askForTarget,
    collectCues      = collectCues,
    listDrives       = listDrives,
    renderDocument   = renderDocument,
  }
end

return Main
