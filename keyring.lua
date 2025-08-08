addon.author   = 'Avogadro, assistance from Thorny and Will'
addon.name     = 'Keyring'
addon.version  = '0.3.1'

require('common')
local chat = require('chat')
local trackedKeyItems = require('tracked_key_items')
local key_items = require('key_items_optimized')
local packet_tracker = require('keyring_packet_handler')
local gui = require('keyring_gui')

-- Local copies of canteen state, updated via callback
local storage_canteens = 0

packet_tracker.set_currency_callback(function(canteens)
    storage_canteens = canteens
end)

-- Set up zone change callback
packet_tracker.set_zone_change_callback(function(notify_time, check_pending, notified)
    zone_notify_time = notify_time
    zone_check_pending = check_pending
    zone_notified = notified
    
    -- Check for available key items after zoning (if notifications are enabled)
    if notification_enabled then
        local availableItems = {}
        for id, _ in pairs(trackedKeyItems) do
            local timestamp = packet_tracker.get_timestamp(id) or 0
            local remaining = packet_tracker.get_remaining(id) or 0
            local hasItem = has_key_item(id)
            
            -- Only notify if: has timestamp, is available (remaining <= 0), and player doesn't have it
            if timestamp > 0 and remaining <= 0 and not hasItem then
                local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
                table.insert(availableItems, itemName)
            end
        end
        
        if #availableItems > 0 then
            local itemList = table.concat(availableItems, ', ')
            print(chat.header('Keyring'):append(chat.message(string.format('Available for pickup: %s', itemList))))
        end
    end
end)

-- GUI state and timing
local last_canteen_time = 0
local last_storage_update = 0

-- Zone notification variables
local zone_check_pending = false
local zone_notify_time = 0
local zone_notified = false

-- Debug flag
local debug_mode = false
local notification_enabled = true

-- Debug helper function
local function debug_print(message)
    if debug_mode then
        print(chat.header('Keyring Debug'):append(chat.message(message)))
    end
end

-- Set debug mode in packet handler
local function update_debug_mode()
    if packet_tracker.set_debug_mode then
        packet_tracker.set_debug_mode(debug_mode)
    end
end

local function has_key_item(id)
    return packet_tracker.has_key_item(id)
end



local function is_item_available(id)
    if id == 3137 then
        -- Canteen availability is based on storage count, not cooldown
        local canteenCount = packet_tracker.get_storage_info().count
        return canteenCount > 0
    else
        return packet_tracker.is_available(id)
    end
