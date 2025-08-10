addon.author   = 'Avogadro, assistance from Thorny and Will'
addon.name     = 'Keyring'
addon.version  = '0.3.2'

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

-- Zone notification variables
local zone_check_pending = false
local zone_notify_time = 0
local zone_notified = false

-- Debug and notification flags
local debug_mode = false
local notification_enabled = true

-- Debug helper function
local function debug_print(message)
    if debug_mode then
        print(chat.header('Keyring Debug'):append(chat.message(message)))
    end
end

-- Memory monitoring function (for debugging)
local function get_memory_usage()
    local info = collectgarbage('count')
    return math.floor(info / 1024 * 100) / 100 -- Convert to MB with 2 decimal places
end

-- Set debug mode in packet handler
local function update_debug_mode()
    if packet_tracker.set_debug_mode then
        packet_tracker.set_debug_mode(debug_mode)
    end
end

-- Helper function to check if item is available
local function is_item_available(id)
    if id == 3137 then
        -- Canteen availability is based on storage count, not cooldown
        local canteenCount = packet_tracker.get_storage_info().count
        return canteenCount > 0
    else
        return packet_tracker.is_available(id)
    end
end

-- Set up zone change callback
packet_tracker.set_zone_change_callback(function(notify_time, check_pending, notified)
    zone_notify_time = notify_time
    zone_check_pending = check_pending
    zone_notified = notified
    
    -- Check for available key items after zoning (if notifications are enabled)
    if notification_enabled then
        for id, _ in pairs(trackedKeyItems) do
            local hasItem = packet_tracker.has_key_item(id)
            local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
            local available = is_item_available(id)
            
            -- Debug logging for zone change availability check
            if debug_mode then
                debug_print(string.format('Zone change check - %s: Available=%s, Own=%s, ShouldNotify=%s', 
                    itemName, tostring(available), tostring(hasItem), tostring(available and not hasItem)))
            end
            
            -- Notify if item is available and player doesn't have it
            -- This handles both cooldown-based items and storage-based items (canteens)
            if available and not hasItem then
                debug_print('ZONE NOTIFICATION TRIGGERED for: ' .. itemName)
                print(chat.header('Keyring'):append(chat.message(string.format('%s is ready for pickup', itemName))))
            end
        end
    end
end)

-- Helper function to get available items for pickup
local function get_available_items()
    local availableItems = {}
    for id, _ in pairs(trackedKeyItems) do
        local hasItem = packet_tracker.has_key_item(id)
        local available = is_item_available(id)
        
        -- Only show if item is available and player doesn't have it
        -- This handles both cooldown-based items and storage-based items (canteens)
        if available and not hasItem then
            local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
            table.insert(availableItems, itemName)
        end
    end
    return availableItems
end

