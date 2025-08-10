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
local BASE_WIDTH = 400

-- Object pool for color tables to reduce garbage collection
local color_pool = {
    red = {1, 0.2, 0.2, 1},
    green = {0, 1, 0, 1},
    gray = {0.7, 0.7, 0.7, 1},
    white = {1, 1, 1, 1},
    bright_green = {0.2, 1, 0.2, 1},
    soft_gray = {0.6, 0.6, 0.6, 1}
}

-- Reusable table for calculations to avoid creating new tables
local calc_buffer = {}

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

-- Cache for window dimensions to prevent unnecessary recalculations
local window_dimension_cache = {}
local last_dimension_update = 0
local DIMENSION_CACHE_DURATION = 1.0 -- Cache dimensions for 1 second

-- Calculate dynamic window dimensions based on content
local function calculate_window_dimensions(keyItemStatuses)
    local current_time = os.clock()
    
    -- Check cache first
    if window_dimension_cache.result and (current_time - last_dimension_update) < DIMENSION_CACHE_DURATION then
        return window_dimension_cache.result.width, window_dimension_cache.result.height
    end
    
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
     local hourglassHeaderHeight = 20    -- "Empty Hourglass" text
     local hourglassStatusHeight = 18    -- Status line (single line for most cases)
     local hourglassSpacing = 4          -- Reduced spacing between elements
     local hourglassSeparatorHeight = 8  -- Separator line
     local hourglassPadding = 8          -- Reduced padding for auto-scaling safety
     local hourglassBottomPadding = 5    -- Reduced padding below the row
     
     local hourglassSectionHeight = hourglassHeaderHeight + hourglassStatusHeight + 
                                   hourglassSpacing + hourglassSeparatorHeight + 
                                   hourglassPadding + hourglassBottomPadding
     
         -- Total height calculation with minimal padding
     local totalContentHeight = keyItemsHeight + dynamisSectionHeight + hourglassSectionHeight
     local requiredHeight = math.max(totalContentHeight + 5, MIN_HEIGHT)  -- 5px padding
     
    -- Calculate width based on longest item name
    local maxNameLength = 0
    for _, item in ipairs(keyItemStatuses) do
        if item.name and #item.name > maxNameLength then
            maxNameLength = #item.name
        end
    end
    
         local dynamicWidth = math.min(math.max(BASE_WIDTH + (maxNameLength * 5), MIN_WIDTH), MAX_WIDTH)
     
    -- Cache the result
    window_dimension_cache.result = {width = dynamicWidth, height = requiredHeight}
    last_dimension_update = current_time
    
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
     
     local nameWidth = math.max(total_width * 0.48, minNameWidth)
     local statusWidth = math.max(total_width * 0.15, minStatusWidth)
     local timeWidth = math.max(total_width * 0.37, minTimeWidth)
     
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

-- Time formatting cache to avoid repeated calculations
local time_format_cache = {}
local last_cache_cleanup = 0

-- Helper function to format time with caching
local function format_time_cached(seconds)
    if seconds <= 0 then return 'Ready.' end
    
    local cache_key = math.floor(seconds / 60) -- Cache by minute to reduce cache size
    local cached = time_format_cache[cache_key]
    if cached then
        return cached
    end
    
    local rh = math.floor(seconds / 3600)
    local rm = math.floor((seconds % 3600) / 60)
    local rs = seconds % 60
    local formatted = string.format('%02dh:%02dm:%02ds', rh, rm, rs)
    
    -- Clean cache every 5 minutes to prevent memory bloat
    local current_time = os.time()
    if current_time - last_cache_cleanup > 300 then
        time_format_cache = {}
        last_cache_cleanup = current_time
    end
    
    time_format_cache[cache_key] = formatted
    return formatted
end