end

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:lower():split(' ')
    if args[1] ~= '/keyring' then return false end

    -- Toggle the GUI if no extra args or 'gui'
    if args[2] == nil or args[2] == '' or args[2] == 'gui' then
        local isVisible = gui.toggle()
        print(chat.header('Keyring'):append(chat.message('GUI ' .. (isVisible and 'toggled on.' or 'toggled off.'))))
        return true
    end

    -- Debug toggle
    if args[2] == 'debug' then
        debug_mode = not debug_mode
        update_debug_mode()
        print(chat.header('Keyring'):append(chat.message('Debug mode ' .. (debug_mode and 'enabled.' or 'disabled.'))))
        if debug_mode then
            print(chat.header('Keyring'):append(chat.message('Debug messages will now be shown in chat.')))
        end
        return true
    end

    -- Notification toggle
    if args[2] == 'notify' then
        notification_enabled = not notification_enabled
        print(chat.header('Keyring'):append(chat.message('Notifications ' .. (notification_enabled and 'enabled.' or 'disabled.'))))
        return true
    end

    -- Check command
    if args[2] == 'check' then
        local availableItems = {}
        for id, _ in pairs(trackedKeyItems) do
            local timestamp = packet_tracker.get_timestamp(id) or 0
            local remaining = packet_tracker.get_remaining(id) or 0
            local hasItem = has_key_item(id)
            
            -- Only show if: has timestamp, is available (remaining <= 0), and player doesn't have it
            if timestamp > 0 and remaining <= 0 and not hasItem then
                local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
                table.insert(availableItems, itemName)
            end
        end
        
        if #availableItems > 0 then
            local itemList = table.concat(availableItems, ', ')
            print(chat.header('Keyring'):append(chat.message(string.format('Available for pickup: %s', itemList))))
        else
            print(chat.header('Keyring'):append(chat.message('No key items are currently available for pickup.')))
        end
        return true
    end

    -- Status command
    if args[2] == 'status' then
        local persistence_mode = packet_tracker.get_persistence_mode()
        local dynamis_remaining = packet_tracker.get_dynamis_d_cooldown_remaining()
        local dynamis_available = packet_tracker.is_dynamis_d_available()
        local dynamis_entry_time = packet_tracker.get_dynamis_d_entry_time()
        
        print(chat.header('Keyring'):append(chat.message('Addon Status:')))
        print(chat.message('  • Persistence Mode: ' .. persistence_mode:upper()))
        print(chat.message('  • Debug Mode: ' .. (debug_mode and 'Enabled' or 'Disabled')))
        print(chat.message('  • Notifications: ' .. (notification_enabled and 'Enabled' or 'Disabled')))
        print(chat.message('  • Dynamis [D] Status: ' .. (dynamis_available and 'Available' or 'On Cooldown')))
        
        if dynamis_entry_time > 0 then
            local entry_date = os.date('%Y-%m-%d %H:%M:%S', dynamis_entry_time)
            print(chat.message('  • Dynamis [D] Last Entry: ' .. entry_date))
        else
            print(chat.message('  • Dynamis [D] Last Entry: None recorded'))
        end
        
        if dynamis_remaining and dynamis_remaining > 0 then
            local hours = math.floor(dynamis_remaining / 3600)
            local minutes = math.floor((dynamis_remaining % 3600) / 60)
            print(chat.message('  • Dynamis [D] Time Remaining: ' .. string.format('%02d:%02d', hours, minutes)))
        end
        
        return true
    end

    -- Test Dynamis [D] entry (for testing purposes)
    if args[2] == 'test_dynamis' then
        local current_state = packet_tracker.get_state()
        local now = os.time()
        current_state.dynamis_d_entry_time = now
        packet_tracker.save_state()
        
        print(chat.header('Keyring'):append(chat.message('Test: Dynamis [D] entry time set to current time')))
        print(chat.header('Keyring'):append(chat.message('Use /keyring status to see the cooldown')))
        return true
    end
    

    
    -- Test zone detection
    if args[2] == 'test_zone' then
        local current_zone = packet_tracker.get_current_zone()
        if current_zone then
            print(chat.header('Keyring'):append(chat.message('Current zone (from player): ' .. current_zone)))
        else
            print(chat.header('Keyring'):append(chat.message('Could not get current zone from player object')))
        end
        
        -- Also show the last detected zone from packet parsing
        local zone_events = packet_tracker.get_zone_events()
        if zone_events and zone_events.onZoneChange then
            print(chat.header('Keyring'):append(chat.message('Zone event system is active')))
        else
            print(chat.header('Keyring'):append(chat.message('Zone event system not available')))
        end
        return true
    end

    -- Help command
    if args[2] == 'help' then
        print(chat.header('Keyring'):append(chat.message('Keyring Addon - Key Item Cooldown Tracker')))
        print(chat.message(''))
        print(chat.message('This addon tracks key items with cooldown timers:'))
        print(chat.message('  • Moglophone (20h cooldown)'))
        print(chat.message('  • Mystical Canteen (20h generation cycle)'))
        print(chat.message('  • Shiny Rakaznar Plate (20h cooldown)'))
        print(chat.message('  • Dynamis [D] entry cooldown (60h cooldown)'))
        print(chat.message('  • Empty Hourglass cooldown (24h cooldown)'))
        print(chat.message(''))
        print(chat.message('Available commands:'))
        print(chat.message('  /keyring or /keyring gui - Toggle the GUI window'))
        print(chat.message('  /keyring debug - Toggle debug messages in chat'))
        print(chat.message('  /keyring check - Check for available key items'))
        print(chat.message('  /keyring notify - Toggle zone change notifications'))
        print(chat.message('  /keyring status - Show addon status and persistence mode'))
        print(chat.message('  /keyring test_dynamis - Test Dynamis [D] entry (for testing)'))
    
        print(chat.message('  /keyring test_zone - Test zone detection'))
        print(chat.message('  /keyring help - Show this help information'))
        print(chat.message(''))
        print(chat.message('Features:'))
        print(chat.message('  • Automatic detection of key item acquisition'))
        print(chat.message('  • Real-time cooldown tracking'))
        print(chat.message('  • Zone change notifications'))
        print(chat.message('  • Special canteen storage tracking (generation-based)'))
        print(chat.message('  • Dynamis [D] entry tracking (automatic zone detection)'))
        print(chat.message('  • Empty Hourglass tracking (automatic packet detection)'))
        print(chat.message('  • Persistent state across sessions (Lua-based)'))
        print(chat.message('  • Shows "Unknown" until first acquisition'))
        print(chat.message('  • Notifications for available items on zone change'))
        return true
    end

    -- Unknown command
    print(chat.header('Keyring'):append(chat.message('Unknown command. Type /keyring help for available commands.')))
    return true
