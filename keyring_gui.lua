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
    
    -- Calculate height for key items section
    local spacingCount = math.max(0, itemCount - 1)
    local keyItemsHeight = HEADER_HEIGHT + (itemCount * ITEM_HEIGHT) + (spacingCount * SPACING_HEIGHT)
    
    -- Calculate height for Dynamis [D] section (reduced padding)
    local dynamisHeaderHeight = 20      -- "Dynamis [D] Entry Cooldown" text
    local dynamisStatusHeight = 18      -- Status line
    local dynamisSpacing = 4            -- Reduced spacing between elements
    local dynamisSeparatorHeight = 8    -- Separator line
    local dynamisPadding = 8            -- Reduced padding for auto-scaling safety
    local dynamisBottomPadding = 5      -- Reduced padding below the row
    
    local dynamisSectionHeight = dynamisHeaderHeight + dynamisStatusHeight + 
                                dynamisSpacing + dynamisSeparatorHeight + 
                                dynamisPadding + dynamisBottomPadding
    
    -- Calculate height for Hourglass section (similar to Dynamis)
    local hourglassHeaderHeight = 20    -- "Empty Hourglass Time" text
    local hourglassStatusHeight = 18    -- Status line
    local hourglassSpacing = 4          -- Reduced spacing between elements
    local hourglassSeparatorHeight = 8  -- Separator line
    local hourglassPadding = 8          -- Reduced padding for auto-scaling safety
    local hourglassBottomPadding = 5    -- Reduced padding below the row
    
    local hourglassSectionHeight = hourglassHeaderHeight + hourglassStatusHeight + 
                                  hourglassSpacing + hourglassSeparatorHeight + 
                                  hourglassPadding + hourglassBottomPadding
    
    -- Total height calculation with minimal padding
    local totalContentHeight = keyItemsHeight + dynamisSectionHeight + hourglassSectionHeight
    local requiredHeight = math.max(totalContentHeight + PADDING + 5, MIN_HEIGHT)  -- Reduced from 20px to 5px safety margin
    
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
    
    if show_canteen_count then
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
local function render_dynamis_d_section(packet_tracker, total_width)
    -- Add row separator above Dynamis section
    imgui.PushStyleColor(3, {0.3, 0.3, 0.3, 0.8})  -- Separator color
    imgui.Separator()
    imgui.PopStyleColor()
    
    -- Add spacing for visual separation
    imgui.Spacing()
    imgui.Spacing()
    
    -- Set up 2 columns for Dynamis [D] section (no separator between columns)
    imgui.Columns(2, 'dynamisColumns', false)
    
    -- Fixed column widths for better layout
    local labelWidth = total_width * 0.55  -- Narrower for label
    local statusWidth = total_width * 0.45  -- Wider for status text
    
    imgui.SetColumnWidth(0, labelWidth)      -- Label
    imgui.SetColumnWidth(1, statusWidth)     -- Status
    
    -- Section header (left column) - centered
    local headerText = 'Dynamis [D] Entry'
    local col_start = imgui.GetColumnOffset()
    local col_width = imgui.GetColumnWidth()
    local text_width = imgui.CalcTextSize(headerText)
    local pos_x = col_start + (col_width - text_width) / 2
    imgui.SetCursorPosX(pos_x)
    imgui.PushStyleColor(0, {1, 1, 1, 1})  -- Text color (white)
    imgui.Text(headerText)
    imgui.PopStyleColor()
    imgui.NextColumn()
    
    -- Get cooldown status
    local remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local entry_time = packet_tracker.get_dynamis_d_entry_time()
    
    -- Check Dynamis availability and manage hourglass increment
    local is_dynamis_available = (remaining == nil or remaining <= 0)
    if is_dynamis_available then
        -- Dynamis is available - start hourglass increment if not already started
        packet_tracker.start_hourglass_increment()
    else
        -- Dynamis is on cooldown - stop hourglass increment if it was running
        packet_tracker.stop_hourglass_increment()
    end
    
    -- Status display (right column) with improved formatting
    if entry_time == 0 or entry_time == nil then
        -- No entry recorded
        local display_text = 'Unknown'
        local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
        
        -- Center the status text in the column
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, display_text)
        
    elseif remaining and remaining > 0 then
        -- On cooldown - show time remaining with improved formatting
        local hours = math.floor(remaining / 3600)
        local minutes = math.floor((remaining % 3600) / 60)
        local seconds = remaining % 60
        local timeText = string.format('%02d:%02d:%02d', hours, minutes, seconds)
        
        -- Calculate positioning for multi-colored text
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        
        -- Calculate total width of all text parts
        local onCooldownWidth = imgui.CalcTextSize('On Cooldown')
        local colonWidth = imgui.CalcTextSize(': [')
        local timeWidth = imgui.CalcTextSize(timeText)
        local bracketWidth = imgui.CalcTextSize(']')
        local totalWidth = onCooldownWidth + colonWidth + timeWidth + bracketWidth
        
        -- Center the entire text block
        local pos_x = col_start + (col_width - totalWidth) / 2
        imgui.SetCursorPosX(pos_x)
        
        -- Render multi-colored text: "On Cooldown: [time]"
        imgui.TextColored({1, 0.2, 0.2, 1}, 'On Cooldown')  -- Red text
        imgui.SameLine()
        imgui.TextColored({1, 1, 1, 1}, ': [')  -- White text
        imgui.SameLine()
        imgui.TextColored({1, 0.2, 0.2, 1}, timeText)  -- Red text
        imgui.SameLine()
        imgui.TextColored({1, 1, 1, 1}, ']')  -- White text
        
    else
        -- Available
        local display_text = 'Ready'
        local text_color = {0.2, 1, 0.2, 1} -- Brighter green
        
        -- Center the status text in the column
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, display_text)
    end
    
    -- Enhanced tooltip with more detailed info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushStyleColor(0, {1, 0.8, 0, 1})  -- Text color
        imgui.Text('Dynamis [D] Entry System')
        imgui.PopStyleColor()
        imgui.Separator()
        imgui.Text('• 60-hour cooldown between entries')
        imgui.Text('• Automatically tracked on zone entry')
        imgui.Text('• Entry zones: Jeuno, Bastok, San d\'Oria, Windurst')
        if entry_time ~= 0 and entry_time ~= nil then
            local entryDate = os.date('%Y-%m-%d %H:%M', entry_time)
            imgui.Text('• Last entry: ' .. entryDate)
        end
        imgui.EndTooltip()
    end
    
    imgui.NextColumn()
    
    -- Add spacing at the bottom
    imgui.Spacing()
    imgui.Spacing()
    
    -- Add row separator below Dynamis section
    imgui.PushStyleColor(3, {0.3, 0.3, 0.3, 0.8})  -- Separator color
    imgui.Separator()
    imgui.PopStyleColor()
