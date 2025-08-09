-- Keyring Packet Handler Module
-- Handles all packet processing and state management for the keyring addon

-- Debug flag - set to true to enable debug output
local debugMode = false

-- Import required modules
local persistence = require('keyring_persistence')
require('common')
local struct = require('struct')
local trackedKeyItems = require('tracked_key_items')
local key_items = require('key_items_optimized')
local chat = require('chat')

-- Debug throttling system
local debug_throttle = {
    messages = {},  -- Track last message time for each unique message
    default_interval = 5.0,  -- Default throttle interval in seconds
    render_interval = 10.0   -- Longer interval for render-related messages
}

-- Throttled debug function - prevents spam from frequent calls
local function debug_print(message, throttle_interval)
    if not debugMode then
        return
    end
    
    -- Use default interval if none specified
    throttle_interval = throttle_interval or debug_throttle.default_interval
    
    local current_time = os.time()
    local last_time = debug_throttle.messages[message]
    
    -- Check if enough time has passed since last identical message
    if not last_time or (current_time - last_time) >= throttle_interval then
        pcall(function()
            print('[Keyring Debug] ' .. tostring(message))
        end)
        debug_throttle.messages[message] = current_time
    end
end

-- Special debug function for render-related messages (longer throttle)
local function debug_print_render(message)
    debug_print(message, debug_throttle.render_interval)
end

-- Function to clear debug throttle cache (useful for testing)
local function debug_clear_throttle()
    debug_throttle.messages = {}
end

-- Simple event system
local event = {}

local event_object = {}

function event_object:trigger(...)
    for _, fn in pairs(self.handlers) do 
        pcall(fn, ...) 
    end
    for _, fn in pairs(self.temp_handlers) do
        pcall(fn, ...)
        self.temp_handlers[fn] = nil
    end
end

function event_object:register(fn) 
    self.handlers[fn] = fn 
end

function event_object:once(fn) 
    self.temp_handlers[fn] = fn 
end

function event_object:unregister(fn) 
    self.handlers[fn] = nil 
end

function event.new()
    return setmetatable({handlers = {}, temp_handlers = {}},
                        {__index = event_object})
end

-- Event system for zone changes
local zone_events = {
    onZoneChange = event.new(),
}

-- Use Lua mode for persistence
local persistence_mode = 'lua'

-- Handler table for API functions
local handler = {}

-- Dynamis [D] zone transition mapping
local dynamis_zone_transitions = {
    [230] = 294,  -- southern_san_doria => Dynamis-San_Doria_[D]
    [234] = 295,  -- Bastok_Mines => Dynamis-Bastok_[D]
    [239] = 296,  -- Windurst_Walls => Dynamis-Windurst_[D]
    [243] = 297   -- RuLude_Gardens => Dynamis-Jeuno_[D]
}

-- Ra'Kaznar zone transition mapping (for Shiny Rakaznar Plate usage detection)
local rakaznar_zone_transitions = {
    [267] = {275, 133, 189}  -- Kamihr Drifts => Outer Ra'Kaznar [U1], [U2], [U3]
}

-- Load state from file (using persistence module)
local function load_state()
    return persistence.load_state(debug_print)
end

-- Initialize with empty state - will be loaded when player is ready
local state = {
    timestamps = {},
    owned = {},
    storage_canteens = 0,
    last_canteen_time = 0
}

local firstLoad = false

-- Create a protected state accessor to prevent corruption
local function get_state()
    if type(state) ~= 'table' then
        debug_print('ERROR: State corrupted! This should not happen after persistence is loaded.')
        debug_print('WARNING: Not auto-recreating state to prevent data loss. Loading from persistence.')
        
        -- Try to reload from persistence instead of creating empty state
        if firstLoad then
            local loaded_state = load_state()
            if type(loaded_state) == 'table' then
                state = loaded_state
                debug_print('Successfully recovered state from persistence file')
                return state
            end
        end
        
        -- Only create empty state as last resort
        debug_print('CRITICAL: Creating empty state as last resort - data may be lost!')
        state = {
            timestamps = {},
            owned = {},
            storage_canteens = 0,
            last_canteen_time = 0
        }
    end
    return state