-- Render time remaining with special canteen handling
local function render_time_remaining(item, hasItem, storage_canteens, packet_tracker)
    local displayText
    local textColor = color_pool.red -- Use pooled color
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
        
        -- Special handling for Shiny Rakaznar Plate (ID 3300)
        if item.id == 3300 and hasItem and (timestamp == 0 or item.remaining == nil or item.remaining <= 0) then
            -- Player has the plate and no cooldown - show dash since cooldown starts when used
            textColor = {0.7, 0.7, 0.7, 1} -- gray
            displayText = '-'
        elseif timestamp == 0 or item.remaining == nil then
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
    -- Add spacing for visual separation
    imgui.Spacing()
    imgui.Spacing()
    
         -- Set up 3 columns for Dynamis [D] section (no separator between columns)
     imgui.Columns(3, 'dynamisColumns', false)
     
     -- Fixed column widths for better layout
     local labelWidth = total_width * 0.35  -- Left column for labels (increased to prevent clipping)
     local statusWidth = total_width * 0.35  -- Center column for status
     local timeWidth = total_width * 0.30   -- Right column for time values
     
    imgui.SetColumnWidth(0, labelWidth)      -- Label (left justified)
    imgui.SetColumnWidth(1, statusWidth)     -- Status (centered)
    imgui.SetColumnWidth(2, timeWidth)       -- Time (right justified)
    
    -- Section header (left column) - left justified
    local headerText = 'Dynamis [D] Entry'
    imgui.Text(headerText)  -- Left justified
    imgui.NextColumn()
    
    -- Get cooldown status
    local remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local entry_time = packet_tracker.get_dynamis_d_entry_time()
    
    -- Check Dynamis availability (no longer managing hourglass increment)
    local is_dynamis_available = (remaining == nil or remaining <= 0)
    
         -- Status display - centered across entire window
     if entry_time == 0 or entry_time == nil then
         -- No entry recorded
         local display_text = 'Unknown'
         local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
         
         -- Center the status text across the entire window
         local text_width = imgui.CalcTextSize(display_text)
         local pos_x = (total_width - text_width) / 2
         imgui.SetCursorPosX(pos_x)
         imgui.TextColored(text_color, display_text)
         
     elseif remaining and remaining > 0 then
         -- On cooldown - show status only (time goes in right column)
         local display_text = 'On cooldown.'
         local text_color = {1, 0.2, 0.2, 1} -- Red text
         
         -- Center the status text across the entire window
         local text_width = imgui.CalcTextSize(display_text)
         local pos_x = (total_width - text_width) / 2
         imgui.SetCursorPosX(pos_x)
         imgui.TextColored(text_color, display_text)
         
     else
         -- Available
         local display_text = 'Ready'
         local text_color = {0.2, 1, 0.2, 1} -- Brighter green
         
         -- Center the status text across the entire window
         local text_width = imgui.CalcTextSize(display_text)
         local pos_x = (total_width - text_width) / 2
         imgui.SetCursorPosX(pos_x)
         imgui.TextColored(text_color, display_text)
     end
     
     imgui.NextColumn()
     
     -- Time display (right column) - right justified
     if entry_time == 0 or entry_time == nil then
         -- No entry recorded - no time to display
         imgui.Text('')
     elseif remaining and remaining > 0 then
         -- On cooldown - show time remaining
         local hours = math.floor(remaining / 3600)
         local minutes = math.floor((remaining % 3600) / 60)
         local seconds = remaining % 60
                   local timeText = string.format('%02dh:%02dm:%02ds', hours, minutes, seconds)
         
         -- Right justify the time text
         local col_start = imgui.GetColumnOffset()
         local col_width = imgui.GetColumnWidth()
         local text_width = imgui.CalcTextSize(timeText)
         local pos_x = col_start + col_width - text_width
         imgui.SetCursorPosX(pos_x)
         imgui.TextColored({1, 1, 1, 1}, timeText)  -- White text
     else
         -- Available - no time to display
         imgui.Text('')
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
     
           -- Minimal spacing at the bottom
      imgui.Spacing()
end