end

-- Render Hourglass cooldown section
local function render_hourglass_section(packet_tracker, total_width)
    -- Add spacing for visual separation
    imgui.Spacing()
    imgui.Spacing()
    
    -- Set up 2 columns for Hourglass section (no separator between columns)
    imgui.Columns(2, 'hourglassColumns', false)
    
    -- Fixed column widths for better layout
    local labelWidth = total_width * 0.55  -- Narrower for label
    local statusWidth = total_width * 0.45  -- Wider for status text
    
    imgui.SetColumnWidth(0, labelWidth)      -- Label
    imgui.SetColumnWidth(1, statusWidth)     -- Status
    
    -- Section header (left column) - centered
    local headerText = 'Empty Hourglass Time'
    local col_start = imgui.GetColumnOffset()
    local col_width = imgui.GetColumnWidth()
    local text_width = imgui.CalcTextSize(headerText)
    local pos_x = col_start + (col_width - text_width) / 2
    imgui.SetCursorPosX(pos_x)
    imgui.PushStyleColor(0, {1, 1, 1, 1})  -- Text color (white)
    imgui.Text(headerText)
    imgui.PopStyleColor()
    imgui.NextColumn()
    
    -- Get hourglass status
    local hourglass_remaining = packet_tracker.get_hourglass_time_remaining()
    local hourglass_time = packet_tracker.get_hourglass_time()
    local dynamis_remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local is_dynamis_available = (dynamis_remaining == nil or dynamis_remaining <= 0)
    
    -- Status display (right column) with conditional coloring
    if hourglass_time == 0 or hourglass_time == nil then
        -- No hourglass use recorded
        local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
        
        -- Center the status text in the column
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        
        -- Calculate center position for each line individually
        local line1 = 'Unknown.'
        local line2 = 'Ask the Enigmatic Footprints.'
        local line1_width = imgui.CalcTextSize(line1)
        local line2_width = imgui.CalcTextSize(line2)
        
        -- Center first line
        local pos_x1 = col_start + (col_width - line1_width) / 2
        imgui.SetCursorPosX(pos_x1)
        imgui.TextColored(text_color, line1)
        
        -- Center second line
        local pos_x2 = col_start + (col_width - line2_width) / 2
        imgui.SetCursorPosX(pos_x2)
        imgui.TextColored(text_color, line2)
        
    elseif hourglass_remaining and hourglass_remaining > 0 then
        -- On cooldown - show time remaining
        local hours = math.floor(hourglass_remaining / 3600)
        local minutes = math.floor((hourglass_remaining % 3600) / 60)
        local seconds = hourglass_remaining % 60
        local timeText = string.format('%02d:%02d:%02d', hours, minutes, seconds)
        
        -- Determine text color based on user's specification: yellow when Hourglass Time - Dynamis Time Remaining > 0, green otherwise
        local text_color
        if dynamis_remaining and dynamis_remaining > 0 then
            local time_diff = hourglass_time - dynamis_remaining
            if time_diff > 0 then
                text_color = {1, 1, 0, 1}      -- Yellow (hourglass ready after Dynamis)
            else
                text_color = {0.2, 1, 0.2, 1}  -- Green (hourglass ready before/with Dynamis)
            end
        else
            text_color = {0.2, 1, 0.2, 1}      -- Green (Dynamis ready, hourglass on cooldown)
        end
        
        -- Center the status text in the column
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(timeText)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, timeText)
        
    else
        -- Available - show current hourglass time (including increment if Dynamis is available)
        local display_text
        local text_color = {0.2, 1, 0.2, 1} -- Brighter green
        
        if is_dynamis_available and hourglass_time > 0 then
            -- Show incrementing time when Dynamis is available
            local hours = math.floor(hourglass_time / 3600)
            local minutes = math.floor((hourglass_time % 3600) / 60)
            local seconds = hourglass_time % 60
            display_text = string.format('%02d:%02d:%02d', hours, minutes, seconds)
            text_color = {0.8, 1, 0.8, 1} -- Light green to indicate incrementing
        else
            -- Show "Ready" when not incrementing
            display_text = 'Ready'
        end
        
        -- Center the status text in the column
        local col_start = imgui.GetColumnOffset()
        local col_width = imgui.GetColumnWidth()
        local text_width = imgui.CalcTextSize(display_text)
        local pos_x = col_start + (col_width - text_width) / 2
        imgui.SetCursorPosX(pos_x)
        imgui.TextColored(text_color, display_text)
    end
    
    -- Enhanced tooltip with more detailed info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushStyleColor(0, {1, 1, 1, 1})  -- Text color (white)
        imgui.Text('Empty Hourglass System')
        imgui.PopStyleColor()
        imgui.Separator()
        imgui.Text('• 24-hour cooldown between uses')
        imgui.Text('• Automatically detected via packet sniffing')
        imgui.Text('• Increments by 1 second every 5 seconds when Dynamis [D] is available')
        imgui.Text('• Green: Hourglass Time <= Dynamis Time Remaining')
        imgui.Text('• Yellow: Hourglass Time > Dynamis Time Remaining')
        imgui.Text('• Light green: Currently incrementing (Dynamis [D] available)')
        if hourglass_time ~= 0 and hourglass_time ~= nil then
            local hourglassDate = os.date('%Y-%m-%d %H:%M', hourglass_time)
            imgui.Text('• Last use: ' .. hourglassDate)
        end
        imgui.EndTooltip()
    end
    
    imgui.NextColumn()
    
    -- Add spacing at the bottom
    imgui.Spacing()
    imgui.Spacing()
    
    -- Add row separator below Hourglass section
    imgui.PushStyleColor(3, {0.3, 0.3, 0.3, 0.8})  -- Separator color
    imgui.Separator()
    imgui.PopStyleColor()
end

-- Main render function
function gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)
    if not showGui[1] then return end

    -- Calculate dynamic window dimensions (includes Dynamis [D] section)
    local width, height = calculate_window_dimensions(keyItemStatuses)
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
    render_dynamis_d_section(packet_tracker, total_width)
    
    -- Render Hourglass section
    render_hourglass_section(packet_tracker, total_width)
    
    imgui.End()
end

return gui