end

local function set_state(new_state)
    if type(new_state) == 'table' then
        state = new_state
        debug_print('State updated')
    else
        debug_print('Invalid state type')
    end
end

-- Save state to file (using persistence module)
local function save_state()
    local current_state = get_state()
    
    -- Safety check: don't save if state appears to be empty/corrupted
    if not current_state.timestamps or not current_state.owned then
        debug_print('WARNING: Refusing to save potentially corrupted state (missing timestamps or owned tables)')
        return false
    end
    
    -- Additional safety: don't save if all timestamps are 0 and all owned are false (likely corrupted)
    local has_meaningful_data = false
    for id, timestamp in pairs(current_state.timestamps) do
        if timestamp > 0 then
            has_meaningful_data = true
            break
        end
    end
    
    if not has_meaningful_data then
        for id, owned in pairs(current_state.owned) do
            if owned == true then
                has_meaningful_data = true
                break
            end
        end
    end
    
    if not has_meaningful_data and firstLoad then
        debug_print('WARNING: State appears to be empty - not saving to prevent data loss')
        return false
    end
    
    return persistence.save_state(current_state, debug_print)
end

-- Callback hooks
local currency_callback = nil
local zone_callback = nil

-- Flag to track if we've already requested canteen data after login/reload
local canteen_requested = false

-- Flag to track if we've done the post-0x0A key item check
local post_zone_check_done = false

-- Zone tracking variables
local current_zone = nil
local previous_zone = nil

-- Request Storage Slip Canteen info (outgoing packet 0x115)
local function request_currency_data()
    local packet = struct.pack('bbbb', 0x15, 0x03, 0x00, 0x00):totable()
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x115, packet)
end

-- Called when a tracked key item is acquired
local function update_keyitem_state(id)
    local current_state = get_state()
    
    -- Ensure required tables exist
    if not current_state.timestamps then current_state.timestamps = {} end
    if not current_state.owned then current_state.owned = {} end
    
    local now = os.time()
    
    -- Set timestamp for new acquisition
    current_state.owned[id] = true
    debug_print('Key item acquired: ' .. tostring(id))

    -- Handle special cases for different key items
    if id == 3300 then
        -- Shiny Rakaznar Plate - don't set timestamp, cooldown starts when used
        debug_print('Shiny Rakaznar Plate acquired - no timestamp set (cooldown starts when used)')
    elseif id == 3212 then
        -- Moglophone - set timestamp when acquired (cooldown starts immediately)
        current_state.timestamps[id] = now
        debug_print('Moglophone acquired - 20-hour cooldown started')
        print(chat.header('Keyring'):append(chat.message('Moglophone acquired - 20-hour cooldown started')))
    elseif id == 3137 then
        -- Don't set last_canteen_time here - it should be set when a new canteen is generated
        -- not when the key item is acquired
        debug_print('Canteen key item acquired')
        request_currency_data()
    end
    
    -- Save state after changes
    save_state()
end

-- API: Register callback for storage canteen updates
function handler.set_currency_callback(cb)
    currency_callback = cb
end

-- API: Register callback for zone change
function handler.set_zone_change_callback(cb)
    zone_callback = cb
end

-- API: Is a key item currently held?
function handler.has_key_item(id)
    local current_state = get_state()
    
    if not current_state.owned then
        return false
    end
    
    local owned_status = current_state.owned[id]
    return owned_status == true
end

-- API: Get timestamp for acquisition
function handler.get_timestamp(id)
    if not id or type(id) ~= 'number' then
        return 0
    end
    local current_state = get_state()
    if not current_state.timestamps then
        return 0
    end
    return current_state.timestamps[id] or 0
end

-- API: Get all timestamps
function handler.get_timestamps()
    local current_state = get_state()
    if not current_state.timestamps then
        return {}
    end
    return current_state.timestamps