-- Render Hourglass cooldown section
local function render_hourglass_section(packet_tracker, total_width)
    -- Add spacing for visual separation
    imgui.Spacing()
    imgui.Spacing()
    
         -- Set up 3 columns for Hourglass section (no separator between columns)
     imgui.Columns(3, 'hourglassColumns', false)
     
     -- Fixed column widths for better layout
     local labelWidth = total_width * 0.35  -- Left column for labels (increased to prevent clipping)
     local statusWidth = total_width * 0.35  -- Center column for status
     local timeWidth = total_width * 0.30   -- Right column for time values
     
    imgui.SetColumnWidth(0, labelWidth)      -- Label (left justified)
    imgui.SetColumnWidth(1, statusWidth)     -- Status (centered)
    imgui.SetColumnWidth(2, timeWidth)       -- Time (right justified)
    
         -- Section header (left column) - left justified
     local headerText = 'Empty Hourglass'
     imgui.Text(headerText)  -- Left justified
     imgui.NextColumn()
     
     -- Add spacing to match Dynamis vertical alignment
     imgui.Spacing()
     imgui.Spacing()
    
    -- Get hourglass status
    local hourglass_remaining = packet_tracker.get_hourglass_time_remaining()
    local hourglass_time = packet_tracker.get_hourglass_time()
    local dynamis_remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
    local is_dynamis_available = (dynamis_remaining == nil or dynamis_remaining <= 0)
    
                                                           -- Status display - centered across entire window
       if hourglass_time == 0 or hourglass_time == nil then
           -- No hourglass use recorded
           local display_text = 'Unknown'
           local text_color = {0.6, 0.6, 0.6, 1} -- Softer gray
           
           -- Center the status text across the entire window
           local text_width = imgui.CalcTextSize(display_text)
           local pos_x = (total_width - text_width) / 2
           imgui.SetCursorPosX(pos_x)
           imgui.TextColored(text_color, display_text)
          
      else
          -- Calculate if hourglass has enough time to bypass Dynamis cooldown
          local dynamis_remaining = dynamis_remaining or 0
          
          local display_text
          local text_color
          
          if hourglass_time >= dynamis_remaining then
              -- Case 1: Hourglass time >= remaining cooldown → "Ready" in green
              display_text = 'Ready'
              text_color = {0.2, 1, 0.2, 1} -- Green
          else
              -- Case 2: Hourglass time < remaining cooldown → "Not enough time" in red
              display_text = 'Not enough time'
              text_color = {1, 0.2, 0.2, 1} -- Red
          end
          
          -- Center the status text in the column
          local col_start = imgui.GetColumnOffset()
          local col_width = imgui.GetColumnWidth()
          local text_width = imgui.CalcTextSize(display_text)
          local pos_x = col_start + (col_width - text_width) / 2
          imgui.SetCursorPosX(pos_x)
          imgui.TextColored(text_color, display_text)
      end
     
     imgui.NextColumn()
     
     -- Time display (right column) - right justified
     if hourglass_time == 0 or hourglass_time == nil then
         -- No hourglass use recorded - no time to display
         imgui.Text('')
     else
                 -- Helper function to format seconds as hh"h":mm"m":ss"s"
        local function format_time_readable(seconds)
            local hours = math.floor(seconds / 3600)
            local minutes = math.floor((seconds % 3600) / 60)
            local secs = seconds % 60
            return string.format('%02dh:%02dm:%02ds', hours, minutes, secs)
        end
        
        local timeText = string.format('%s', format_time_readable(hourglass_time))
         
                   -- Add spacing to match vertical alignment first
          imgui.Spacing()
          imgui.Spacing()
          
          -- Right justify the time text
          local col_start = imgui.GetColumnOffset()
          local col_width = imgui.GetColumnWidth()
          local text_width = imgui.CalcTextSize(timeText)
          local pos_x = col_start + col_width - text_width
          imgui.SetCursorPosX(pos_x)
          
          imgui.TextColored({1, 1, 1, 1}, timeText)  -- White text
     end
    
    -- Enhanced tooltip with more detailed info
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushStyleColor(0, {1, 1, 1, 1})  -- Text color (white)
        imgui.Text('Empty Hourglass System')
        imgui.Separator()
                 imgui.Text('• Shows the time value stored in the hourglass')
         imgui.Text('• Time is consumed when entering Dynamis [D] with cooldown')
         imgui.Text('• Green "Ready": Enough time to bypass current Dynamis cooldown')
         imgui.Text('• Red "Not enough time": Not enough time to bypass current Dynamis cooldown')
         if hourglass_time ~= 0 and hourglass_time ~= nil then
             imgui.Text('• Time stored: ' .. hourglass_time .. ' seconds')
         end
         
         -- Show "Last checked" timestamp if available
         local packet_timestamp = packet_tracker.get_hourglass_packet_timestamp()
         if packet_timestamp and packet_timestamp > 0 then
             local last_checked_date = os.date('%Y-%m-%d %H:%M', packet_timestamp)
             imgui.Text('• Last checked: ' .. last_checked_date)
         end
         imgui.EndTooltip()
     end
     
     imgui.NextColumn()
     
     -- Minimal spacing at the bottom
     imgui.Spacing()
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
     
           -- Add spacing before the unified section
      imgui.Spacing()
      imgui.Spacing()
      
      -- Top separator for the unified section
      imgui.Separator()
      
      -- Render Dynamis [D] section
      render_dynamis_d_section(packet_tracker, total_width)
      
      -- Row separator between Dynamis and Hourglass
      imgui.Separator()
      
      -- Render Hourglass section
      render_hourglass_section(packet_tracker, total_width)
      
      -- Bottom separator for the unified section
      imgui.Separator()
    
    imgui.End()
end

return gui