end)

ashita.events.register('load', 'load_cb', function()
    debug_print('Addon load event triggered')
    print(chat.header('Keyring'):append(chat.message('Keyring loaded. Key item state will be initialized after first zone.')))
end)

-- Load persistence file when player is ready (with delay for full initialization)
local player_ready_time = 0
local persistence_loaded = false

ashita.events.register('d3d_present', 'LoadDelayTimer', function()
    local playerName = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    
    if playerName ~= nil and playerName ~= '' then
        if player_ready_time == 0 then
            -- First time player is detected - start the delay timer
            player_ready_time = os.time()
            debug_print('Player data ready, starting 3-second delay for full initialization...')
        elseif os.time() - player_ready_time >= 3 and not persistence_loaded then
            -- 3 seconds have passed, load persistence file
            ashita.events.unregister('d3d_present', 'LoadDelayTimer')
            debug_print('Delay complete, loading persistence file...')
            
            if packet_tracker.load_persistence_file then
                packet_tracker.load_persistence_file()
            end
            
            persistence_loaded = true
        end
    end
end)

ashita.events.register('d3d_present', 'render', function()
    local current_time = os.time()
    if current_time - last_storage_update > 5 then
        storage_canteens = packet_tracker.update_storage_canteens()
        last_storage_update = current_time
    end

    if zone_check_pending and current_time >= zone_notify_time and not zone_notified then
        local notify_needed = false
        for id in pairs(trackedKeyItems) do
            if is_item_available(id) and not has_key_item(id) then
                notify_needed = true
                break
            end
        end

        if notify_needed then
            print(chat.header('Keyring'):append(chat.message('One or more key items are available for pickup! /keyring to check.')))
        end

        zone_notified = true
        zone_check_pending = false
    end



    -- Render the GUI using the modularized GUI system
    local keyItemStatuses = packet_tracker.get_key_item_statuses()
    
    -- Debug: Print the statuses being passed to GUI (throttled to prevent spam)
    if debug_mode and #keyItemStatuses > 0 then
        -- Use a throttled debug print for render-related messages
        local debug_message = 'GUI render - keyItemStatuses count: ' .. #keyItemStatuses
        local current_time = os.time()
        if not _G.last_gui_debug_time or (current_time - _G.last_gui_debug_time) >= 10 then
            debug_print(debug_message)
            _G.last_gui_debug_time = current_time
        end
    end
    
    gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)

end)