end

-- API: Set timestamp for a specific item
function handler.set_timestamp(id, timestamp)
    if not id or type(id) ~= 'number' or not timestamp or type(timestamp) ~= 'number' then
        return false
    end
    
    local current_state = get_state()
    if not current_state.timestamps then current_state.timestamps = {} end
    if not current_state.owned then current_state.owned = {} end
    
    current_state.timestamps[id] = timestamp
    current_state.owned[id] = true
    debug_print('Timestamp set for ID: ' .. tostring(id))
    
    -- Save state after changes
    save_state()
    return true
end

-- API: Get cooldown remaining
function handler.get_remaining(id)
    if not id or type(id) ~= 'number' then
        return 0
    end
    
    local current_state = get_state()
    if not current_state.timestamps then
        return 0
    end
    
    local cooldown = trackedKeyItems[id]
    local ts = current_state.timestamps[id]
    if not cooldown or not ts then 
        return 0 
    end
    return math.max(0, (ts + cooldown) - os.time())
end

-- API: Is key item cooldown expired?
function handler.is_available(id)
    local current_state = get_state()
    if not current_state.timestamps then
        return false
    end
    
    local cooldown = trackedKeyItems[id]
    local ts = current_state.timestamps[id]
    
    -- Return false if no cooldown defined or timestamp is 0/nil (never acquired)
    if not cooldown or not ts or ts <= 0 then 
        return false 
    end
    
    return os.time() >= (ts + cooldown)
end

-- API: Last storage time / count
function handler.get_storage_info()
    local current_state = get_state()
    return {
        count = current_state.storage_canteens or 0,
        last_storage = 0
    }
end

-- API: Get last canteen time
function handler.get_canteen_timestamp()
    local current_state = get_state()
    return current_state.last_canteen_time or 0
end

-- API: Update storage canteens based on timestamp
function handler.update_storage_canteens()
    local current_state = get_state()
    
    local currentTime = os.time()
    
    -- Only process if we have a valid generation timer and storage is not full
    if current_state.last_canteen_time and current_state.last_canteen_time > 0 and current_state.storage_canteens and current_state.storage_canteens < 3 then
        local timeSinceTimerStart = currentTime - current_state.last_canteen_time
        
        -- If the timer is more than 24 hours old, it's probably stale - reset it
        if timeSinceTimerStart > 86400 then  -- 24 hours
            debug_print('Canteen generation timer is stale, resetting')
            current_state.last_canteen_time = 0
            save_state()
            return current_state.storage_canteens or 0
        end
        
        -- Check if 20 hours have passed since timer started
        if timeSinceTimerStart >= 72000 then  -- 20 hours = 72000 seconds
            -- Generate one canteen
            current_state.storage_canteens = current_state.storage_canteens + 1
            
            -- Reset timer to current time for next generation cycle
            current_state.last_canteen_time = currentTime
            
            -- Save state after updating
            save_state()
            
            debug_print('Canteen generated: ' .. current_state.storage_canteens .. '/3')
        end
    end
    
    return current_state.storage_canteens or 0
end

-- API: Get time remaining until next canteen generation
function handler.get_canteen_generation_remaining()
    local current_state = get_state()
    
    -- If storage is full, no more canteens will be generated
    if current_state.storage_canteens and current_state.storage_canteens >= 3 then
        return nil
    end
    
    -- If we don't have a generation timer, we can't calculate
    if not current_state.last_canteen_time or current_state.last_canteen_time <= 0 then
        return nil
    end
    
    local currentTime = os.time()
    local timeSinceTimerStart = currentTime - current_state.last_canteen_time
    
    -- If the timer is more than 24 hours old, it's probably stale
    if timeSinceTimerStart > 86400 then  -- 24 hours
        return nil
    end
    
    local remaining = 72000 - timeSinceTimerStart  -- 20 hours minus elapsed time
    
    return math.max(0, remaining)
end

