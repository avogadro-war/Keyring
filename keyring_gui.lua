-- Keyring GUI Module
-- Handles all ImGui rendering logic for the keyring addon

local imgui = require('imgui')
local chat = require('chat')

local gui = {}

-- GUI state
local showGui = { false }

-- Dynamic window sizing constants
local HEADER_HEIGHT = 30
local ITEM_HEIGHT = 22
local SPACING_HEIGHT = 2
local PADDING = 35
local MIN_HEIGHT = 100
local MIN_WIDTH = 450
local MAX_WIDTH = 1200
local BASE_WIDTH = 500

function gui.is_visible()
    return showGui[1]
end

function gui.toggle()
    showGui[1] = not showGui[1]
    return showGui[1]
end

function gui.set_visible(visible)
    showGui[1] = visible
end

-- Calculate dynamic window dimensions based on content
local function calculate_window_dimensions(keyItemStatuses)
    local itemCount = #keyItemStatuses
    
    -- Calculate height
    local spacingCount = math.max(0, itemCount - 1)
    local contentHeight = HEADER_HEIGHT + (itemCount * ITEM_HEIGHT) + (spacingCount * SPACING_HEIGHT)
    local requiredHeight = math.max(contentHeight + PADDING, MIN_HEIGHT)
    
    -- Calculate width based on longest item name
    local maxNameLength = 0
    for _, item in ipairs(keyItemStatuses) do
        if item.name and #item.name > maxNameLength then
            maxNameLength = #item.name
        end
    end
    
    local dynamicWidth = math.min(math.max(BASE_WIDTH + (maxNameLength * 6), MIN_WIDTH), MAX_WIDTH)
    
    return dynamicWidth, requiredHeight
end

-- Center text within current column
local function center_text(text)
    local col_start = imgui.GetColumnOffset()
    local col_width = imgui.GetColumnWidth()
    local text_width = imgui.CalcTextSize(text)
    local pos_x = col_start + (col_width - text_width) / 2
    imgui.SetCursorPosX(pos_x)
    imgui.Text(text)
end

-- Render column headers
local function render_headers(total_width)
    imgui.Columns(3, 'cooldownColumns', true)
    
    -- Responsive column widths with minimum sizes
    local minNameWidth = 180
    local minStatusWidth = 70
    local minTimeWidth = 140
    
    local nameWidth = math.max(total_width * 0.50, minNameWidth)
    local statusWidth = math.max(total_width * 0.20, minStatusWidth)
    local timeWidth = math.max(total_width * 0.30, minTimeWidth)
    
    imgui.SetColumnWidth(0, nameWidth)      -- Key Item
    imgui.SetColumnWidth(1, statusWidth)    -- Have?
    imgui.SetColumnWidth(2, timeWidth)      -- Time Remaining

    -- Headers
    center_text('Key Item')
    imgui.NextColumn()
    center_text('Have?')
    imgui.NextColumn()
    center_text('Time Remaining')
    imgui.NextColumn()
    imgui.Separator()
end

-- Render time remaining with special canteen handling
local function render_time_remaining(item, hasItem, storage_canteens, packet_tracker)
    local displayText
    local textColor = {1, 0.2, 0.2, 1} -- red default
    local show_canteen_count = (item.id == 3137)
    
    if show_canteen_count then
        -- Special handling for canteen - show generation time instead of cooldown
        if storage_canteens >= 3 then
            -- Storage is full - no more canteens will be generated
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = 'Storage Full'
        else
            -- Check generation time
            local generationRemaining = packet_tracker.get_canteen_generation_remaining()
            if generationRemaining == nil then
                textColor = {0.7, 0.7, 0.7, 1} -- gray
                displayText = 'Unknown'
            elseif generationRemaining <= 0 then
                textColor = {0, 1, 0, 1} -- green
                displayText = 'Ready'
            else
                local rh = math.floor(generationRemaining / 3600)
                local rm = math.floor((generationRemaining % 3600) / 60)
                local rs = generationRemaining % 60
                displayText = string.format('%02dh:%02dm:%02ds', rh, rm, rs)
            end
        end
    else
        -- Regular key item cooldown logic
        local timestamp = item.timestamp or 0
        
        if timestamp == 0 or item.remaining == nil then
            -- No timestamp recorded yet or no remaining time calculated
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = 'Unknown'
        elseif item.remaining <= 0 then
            textColor = {0, 1, 0, 1} -- green
            displayText = 'Available'
        elseif item.remaining > 0 then
            local rh = math.floor(item.remaining / 3600)
            local rm = math.floor((item.remaining % 3600) / 60)
            local rs = item.remaining % 60
            displayText = string.format('%02dh:%02dm:%02ds', rh, rm, rs)
        else
            -- Fallback for any calculation issues
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = 'Unknown'
        end
    end

    -- Calculate positioning for centered text
    local col_start = imgui.GetColumnOffset()
    local col_width = imgui.GetColumnWidth()
    
    if showCanteenCount then
        -- For canteen, render main text and count separately
        local mainTextWidth = imgui.CalcTextSize(displayText)
        local canteenText = string.format(' (%d/3)', storage_canteens)
        local canteenTextWidth = imgui.CalcTextSize(canteenText)
        local totalWidth = mainTextWidth + canteenTextWidth
        local pos_x = col_start + (col_width - totalWidth) / 2
        
        -- Render main status text
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(textColor, displayText)
        
        -- Render canteen count in white
        imgui.SameLine()
        imgui.TextColored({1, 1, 1, 1}, canteenText)
    else
        -- For non-canteen items, render normally
        local text_width = imgui.CalcTextSize(displayText)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(textColor, displayText)
    end

    -- Tooltip
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        if show_canteen_count then
            -- Canteen-specific tooltip
            if storage_canteens >= 3 then
                imgui.Text('Storage is full (3/3 canteens).')
                imgui.Text('Use a canteen to start generation timer.')
            else
                local generationRemaining = packet_tracker.get_canteen_generation_remaining()
                if generationRemaining == nil then
                    imgui.Text('Generation time unknown.')
                    imgui.Text('Waiting for canteen data.')
                elseif generationRemaining <= 0 then
                    imgui.Text('Next canteen is ready to generate.')
                else
                    imgui.Text('Time until next canteen generation.')
                end
            end
        else
            -- Regular key item tooltip
            local timestamp = item.timestamp or 0
            if timestamp == 0 or item.remaining == nil then
                imgui.Text('No acquisition time recorded yet.')
                imgui.Text('Acquire the item to start tracking.')
            elseif item.remaining <= 0 then
                imgui.Text('Available now.')
            elseif item.remaining > 0 then
                imgui.Text('Still on cooldown.')
            else
                imgui.Text('Time calculation error.')
                imgui.Text('Please reload the addon.')
            end
        end
        imgui.EndTooltip()
    end
