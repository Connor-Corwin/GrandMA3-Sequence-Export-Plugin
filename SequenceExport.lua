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
}

local PLUGIN_NAME    = "Sequence Export"
local PLUGIN_VERSION = "1.1.0"

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

--- Number and name for a pool object, tolerating an unreadable No.
local function identify(handle)
  local no = clean(getProp(handle, "No"))
  if no == "" then
    local n = getNumber(handle, "No")
    no = n and tostring(math.floor(n)) or "?"
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

--- Read an Appearance handle into a normalized color, or nil.
local function readAppearance(cueHandle)
  local ok, appearance = pcall(function() return cueHandle.appearance end)
  if not ok or appearance == nil then return nil end

  local r = getNumber(appearance, "BackR")
  local g = getNumber(appearance, "BackG")
  local b = getNumber(appearance, "BackB")
  if r == nil and g == nil and b == nil then return nil end

  r, g, b = r or 0, g or 0, b or 0

  -- BackR/G/B are 0-255. A fully transparent appearance carries no color.
  local alpha = getNumber(appearance, "BackAlpha")
  if alpha ~= nil and alpha <= 0 then return nil end

  local name = clean(getProp(appearance, "Name"))
  local key  = name ~= "" and name or string.format("%d,%d,%d", r, g, b)

  return {
    r    = r / 255,
    g    = g / 255,
    b    = b / 255,
    name = name,
    key  = key,
  }
end