-- API: Get Dynamis [D] cooldown remaining time
function handler.get_dynamis_d_cooldown_remaining()
    local current_state = get_state()
    
    -- If no entry time recorded, no cooldown
    if not current_state.dynamis_d_entry_time or current_state.dynamis_d_entry_time <= 0 then
        return nil
    end
    
    local current_time = os.time()
    local time_since_entry = current_time - current_state.dynamis_d_entry_time
    
    -- Dynamis [D] cooldown is 60 hours (216000 seconds)
    local cooldown_duration = 216000
    local remaining = cooldown_duration - time_since_entry
    
    return math.max(0, remaining)
end

-- API: Get Dynamis [D] entry timestamp
function handler.get_dynamis_d_entry_time()
    local current_state = get_state()
    return current_state.dynamis_d_entry_time or 0
end

 -- API: Get hourglass timestamp (with increment logic)
 function handler.get_hourglass_time()
     local current_state = get_state()
     local base_hourglass_time = current_state.hourglass_time or 0
     local packet_timestamp = current_state.hourglass_packet_timestamp or 0
     local increment_start_time = current_state.hourglass_increment_start_time or 0
     
     -- If no base hourglass time, return 0
     if base_hourglass_time == 0 then
         return 0
     end
     
     -- If no packet timestamp, fall back to old increment logic
     if packet_timestamp == 0 then
         -- If increment hasn't started, return base time
         if increment_start_time == 0 then
             return base_hourglass_time
         end
         
         -- Calculate increment: 1 second for every 5 seconds that pass
         local current_time = os.time()
         local time_since_increment_start = current_time - increment_start_time
         local increment_seconds = math.floor(time_since_increment_start / 5)  -- 1 second per 5 seconds
         
         -- Return base time plus increment
         return base_hourglass_time + increment_seconds
     end
     
     -- Use new formula: (current_time - packet_timestamp) / 5 + base_hourglass_time
     local current_time = os.time()
     local time_since_packet = current_time - packet_timestamp
     local accumulated_seconds = math.floor(time_since_packet / 5)  -- 1 second per 5 seconds
     
     -- Return base hourglass time plus accumulated time
     return base_hourglass_time + accumulated_seconds
 end

-- API: Get hourglass time remaining (24-hour cooldown)
function handler.get_hourglass_time_remaining()
    local hourglass_time = handler.get_hourglass_time()
    if hourglass_time == 0 then
        return nil  -- No hourglass use recorded
    end
    
    local current_time = os.time()
    local elapsed = current_time - hourglass_time
    local cooldown_duration = 86400  -- 24 hours in seconds
    
    local remaining = cooldown_duration - elapsed
    return math.max(0, remaining)
end

-- API: Start hourglass increment when Dynamis becomes available
function handler.start_hourglass_increment()
    local current_state = get_state()
    local increment_start_time = current_state.hourglass_increment_start_time or 0
    
    -- Only start increment if it hasn't already started
    if increment_start_time == 0 then
        current_state.hourglass_increment_start_time = os.time()
        save_state()
        debug_print('Hourglass increment started - Dynamis [D] is now available')
    end
end

-- API: Stop hourglass increment when Dynamis becomes unavailable
function handler.stop_hourglass_increment()
    local current_state = get_state()
    local increment_start_time = current_state.hourglass_increment_start_time or 0
    
    -- Only stop increment if it was running
    if increment_start_time > 0 then
        -- Calculate the current hourglass time before stopping
        local current_hourglass_time = handler.get_hourglass_time()
        current_state.hourglass_time = current_hourglass_time
        current_state.hourglass_increment_start_time = 0
        save_state()
        debug_print('Hourglass increment stopped - Dynamis [D] is no longer available')
    end
end

-- API: Check if Dynamis [D] is available (cooldown expired)
function handler.is_dynamis_d_available()
    local remaining = handler.get_dynamis_d_cooldown_remaining()
    return remaining == nil or remaining <= 0
end