-- Command handler
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

    -- Memory usage command
    if args[2] == 'memory' then
        local memory_mb = get_memory_usage()
        print(chat.header('Keyring'):append(chat.message('Current memory usage: ' .. memory_mb .. ' MB')))
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
        local availableItems = get_available_items()
        
        if #availableItems > 0 then
            -- Show individual callouts for each available item
            for _, itemName in ipairs(availableItems) do
                print(chat.header('Keyring'):append(chat.message(string.format('%s is ready for pickup', itemName))))
            end
        else
            print(chat.header('Keyring'):append(chat.message('No key items are currently available for pickup.')))
        end
        
        -- Debug mode: show detailed availability info
        if debug_mode then
            print(chat.header('Keyring Debug'):append(chat.message('Detailed availability check:')))
            for id, _ in pairs(trackedKeyItems) do
                local timestamp = packet_tracker.get_timestamp(id) or 0
                local remaining = packet_tracker.get_remaining(id) or 0
                local hasItem = packet_tracker.has_key_item(id)
                local itemName = key_items.idToName[id] or ('ID ' .. tostring(id))
                
                local status = 'Not available'
                if timestamp > 0 and remaining <= 0 and not hasItem then
                    status = 'AVAILABLE for pickup'
                elseif timestamp <= 0 then
                    status = 'No timestamp (Unknown status)'
                elseif remaining > 0 then
                    local hours = math.floor(remaining / 3600)
                    local minutes = math.floor((remaining % 3600) / 60)
                    status = string.format('On cooldown (%02d:%02d remaining)', hours, minutes)
                elseif hasItem then
                    status = 'Already owned'
                end
                
                print(chat.message(string.format('  %s: %s (TS:%d, Rem:%d, Own:%s)', 
                    itemName, status, timestamp, remaining, tostring(hasItem))))
            end
        end
        return true
    end

    -- Fix command - manually trigger acquisition for missed packets
    if args[2] == 'fix' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring fix <item>')))
            print(chat.message('Available items: Moglophone, Mystical Canteen, Shiny Rakaznar Plate'))
            return true
        end
        
        -- Convert item name to proper case and find ID
        local itemName = args[3]:lower()
        local itemId = nil
        
        -- Create case-insensitive lookup
        for id, name in pairs(key_items.idToName) do
            if name:lower():find(itemName, 1, true) then
                itemId = id
                itemName = name  -- Use the proper name
                break
            end
        end
        
        if not itemId then
            print(chat.header('Keyring'):append(chat.message('Unknown item: ' .. args[3])))
            print(chat.message('Available items: Moglophone, Mystical Canteen, Shiny Rakaznar Plate'))
            return true
        end
        
        -- Check if item is already owned
        local hasItem = packet_tracker.has_key_item(itemId)
        if hasItem then
            print(chat.header('Keyring'):append(chat.message(string.format('%s is already in your inventory', itemName))))
            return true
        end
        
        -- Trigger manual acquisition
        local now = os.time()
        local success = packet_tracker.set_timestamp(itemId, now)
        
        if success then
            print(chat.header('Keyring'):append(chat.message(string.format('Manual acquisition triggered for %s - cooldown started', itemName))))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to set timestamp for ' .. itemName)))
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

    -- Manual hourglass command - set hourglass time for missed packets
    if args[2] == 'hourglass' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring hourglass <time_in_seconds>')))
            print(chat.message('Example: /keyring hourglass 7200 (for 2 hours)'))
            return true
        end
        
        local hourglass_time = tonumber(args[3])
        if not hourglass_time or hourglass_time < 0 then
            print(chat.header('Keyring'):append(chat.message('Invalid time value. Please provide time in seconds.')))
            return true
        end
        
        local current_state = packet_tracker.get_state()
        local now = os.time()
        
        -- Set hourglass time manually
        current_state.hourglass_time = hourglass_time
        current_state.hourglass_packet_timestamp = now

        packet_tracker.save_state()
        
        local hours = math.floor(hourglass_time / 3600)
        local minutes = math.floor((hourglass_time % 3600) / 60)
        local seconds = hourglass_time % 60
        print(chat.header('Keyring'):append(chat.message(string.format('Manual hourglass time set: %02dh:%02dm:%02ds (%d seconds)', hours, minutes, seconds, hourglass_time))))
        print(chat.header('Keyring'):append(chat.message('Time will be consumed automatically when entering Dynamis [D] with cooldown')))
        
        return true
    end

    -- Reset hourglass time command
    if args[2] == 'reset_hourglass' then
        local success = packet_tracker.reset_hourglass_time()
        if success then
            print(chat.header('Keyring'):append(chat.message('Hourglass time has been reset to 0')))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to reset hourglass time')))
        end
        return true
    end

    -- Dump packet data command (for debugging)
    if args[2] == 'dump_packet' then
        print(chat.header('Keyring'):append(chat.message('Packet dump command added - will dump next 0x02A packet data')))
        -- This will be handled in the packet handler
        return true
    end

    -- Force update hourglass time command (bypasses packet validation)
    if args[2] == 'force_hourglass' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Usage: /keyring force_hourglass <time_in_seconds>')))
            print(chat.message('Example: /keyring force_hourglass 147939'))
            return true
        end
        
        local hourglass_time = tonumber(args[3])
        if not hourglass_time or hourglass_time < 0 then
            print(chat.header('Keyring'):append(chat.message('Invalid time value. Please provide time in seconds.')))
            return true
        end
        
        local success = packet_tracker.force_hourglass_time(hourglass_time)
        if success then
            local hours = math.floor(hourglass_time / 3600)
            local minutes = math.floor((hourglass_time % 3600) / 60)
            local seconds = hourglass_time % 60
            print(chat.header('Keyring'):append(chat.message(string.format('Hourglass time forced to: %02dh:%02dm:%02ds (%d seconds)', hours, minutes, seconds, hourglass_time))))
        else
            print(chat.header('Keyring'):append(chat.message('Failed to force hourglass time')))
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

    -- Backup commands
    if args[2] == 'backup' then
        if not args[3] or args[3] == '' then
            print(chat.header('Keyring'):append(chat.message('Backup Commands:')))
            print(chat.message('  /keyring backup create - Create a manual backup'))
            print(chat.message('  /keyring backup list - List available backups'))
            print(chat.message('  /keyring backup restore <filename> - Restore from backup'))
            print(chat.message('  /keyring backup info - Show backup system info'))
            return true
        end
        
        if args[3] == 'create' then
            local success = persistence.create_manual_backup(debug_print)
            if success then
                print(chat.header('Keyring'):append(chat.message('Manual backup created successfully')))
            else
                print(chat.header('Keyring'):append(chat.message('Failed to create manual backup')))
            end
            return true
        end
        
        if args[3] == 'list' then
            local backups = persistence.list_backups(debug_print)
            if #backups > 0 then
                print(chat.header('Keyring'):append(chat.message('Available backups:')))
                for i, backup in ipairs(backups) do
                    print(chat.message('  ' .. i .. '. ' .. backup))
                end
            else
                print(chat.header('Keyring'):append(chat.message('No backups found')))
            end
            return true
        end
        
        if args[3] == 'restore' then
            if not args[4] or args[4] == '' then
                print(chat.header('Keyring'):append(chat.message('Usage: /keyring backup restore <filename>')))
                print(chat.message('Use /keyring backup list to see available backups'))
                return true
            end
            
            local success = persistence.restore_from_backup(args[4], debug_print)
            if success then
                print(chat.header('Keyring'):append(chat.message('Successfully restored from backup: ' .. args[4])))
                print(chat.header('Keyring'):append(chat.message('Please reload the addon with /addon reload keyring')))
            else
                print(chat.header('Keyring'):append(chat.message('Failed to restore from backup: ' .. args[4])))
            end
            return true
        end
        
        if args[3] == 'info' then
            print(chat.header('Keyring'):append(chat.message('Backup System Information:')))
            print(chat.message('  • Automatic backups: Every hour'))
            print(chat.message('  • Backup retention: 24 backups (1 day)'))
            print(chat.message('  • Backup location: data/backups/'))
            print(chat.message('  • Backup format: keyring_backup_<server_id>_<timestamp>.lua'))
            return true
        end
        
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
        print(chat.header('Keyring'):append(chat.message('Keyring Addon v0.3.2 - Key Item Cooldown Tracker')))
        print(chat.message(''))
        print(chat.message('== TRACKED KEY ITEMS =='))
        print(chat.message('  • Moglophone (20h cooldown) - Acquired when obtained'))
        print(chat.message('  • Mystical Canteen (20h generation cycle) - Storage-based tracking'))
        print(chat.message('  • Shiny Rakaznar Plate (20h cooldown) - Starts when used for teleport'))
        print(chat.message('  • Dynamis [D] Entry (60h cooldown) - Auto-detected on zone entry'))
        print(chat.message('  • Empty Hourglass - Time value tracked via NPC interactions'))
        print(chat.message(''))
        print(chat.message('== COMMANDS =='))
        print(chat.message('  /keyring [gui] - Toggle the GUI window'))
        print(chat.message('  /keyring check - Check for available key items (individual callouts)'))
        print(chat.message('  /keyring fix <item> - Manually trigger acquisition for missed packets'))
        print(chat.message('    Available items: moglophone, canteen, plate'))
        print(chat.message('  /keyring hourglass <seconds> - Manually set hourglass time for missed packets'))
        print(chat.message('  /keyring reset_hourglass - Reset hourglass time to 0'))
        print(chat.message('  /keyring force_hourglass <seconds> - Force hourglass time (bypasses validation)'))
        print(chat.message('  /keyring notify - Toggle zone change notifications (default: on)'))
        print(chat.message('  /keyring status - Show addon status and cooldown information'))
        print(chat.message('  /keyring debug - Toggle debug messages in chat'))
        print(chat.message('  /keyring backup - Backup system commands (create/list/restore/info)'))
        print(chat.message('  /keyring help - Show this help information'))
        print(chat.message(''))
        print(chat.message('== NOTIFICATIONS =='))
        print(chat.message('  • Individual item acquisition alerts (always on)'))
        print(chat.message('  • Individual "ready for pickup" alerts on zone change'))
        --print(chat.message('  • No general notifications - each item gets specific callout'))
        print(chat.message('  • Toggle zone notifications with /keyring notify'))
        print(chat.message(''))
        print(chat.message('== FEATURES =='))
        print(chat.message('  • Automatic packet-based detection of key item events'))
        print(chat.message('  • Real-time GUI with countdown timers'))
        print(chat.message('  • Persistent state across character sessions'))
        print(chat.message('  • Manual acquisition fix for missed packets'))
        print(chat.message('  • Smart cooldown handling per item type'))
        print(chat.message('  • Zone-based automatic Dynamis [D] and Ra\'Kaznar detection'))
        print(chat.message('  • Empty Hourglass time tracking and status display'))
        print(chat.message(''))
        --print(chat.message('== DEVELOPER COMMANDS =='))
        --print(chat.message('  /keyring test_dynamis - Test Dynamis [D] entry detection'))
        --print(chat.message('  /keyring test_zone - Test current zone detection'))
        return true
    end

    -- Unknown command
    print(chat.header('Keyring'):append(chat.message('Unknown command. Type /keyring help for available commands.')))
    return true
end)

-- Load event
ashita.events.register('load', 'load_cb', function()
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
        elseif os.time() - player_ready_time >= 3 and not persistence_loaded then
            -- 3 seconds have passed, load persistence file
            ashita.events.unregister('d3d_present', 'LoadDelayTimer')
            
            if packet_tracker.load_persistence_file then
                packet_tracker.load_persistence_file()
            end
            
            persistence_loaded = true
        end
    end
end)

-- Main render loop
ashita.events.register('d3d_present', 'render', function()
    -- Update storage canteens every 5 seconds
    local current_time_seconds = os.time()
    if current_time_seconds - (last_storage_update or 0) > 5 then
        storage_canteens = packet_tracker.update_storage_canteens()
        last_storage_update = current_time_seconds
    end

    -- Zone notifications are now handled immediately in the zone change callback
    -- No need for delayed notifications since individual callouts happen on zone change

    -- Render the GUI using the modularized GUI system
    local keyItemStatuses = packet_tracker.get_key_item_statuses()
    

    
    gui.render(keyItemStatuses, trackedKeyItems, storage_canteens, packet_tracker)
end)