--
-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\",
  [ "\"" ] = "\"",
  [ "\b" ] = "b",
  [ "\f" ] = "f",
  [ "\n" ] = "n",
  [ "\r" ] = "r",
  [ "\t" ] = "t",
}

local escape_char_map_inv = { [ "/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end


local function encode_nil(val)
  return "null"
end


local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then error("circular reference") end

  stack[val] = true

  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
        error("invalid table: mixed or invalid key types")
      end
      n = n + 1
    end
    if n ~= #val then
      error("invalid table: sparse array")
    end
    -- Encode
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"

  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid table: mixed or invalid key types")
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("unexpected number value '" .. tostring(val) .. "'")
  end
  return string.format("%.14g", val)
end


local type_func_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]
  if f then
    return f(val, stack)
  end
  error("unexpected type '" .. t .. "'")
end


function json.encode(val)
  return ( encode(val) )
end


-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(1, 4),  16 )
  local n2 = tonumber( s:sub(7, 10), 16 )
   -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end


local function parse_string(str, i)
  local res = ""
  local j = i + 1
  local k = j

  while j <= #str do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")

    elseif x == 92 then -- `\`: Escape
      res = res .. str:sub(k, j - 1)
      j = j + 1
      local c = str:sub(j, j)
      if c == "u" then
        local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                 or str:match("^%x%x%x%x", j + 1)
                 or decode_error(str, j - 1, "invalid unicode escape in string")
        res = res .. parse_unicode_escape(hex)
        j = j + #hex
      else
        if not escape_chars[c] then
          decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
        end
        res = res .. escape_char_map_inv[c]
      end
      k = j + 1

    elseif x == 34 then -- `"`: End of string
      res = res .. str:sub(k, j - 1)
      return res, j + 1
    end

    j = j + 1
  end

  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]
  if f then
    return f(str, idx)
  end
  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json.decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end
  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end


-- Sonarr Status Colors
local COLOR_GREEN = "39,194,76"   -- Has File
local COLOR_RED   = "240,50,50"   -- Missing & Aired
local COLOR_BLUE  = "0,180,255"   -- Unaired

function Initialize()
    local now = os.time()
    local future = now + (45 * 24 * 60 * 60)
    
    -- Generate API URL
    local offset = (tonumber(SKIN:GetVariable('ShowYesterday')) == 0) and 43200 or 86400
    local startDate = os.date("!%Y-%m-%dT%H:%M:%SZ", now - offset)
    local endDate = os.date("!%Y-%m-%dT%H:%M:%SZ", future)
    
    local url = SKIN:GetVariable('SonarrURL') .. '/api/v3/calendar?start=' .. startDate .. '&end=' .. endDate .. '&includeSeries=true&includeEpisodeFile=false'
    
    SKIN:Bang('!SetVariable', 'CurrentCalendarURL', url)
    SKIN:Bang('!CommandMeasure', 'MeasureSonarr', 'Update')
end