-- API: Save state to file
function handler.save_state()
    save_state()
end

-- API: Get persistence mode
function handler.get_persistence_mode()
    return persistence_mode
end

-- API: Get current state (for testing/debugging)
function handler.get_state()
    return get_state()
end

-- API: Set current zone for testing (useful for debugging)
function handler.set_current_zone(zone_id)
    if not zone_id or type(zone_id) ~= 'number' then
        debug_print('Invalid zone ID provided: ' .. tostring(zone_id))
        return false
    end
    
    current_zone = zone_id
    debug_print('Current zone manually set to: ' .. zone_id)
    return true
end

-- API: Get current zone ID
function handler.get_current_zone()
    local mem = AshitaCore:GetMemoryManager()
    local player = mem:GetPlayer()
    
    if not player then
        return nil
    end
    
    return player:GetZone()
end

-- API: Register for zone change events
function handler.on_zone_change(callback)
    zone_events.onZoneChange:register(callback)
end

-- API: Get zone events system
function handler.get_zone_events()
    return zone_events
end

-- API: Load persistence file when player is ready
function handler.load_persistence_file()
    if firstLoad then
        return
    end
    
    -- Check if player is available before loading
    local mem = AshitaCore:GetMemoryManager()
    local player = mem:GetPlayer()
    if not player then
        debug_print('Player not ready, skipping persistence load')
        return
    end
    
    debug_print('Loading persistence file')
    local loaded_state = load_state()
    
    if type(loaded_state) == 'table' then
        -- Validate canteen generation timer - only reset if extremely old (7 days)
        if loaded_state.last_canteen_time and loaded_state.last_canteen_time > 0 then
            local currentTime = os.time()
            local timeSinceTimerStart = currentTime - loaded_state.last_canteen_time
            
            -- Only reset if timer is more than 7 days old (likely corrupted data)
            if timeSinceTimerStart > 604800 then  -- 7 days = 604800 seconds
                debug_print('Canteen generation timer is extremely old (>7 days), resetting')
                loaded_state.last_canteen_time = 0
            elseif timeSinceTimerStart > 86400 then  -- 24 hours
                debug_print('Canteen generation timer is old but keeping it (timer: ' .. timeSinceTimerStart .. ' seconds)')
            end
        end
        
        set_state(loaded_state)
        debug_print('Persistence loaded successfully')
        firstLoad = true
    else
        debug_print('Failed to load persistence file')
        -- Don't set firstLoad to true if loading failed
    end
end

-- PACKET HOOKS --

