-- Sonarr Status Colors
local COLOR_GREEN = "39,194,76"   -- Has File
local COLOR_RED   = "240,50,50"   -- Missing & Aired
local COLOR_BLUE  = "0,180,255"   -- Unaired

function Initialize()
    local now = os.time()
    local future = now + (45 * 24 * 60 * 60)
    
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
        end
    end

    SKIN:Bang('!SetVariable', 'BgHeight', currentY + 10)
    SKIN:Bang('!UpdateMeter', 'MeterBackground')
    SKIN:Bang('!Redraw')
end