function UpdateFromLua()
    local rawData = SKIN:GetMeasure('MeasureSonarr'):GetStringValue()
    
    if rawData == "" then return end

    local data, err = json.decode(rawData)
    if err or not data then
        SKIN:Bang('!SetOption', 'MeterError', 'Text', 'JSON Error')
        SKIN:Bang('!ShowMeter', 'MeterError')
        return 
    end
    
    -- Clear Loading/Error States
    SKIN:Bang('!HideMeter', 'MeterLoading')
    SKIN:Bang('!HideMeter', 'MeterError')

    -- Sort by Date
    table.sort(data, function(a,b) return a.airDateUtc < b.airDateUtc end)

    -- Grouping Prep
    local groups = {}
    local groupsOrder = {}
    local nowTable = os.date("*t")
    local todayVal = os.time({year=nowTable.year, month=nowTable.month, day=nowTable.day})

    -- Current UTC Time (for status calculation)
    local currentUtcTable = os.date("!*t")
    local nowUtcTimestamp = os.time(currentUtcTable)

    for _, ep in ipairs(data) do
        local y, m, d, h, min, s = ep.airDateUtc:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")
        if y then
            -- Create Timestamp for Grouping (Local Time)
            local utcTime = os.time({year=y, month=m, day=d, hour=h, min=min, sec=s})
            local localDate = os.date("*t", utcTime + os.difftime(os.time(), os.time(os.date("!*t"))))
            local dateKey = string.format("%04d-%02d-%02d", localDate.year, localDate.month, localDate.day)
            
            if not groups[dateKey] then
                groups[dateKey] = { dateObj = localDate, items = {} }
                table.insert(groupsOrder, dateKey)
            end
            
            -- Format Display Time
            local hour12 = localDate.hour % 12
            if hour12 == 0 then hour12 = 12 end
            local ampm = (localDate.hour >= 12) and "pm" or "am"
            ep.displayTime = string.format("%d:%02d %s", hour12, localDate.min, ampm)
            
            -- Calculate Status Color Logic
            -- 1. Create timestamp for the Episode Air Date (in UTC context)
            local epUtcTimestamp = os.time({year=y, month=m, day=d, hour=h, min=min, sec=s})
            -- 2. Calculate End Time (Start + Runtime in minutes)
            local runtimeSec = (ep.runtime or 0) * 60
            local epEndTimestamp = epUtcTimestamp + runtimeSec

            if ep.hasFile then
                ep.statusColor = COLOR_GREEN
            elseif nowUtcTimestamp > epEndTimestamp then
                ep.statusColor = COLOR_RED
            else
                ep.statusColor = COLOR_BLUE
            end

            table.insert(groups[dateKey].items, ep)
        end
    end

    -- --- RENDERING ---
    local maxGen = tonumber(SKIN:GetVariable('MaxGeneratedDays')) or 14
    local showLimit = tonumber(SKIN:GetVariable('MaxDaysToShow')) or 3
    local maxItems = 20

    -- Reset Meters
    for d=1, maxGen do
        SKIN:Bang('!HideMeterGroup', 'Day'..d)
    end

    local showYesterday = tonumber(SKIN:GetVariable('ShowYesterday')) or 1
    local currentY = 62
    local daysRendered = 0
    local skinWidth = tonumber(SKIN:GetVariable('Width')) or 350
    local textW = skinWidth - 100

    for _, dateKey in ipairs(groupsOrder) do
        local gData = groups[dateKey]
        local dObj = gData.dateObj
        local dayTimeVal = os.time({year=dObj.year, month=dObj.month, day=dObj.day})
        local diffDays = math.floor((dayTimeVal - todayVal) / 86400 + 0.5)

        if not (showYesterday == 0 and diffDays < 0) then
            if daysRendered >= showLimit then break end
            
            daysRendered = daysRendered + 1
            if daysRendered > maxGen then break end
            
            local headerText = os.date("%a %d %b", dayTimeVal)
            if diffDays == -1 then headerText = "Yesterday"
            elseif diffDays == 0 then headerText = "Today"
            elseif diffDays == 1 then headerText = "Tomorrow"
            end
        
        local headerMeter = 'MeterDay'..daysRendered..'Header'
        SKIN:Bang('!SetOption', headerMeter, 'Text', headerText)
        SKIN:Bang('!SetOption', headerMeter, 'Y', currentY)
        SKIN:Bang('!ShowMeter', headerMeter)
        
        currentY = currentY + 25 

        for i, ep in ipairs(gData.items) do
            if i > maxItems then
                local ovMeter = 'MeterDay'..daysRendered..'Overflow'
                SKIN:Bang('!SetOption', ovMeter, 'Text', '... and ' .. (#gData.items - maxItems) .. ' more')
                SKIN:Bang('!SetOption', ovMeter, 'Y', currentY)
                SKIN:Bang('!ShowMeter', ovMeter)
                currentY = currentY + 20
                break
            end
            
            local prefix = 'Day'..daysRendered..'Item'..i
            
            local sTitle = (ep.series and ep.series.title) or "Series ID: " .. (ep.seriesId or "?")
            local epInfo = string.format("S%02dE%02d - %s", ep.seasonNumber, ep.episodeNumber, ep.title or "?")
            
            SKIN:Bang('!SetOption', prefix..'Title', 'Text', sTitle)
            SKIN:Bang('!SetOption', prefix..'Title', 'W', textW)
            SKIN:Bang('!SetOption', prefix..'Title', 'ClipString', '1')
            SKIN:Bang('!SetOption', prefix..'Episode', 'Text', epInfo)
            SKIN:Bang('!SetOption', prefix..'Episode', 'W', textW)
            SKIN:Bang('!SetOption', prefix..'Episode', 'ClipString', '1')
            SKIN:Bang('!SetOption', prefix..'Time', 'Text', ep.displayTime)
            
            -- Apply Status Color
            local shape = "Ellipse 3,3,3 | Fill Color " .. ep.statusColor .. " | StrokeWidth 0"
            SKIN:Bang('!SetOption', prefix..'Dot', 'Shape', shape)

            -- Positioning (Preserving fixed offsets)
            SKIN:Bang('!SetOption', prefix..'Hitbox', 'Y', currentY)
            SKIN:Bang('!SetOption', prefix..'Highlight', 'Y', currentY)
            SKIN:Bang('!SetOption', prefix..'Dot', 'Y', (currentY + 10))
            SKIN:Bang('!SetOption', prefix..'Title', 'Y', (currentY + 2))
            SKIN:Bang('!SetOption', prefix..'Episode', 'Y', (currentY + 17))
            SKIN:Bang('!SetOption', prefix..'Time', 'Y', (currentY + 9))

            -- Update and Show
            local metersToUpdate = {
                prefix..'Hitbox', prefix..'Highlight', prefix..'Dot',
                prefix..'Title', prefix..'Episode', prefix..'Time'
            }

            for _, m in ipairs(metersToUpdate) do
                SKIN:Bang('!ShowMeter', m)
                SKIN:Bang('!UpdateMeter', m)
            end

            -- Tooltip
            local tip = sTitle .. "#CRLF#" .. epInfo
            if ep.overview then tip = tip .. "#CRLF##CRLF#" .. ep.overview end
            SKIN:Bang('!SetOption', prefix..'Hitbox', 'ToolTipText', tip)
            
            SKIN:Bang('!UpdateMeterGroup', 'Day'..daysRendered..'Item'..i)
            
            currentY = currentY + 40 -- Row Height
        end
        
        currentY = currentY + 10 -- Gap between days
        end -- End of skip check
    end

    SKIN:Bang('!SetVariable', 'BgHeight', currentY + 10)
    SKIN:Bang('!UpdateMeter', 'MeterBackground')
    SKIN:Bang('!Redraw')
end