-- Consolidated packet handler for all packet types
ashita.events.register('packet_in', 'Keyring_PacketHandler', function(e)
    if e.id == 0x55 then
        -- Key item list (0x55) - Using Thorny's approach
        local current_state = get_state()
        if not current_state.owned then
            debug_print('ERROR: Invalid state in 0x55 packet handler')
            return
        end

        debug_print('Processing 0x55 packet')

        local offset = struct.unpack('B', e.data, 0x84 + 1) * 512

        for ki, _ in pairs(trackedKeyItems) do
            if (ki >= offset) and (ki <= offset + 511) then
                local hasKeyItem = (ashita.bits.unpack_be(e.data_raw, 0x04, ki - offset, 1) == 1)
                local wasOwned = current_state.owned[ki] == true
                
                if hasKeyItem ~= wasOwned then
                    -- HasKeyItem state changed - save to persistence file
                    debug_print('Key item state changed: ' .. tostring(ki))
                    
                    if hasKeyItem then
                        -- Item acquired
                        local hasExistingTimestamp = current_state.timestamps[ki] and current_state.timestamps[ki] > 0
                        
                        if not hasExistingTimestamp then
                            -- New acquisition - set timestamp (except for Shiny Rakaznar Plate)
                            if ki == 3300 then
                                -- Shiny Rakaznar Plate - don't set timestamp, cooldown starts when used
                                debug_print('Shiny Rakaznar Plate acquired - no timestamp set (cooldown starts when used)')
                                print(chat.header('Keyring'):append(chat.message('Acquired Shiny Rakaznar Plate - cooldown will start when used')))
                                current_state.owned[ki] = true
                                save_state()
                            else
                                -- Other items - set timestamp normally
                                debug_print('New key item acquired: ' .. tostring(ki))
                                print(chat.header('Keyring'):append(chat.message(string.format('Acquired tracked key item: %s', key_items.idToName[ki] or ('ID ' .. ki)))))
                                update_keyitem_state(ki)
                            end
                        else
                            -- Item already has timestamp - just mark as owned (no new timestamp)
                            debug_print('Key item already tracked: ' .. tostring(ki))
                            current_state.owned[ki] = true
                            save_state()
                        end
                    else
                        -- Item lost
                        debug_print('Key item lost: ' .. tostring(ki))
                        current_state.owned[ki] = false
                        
                        -- Special handling for key item loss
                        if ki == 3300 then
                            -- Shiny Rakaznar Plate was lost - start cooldown timer
                            local now = os.time()
                            current_state.timestamps[ki] = now  -- Set timestamp when plate is lost
                            debug_print('Shiny Rakaznar Plate lost via 0x55 packet - 20-hour cooldown started')
                            print(chat.header('Keyring'):append(chat.message('Shiny Rakaznar Plate lost - 20-hour cooldown started')))
                        elseif ki == 3212 then
                            -- Moglophone was lost - just update owned status (cooldown already started on acquisition)
                            debug_print('Moglophone lost via 0x55 packet - cooldown continues from acquisition time')
                        end
                        
                        save_state()
                    end
                end
            end
        end
        
    elseif e.id == 0x0A then
        -- Zone change detection using 0x0A packets with direct packet parsing
        -- Extract zone ID directly from packet data (more reliable than player:GetZone())
        local zoneId = struct.unpack('H', e.data, 0x10+1)
        
        debug_print('Zone change packet received - zone ID: ' .. zoneId)
        
        -- Track zone transitions: if current_zone exists, set it as previous_zone
        if current_zone ~= nil then
            previous_zone = current_zone
        end
        
        -- Record new zone from packet
        current_zone = zoneId
        
        -- Only process if zone actually changed
        if previous_zone == current_zone then
            debug_print('Zone unchanged: ' .. current_zone)
            return
        end
        
        debug_print('Zone changed from ' .. (previous_zone or 'unknown') .. ' to ' .. current_zone)
        
        -- Trigger zone change event
        zone_events.onZoneChange:trigger(zoneId)
        
        local notify_time = os.time() + 6
        local check_pending = true
        local notified = false

        if zone_callback then
            zone_callback(notify_time, check_pending, notified)
        end

        -- Request canteen data only on the first zone after login/reload
        if not canteen_requested then
            debug_print('Requesting canteen data')
            request_currency_data()
            canteen_requested = true
        end

        -- Skip post-zone check - rely on 0x55 packets for accurate ownership data
        if not post_zone_check_done then
            debug_print('First zone complete')
            post_zone_check_done = true
        end
        
        -- Check for Dynamis [D] zone transitions
        local current_state = get_state()
        
        for pre_zone_id, dynamis_zone_id in pairs(dynamis_zone_transitions) do
            if previous_zone == pre_zone_id and current_zone == dynamis_zone_id then
                -- We're transitioning from an entry zone to a Dynamis [D] zone - record the entry
                local now = os.time()
                current_state.dynamis_d_entry_time = now
                save_state()
                
                debug_print('Dynamis [D] entry detected - zone transition from ' .. pre_zone_id .. ' to ' .. dynamis_zone_id)
                print(chat.header('Keyring'):append(chat.message(string.format('Entered Dynamis [D] zone (ID: %d) - cooldown started', dynamis_zone_id))))
                break
            end
        end
        
        -- Check for Ra'Kaznar zone transitions (Shiny Rakaznar Plate usage detection)
        for pre_zone_id, target_zones in pairs(rakaznar_zone_transitions) do
            if previous_zone == pre_zone_id then
                -- Check if we're transitioning from Kamihr Drifts to any Outer Ra'Kaznar zone
                for _, target_zone_id in ipairs(target_zones) do
                    if current_zone == target_zone_id then
                        -- Player used their Shiny Rakaznar Plate - start cooldown timer
                        local plate_id = 3300  -- Shiny Rakaznar Plate ID
                        if current_state.owned and current_state.owned[plate_id] == true then
                            local now = os.time()
                            current_state.owned[plate_id] = false
                            current_state.timestamps[plate_id] = now  -- Set timestamp when plate is used
                            save_state()
                            
                            debug_print('Shiny Rakaznar Plate usage detected - zone transition from ' .. pre_zone_id .. ' to ' .. current_zone)
                            print(chat.header('Keyring'):append(chat.message('Shiny Rakaznar Plate used - 20-hour cooldown started')))
                        end
                        break
                    end
                end
            end
        end
        
    elseif e.id == 0x02A then
        -- Hourglass usage detection (0x02A) - from four different NPCs
        local current_state = get_state()
        
        -- Extract message ID and parameters from the packet
        local messageId = struct.unpack('H', e.data, 0x1A+1)
        local actor_ID = struct.unpack('I', e.data, 0x04+1)  -- Actor ID (4 bytes) at offset 0x04
        local param2 = struct.unpack('I', e.data, 0x08+1)  -- Use 'I' for 32-bit integer since Param2 is 4 bytes
        
        debug_print('0x02A packet received - Message ID: ' .. messageId .. ', Actor ID: ' .. actor_ID .. ', Param2: ' .. param2)
        
        -- Validation table: Actor ID -> Expected Message ID pairs
        local hourglass_validation = {
            [17772867] = 48733,
            [17720029] = 49344,
            [17756500] = 43686,
            [17736063] = 49463
        }
        
                 -- Double validation: Check both actor_ID and messageId are valid and match
         local expected_message_id = hourglass_validation[actor_ID]
         if expected_message_id and messageId == expected_message_id then
             -- This is a confirmed hourglass usage message
             local now = os.time()
             -- Store the Param2 value (hourglass time in seconds) and the timestamp when it was received
             current_state.hourglass_time = param2
             current_state.hourglass_packet_timestamp = now  -- Store timestamp when packet was received
             current_state.hourglass_increment_start_time = 0  -- Reset increment state when new packet arrives
             save_state()
             
             debug_print('Hourglass time detected via 0x02A packet - Actor ID: ' .. actor_ID .. ', Message ID: ' .. messageId .. ', Hourglass Time: ' .. param2 .. ' seconds, Timestamp: ' .. now)             return
         end
        
        -- Log other 0x02A packets for debugging (throttled to prevent spam)
        debug_print('0x02A packet not recognized as hourglass - Message ID: ' .. messageId .. ', Param2: ' .. param2, 5.0)
        
    elseif e.id == 0x118 then
        -- Canteen storage response (0x118)
        local current_state = get_state()

        local canteenCount = e.data:byte(12) or 0 
        canteenCount = math.min(canteenCount, 3)
        
        local previousCount = current_state.storage_canteens or 0
        
        -- Check if canteens increased (indicating new generation)
        if canteenCount > previousCount then
            debug_print('Canteen count increased - new canteen generated')
            
            -- This could be due to our generation logic or external factors
            -- Don't modify the generation timer here - let update_storage_canteens handle it
            
            -- Update canteen timestamp for Mystical Canteen (ID 3137) if not already tracked
            local canteenId = 3137
            if not current_state.timestamps or not current_state.timestamps[canteenId] or current_state.timestamps[canteenId] == 0 then
                debug_print('Canteen acquisition detected')
                
                -- Don't set a timestamp - let the user acquire it manually for accuracy
                if not current_state.owned then current_state.owned = {} end
                current_state.owned[canteenId] = true
                
                -- Show informative message
                print(chat.header('Keyring'):append(chat.message('Canteen storage increased but exact acquisition time unknown.')))
                print(chat.header('Keyring'):append(chat.message('Please acquire a canteen manually to start accurate tracking.')))
            end
        elseif canteenCount < previousCount then
            -- Canteen was used (count decreased)
            debug_print('Canteen count decreased - canteen was used')
            
            -- If storage was full and now has space, start the generation timer
            if previousCount >= 3 and canteenCount < 3 then
                current_state.last_canteen_time = os.time()
                debug_print('Storage space available - starting canteen generation timer')
            end
        else
            -- Normal case: just update the count (no change detected)
            debug_print('Canteen count updated')
        end

        current_state.storage_canteens = canteenCount

        if currency_callback then
            currency_callback(canteenCount)
        end
        
        -- Save state after canteen data changes
        save_state()
    end
end)