end

-- Render a single key item row
local function render_key_item_row(item, hasItem, storage_canteens, packet_tracker)
    -- Key Item Name (left aligned)
    imgui.Text(item.name)
    imgui.NextColumn()

    -- Have? (centered, colored)
    local statusText = hasItem and 'Yes' or 'No'
    local statusColor = hasItem and {0, 1, 0, 1} or {1, 0.2, 0.2, 1}
    do
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(statusText)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(statusColor, statusText)
    end
    imgui.NextColumn()

    -- Time Remaining
    render_time_remaining(item, hasItem, storage_canteens, packet_tracker)
    imgui.NextColumn()
    
    -- Add spacing between rows
    imgui.Spacing()
end

-- Render Dynamis [D] cooldown section
local function render_dynamis_d_section(packet_tracker)
    imgui.Separator()
    imgui.Spacing()
    
    -- Section header
    imgui.TextColored({1, 1, 0, 1}, 'Dynamis [D] Entry Cooldown')
    imgui.Spacing()
    
    -- Get cooldown status
    local remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local is_available = packet_tracker.is_dynamis_d_available()
    local entry_time = packet_tracker.get_dynamis_d_entry_time()
    
    -- Status display
    local status_text = is_available and 'Available' or 'On Cooldown'
    local status_color = is_available and {0, 1, 0, 1} or {1, 0.2, 0.2, 1}
    
    imgui.Text('Status: ')
    imgui.SameLine()
    imgui.TextColored(status_color, status_text)
    
    -- Time remaining display
    if remaining and remaining > 0 then
        local hours = math.floor(remaining / 3600)
        local minutes = math.floor((remaining % 3600) / 60)
        local seconds = remaining % 60
        
        imgui.Text('Time Remaining: ')
        imgui.SameLine()
        imgui.TextColored({1, 1, 1, 1}, string.format('%02d:%02d:%02d', hours, minutes, seconds))
    elseif entry_time > 0 then
        imgui.Text('Time Remaining: ')
        imgui.SameLine()
        imgui.TextColored({0, 1, 0, 1}, 'Ready')
    else
        imgui.Text('Time Remaining: ')
        imgui.SameLine()
        imgui.TextColored({0.7, 0.7, 0.7, 1}, 'No entry recorded')
    end
    
    -- Entry time display
    if entry_time > 0 then
        local entry_date = os.date('%Y-%m-%d %H:%M:%S', entry_time)
        imgui.Text('Last Entry: ')
        imgui.SameLine()
        imgui.TextColored({0.8, 0.8, 0.8, 1}, entry_date)
    end
    
    -- Tooltip with additional info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.Text('Dynamis [D] entry cooldown is 60 hours.')
        imgui.Text('Tracked automatically when entering')
        imgui.Text('Dynamis [D] zones from specific areas.')
        imgui.EndTooltip()
    end
end

-- Main render function
function gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)
    if not showGui[1] then return end

    -- Calculate dynamic window dimensions (add extra height for Dynamis [D] section)
    local width, height = calculate_window_dimensions(keyItemStatuses)
    height = height + 120  -- Add space for Dynamis [D] section
    imgui.SetNextWindowSizeConstraints({width, height}, {width, height})

    if not imgui.Begin('Keyring', showGui) then
        imgui.End()
        return
    end

    local total_width = imgui.GetWindowContentRegionWidth()
    
    -- Render headers
    render_headers(total_width)

    -- Render key item rows
    for i, item in ipairs(keyItemStatuses) do
        local hasItem = item.owned
        
        render_key_item_row(item, hasItem, storage_canteens, packet_tracker)
    end

    imgui.Columns(1)
    
    -- Render Dynamis [D] section
    render_dynamis_d_section(packet_tracker)
    
    imgui.End()
end

return gui