--- Every cue of a sequence, in sheet order.
local function collectCues(sequenceHandle)
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

    local number = clean(getProp(cueHandle, "No"))
    if number == "" then
      local n = getNumber(cueHandle, "No")
      number = n and tostring(n) or ""
    end

    cues[#cues + 1] = {
      no         = number,
      name       = clean(getProp(cueHandle, "Name")),
      note       = clean(getProp(cueHandle, "Note")),
      fade       = clean(getProp(part, "CueFade")),
      delay      = clean(getProp(part, "CueDelay")),
      appearance = readAppearance(cueHandle),
    }
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
local function renderDocument(sequenceName, sequenceNumber, cues, showfile, poolLabel)
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
      if poolLabel and poolLabel ~= "" then meta[#meta + 1] = poolLabel end
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
-- LIST PICKER
--
-- MessageBox has no dropdown. Its `selectors` only offer type 0 (a swipe
-- button showing one value at a time) and type 1 (a radio group that draws
-- every value at once) -- handing a radio group a whole sequence pool
-- overflows the popup and renders as a black block.
--
-- PopupInput is the console's own scrollable list picker:
--   PopupInput(title, uiCaller, items [, selectedValue [, x, y]]) -> string
-- It takes the display *handle* as its caller, not the display index that
-- MessageBox wants, and returns nil when dismissed.
--=============================================================================

local LIST_PAGE_SIZE = 8   -- radio entries per page in the fallback picker

--- Fallback picker for builds without PopupInput: a paged radio group, kept
--- short enough to actually render.
local function pickFromListPaged(display, title, entries, labels)
  local page = 1
  local pageCount = math.max(1, math.ceil(#entries / LIST_PAGE_SIZE))

  while true do
    local first = (page - 1) * LIST_PAGE_SIZE + 1
    local last  = math.min(first + LIST_PAGE_SIZE - 1, #entries)

    local values = {}
    for index = first, last do
      values[labels[index]] = index
    end

    local commands = { { value = 1, name = "Select" } }
    if pageCount > 1 then
      commands[#commands + 1] = { value = 2, name = "Previous" }
      commands[#commands + 1] = { value = 3, name = "Next" }
    end
    commands[#commands + 1] = { value = 4, name = "Cancel" }

    local result = MessageBox({
      title   = title,
      message = pageCount > 1
        and string.format("Page %d of %d", page, pageCount)
        or "",
      display = display,
      selectors = {
        { name = "Item", selectedValue = first, type = 1, values = values },
      },
      commands = commands,
    })

    if not result then return nil end

    if result.result == 2 then
      page = page > 1 and page - 1 or pageCount
    elseif result.result == 3 then
      page = page < pageCount and page + 1 or 1
    elseif result.result == 1 then
      local index = tonumber(result.selectors and result.selectors["Item"])
      if index and entries[index] then return entries[index] end
      return nil
    else
      return nil
    end
  end
end

--- Present a scrollable list and return the chosen entry, or nil if dismissed.
--- `entries` is an array of { label = string, value = anything }.
local function pickFromList(caller, display, title, entries, selectedLabel)
  if #entries == 0 then return nil end

  local labels = {}
  for index, entry in ipairs(entries) do labels[index] = entry.label end

  if _G.PopupInput ~= nil then
    -- Some builds are reported to return the index alongside the string, so
    -- accept either and resolve it back to an entry.
    local ok, first, second = pcall(function()
      return PopupInput(title, caller, labels, selectedLabel)
    end)

    if ok then
      for _, returned in ipairs({ first, second }) do
        if type(returned) == "number" and entries[returned] then
          return entries[returned]
        end
        if type(returned) == "string" then
          for index, label in ipairs(labels) do
            if label == returned then return entries[index] end
          end
        end
      end
      -- PopupInput ran, so trust it: nothing matched means nothing was chosen.
      -- Falling back here would pop a second, different picker at the user.
      return nil
    end
  end

  -- Only reached when PopupInput is missing or raised an error.
  return pickFromListPaged(display, title, entries, labels)
end

local TYPE_A_NUMBER = "Enter a number..."

--- Ask for a sequence number in its own small dialog.
local function askForNumber(display, previousNumber)
  local result = MessageBox({
    title   = PLUGIN_NAME .. " - Sequence number",
    message = "Type the number of the sequence to export.",
    display = display,
    inputs  = {
      { name = "Sequence number", value = previousNumber or "", vkPlugin = "TextInputNumOnly" },
    },
    commands = {
      { value = 1, name = "Ok" },
      { value = 2, name = "Cancel" },
    },
  })

  if not result or result.result ~= 1 then return nil end

  local typed = result.inputs and result.inputs["Sequence number"]
  if typed == nil then return nil end
  typed = tostring(typed):match("^%s*(.-)%s*$")
  if typed == "" then return nil end
  return typed
end

--- Step 1: choose the data pool. Returns an entry, or nil when dismissed.
local function askForDataPool(caller, display, pools)
  local entries, selectedLabel = {}, nil
  for _, pool in ipairs(pools) do
    local label = pool.no
    if pool.name ~= "" then label = label .. " - " .. pool.name end
    entries[#entries + 1] = { label = label, value = pool }
    if pool.active then selectedLabel = label end
  end

  local chosen = pickFromList(caller, display,
    PLUGIN_NAME .. " - Select data pool", entries, selectedLabel)
  return chosen and chosen.value or nil
end

--- Step 2: choose a sequence from a scrollable list, or type its number.
--- Returns sequence, errorMessage. Both nil means the user backed out.
local function askForSequence(caller, display, sequences, dataPoolHandle, previousNumber)
  local entries = { { label = TYPE_A_NUMBER, value = TYPE_A_NUMBER } }
  local selectedLabel

  for _, sequence in ipairs(sequences) do
    local label = sequence.no
    if sequence.name ~= "" then label = label .. " - " .. sequence.name end
    entries[#entries + 1] = { label = label, value = sequence }
    if previousNumber ~= nil and sequence.no == previousNumber then
      selectedLabel = label
    end
  end

  local chosen = pickFromList(caller, display,
    PLUGIN_NAME .. " - Select sequence", entries, selectedLabel)
  if chosen == nil then return nil, nil end

  if chosen.value == TYPE_A_NUMBER then
    local typed = askForNumber(display, previousNumber)
    if typed == nil then return nil, nil end

    local match = findSequenceByNumber(sequences, typed, dataPoolHandle)
    if not match then
      return nil, string.format("No sequence %s exists in this data pool.", typed)
    end
    return match
  end

  return chosen.value
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
  -- PopupInput wants the display handle itself; MessageBox wants its index.
  local caller  = displayHandle
  local display = displayIndex(displayHandle)

  local pools = listDataPools()

  -- With a single pool there is nothing to choose, so skip that step entirely.
  local pool = (#pools == 1) and pools[1] or nil
  if #pools == 0 then
    -- ShowData was unreadable; fall back to whichever pool is selected.
    pool = { no = "", name = "", handle = nil }
  end

  local step = (pool == nil) and "pool" or "sequence"
  local sequence, sequences, cues, typedNumber

  while true do
    if step == "pool" then
      local chosen = askForDataPool(caller, display, pools)
      if chosen == nil then
        say("Export cancelled.")
        return
      end
      pool = chosen
      sequences = nil
      step = "sequence"

    elseif step == "sequence" then
      if sequences == nil then
        sequences = listSequences(pool.handle)
      end

      if #sequences == 0 then
        local where = pool.name ~= "" and ("data pool " .. pool.no) or "this data pool"
        showError(display, "No sequences found in " .. where .. ".")
        if #pools > 1 then
          step = "pool"
        else
          return
        end
      else
        local chosen, err = askForSequence(caller, display, sequences, pool.handle, typedNumber)
        if err then
          showError(display, err)
        elseif chosen == nil then
          if #pools > 1 then
            step = "pool"
          else
            say("Export cancelled.")
            return
          end
        else
          sequence = chosen
          typedNumber = chosen.no
          cues = collectCues(sequence.handle)
          if #cues == 0 then
            showError(display, string.format(
              "Sequence %s has no cues to export.", sequence.no))
          else
            step = "confirm"
          end
        end
      end

    elseif step == "confirm" then
      local answer = confirmSequence(display, sequence, #cues, pool)
      if answer == "back" then
        step = "sequence"
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

          local poolLabel = ""
          if pool.no ~= "" then
            poolLabel = "Data pool " .. pool.no
            if pool.name ~= "" then poolLabel = poolLabel .. " - " .. pool.name end
          end

          local pdf = renderDocument(title, sequence.no, cues, showfile, poolLabel)
          local written, err = pdf:writeFile(path, title)

          if written then
            say(string.format("Exported %d cues to %s", #cues, path))
            pcall(function()
              MessageBox({
                title   = PLUGIN_NAME .. " - Done",
                message = string.format(
                  "Exported %d %s to:\n\n%s",
                  #cues, #cues == 1 and "cue" or "cues", path),
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
    pickFromList     = pickFromList,
    collectCues      = collectCues,
    listDrives       = listDrives,
    renderDocument   = renderDocument,
  }
end

return Main