-- Get key item statuses for GUI
function handler.get_key_item_statuses()
    local result = {}
    
    -- Always try to load persistence if not already loaded
    if not firstLoad then
        debug_print('Loading persistence for GUI')
        handler.load_persistence_file()
    end
    
    local current_state = get_state()
    
    -- Throttle these debug messages to prevent spam during GUI rendering
    debug_print('Current state in get_key_item_statuses:', 10.0)  -- 10 second throttle
    debug_print('  timestamps: ' .. (current_state.timestamps and 'exists' or 'nil'), 10.0)
    debug_print('  owned: ' .. (current_state.owned and 'exists' or 'nil'), 10.0)
    if current_state.timestamps then
        for id, timestamp in pairs(current_state.timestamps) do
            debug_print('    ID ' .. id .. ': ' .. timestamp, 10.0)
        end
    end

    if not current_state.timestamps then
        -- Return empty result if state is invalid
        for id, cooldown in pairs(trackedKeyItems) do
            local name = key_items.idToName[id] or ('Unknown ID: ' .. tostring(id))
            table.insert(result, {
                id = id,
                name = name,
                remaining = nil,
                timestamp = 0,
                owned = false,
            })
        end
        return result
    end

    for id, cooldown in pairs(trackedKeyItems) do
        local timestamp = current_state.timestamps[id] or 0

        if type(timestamp) ~= 'number' then
            timestamp = tonumber(timestamp) or 0
        end

        local remaining = nil  -- Set to nil if no timestamp
        if timestamp > 0 then
            remaining = (timestamp + cooldown) - os.time()
            debug_print(string.format('Item %d (%s): timestamp=%d, cooldown=%d, current_time=%d, remaining=%d', 
                id, key_items.idToName[id] or 'Unknown', timestamp, cooldown, os.time(), remaining))
        end
        
        local name = key_items.idToName[id] or ('Unknown ID: ' .. tostring(id))
        
        -- Get owned status from persisted state
        local owned = false
        if current_state.owned and current_state.owned[id] then
            owned = current_state.owned[id] == true
        end

        table.insert(result, {
            id = id,
            name = name,
            remaining = remaining,
            timestamp = timestamp,
            owned = owned,
        })
    end

    return result
end

-- API: Set debug mode
function handler.set_debug_mode(enabled)
    debugMode = enabled
    debug_print("Debug mode " .. (enabled and "enabled" or "disabled") .. " in packet handler")
end

-- API: Clear debug throttle cache
function handler.clear_debug_throttle()
    debug_clear_throttle()
    debug_print("Debug throttle cache cleared")
end

-- API: Set debug throttle intervals
function handler.set_debug_throttle_intervals(default_interval, render_interval)
    if default_interval and type(default_interval) == 'number' then
        debug_throttle.default_interval = default_interval
    end
    if render_interval and type(render_interval) == 'number' then
        debug_throttle.render_interval = render_interval
    end
    debug_print("Debug throttle intervals updated - default: " .. debug_throttle.default_interval .. "s, render: " .. debug_throttle.render_interval .. "s")
end

return handler