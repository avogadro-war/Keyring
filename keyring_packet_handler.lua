-- Debug flag - set to true to enable debug output
local debugMode = false

-- Simple debug function - only prints if debugMode is true
local function debug_print(message)
    if debugMode then
        pcall(function()
            print('[Keyring Debug] ' .. tostring(message))
        end)
    end
end

-- Simple event system (similar to onevent2's approach)
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

require('common')
local struct = require('struct')
local trackedKeyItems = require('tracked_key_items')
local key_items = require('key_items_optimized')
local chat = require('chat')

local handler = {}

-- Event system for zone changes
local zone_events = {
    onZoneChange = event.new(),
}

-- Persistence system using Lua files

-- Get the addon directory path
local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'



-- Use Lua mode for persistence
local persistence_mode = 'lua'

-- Player server ID storage - will be set once player is available
local cached_player_server_id = nil

-- Helper function to get and cache player server ID
local function get_player_server_id()
    if cached_player_server_id then
        debug_print('Returning cached player server ID: ' .. cached_player_server_id)
        return cached_player_server_id
    end
    
    debug_print('Attempting to get player server ID...')
    local mem = AshitaCore:GetMemoryManager()
    if not mem then
        debug_print('Memory manager not available')
        return nil
    end
    
    local party = mem:GetParty()
    if not party then
        debug_print('Party manager not available')
        return nil
    end
    
    debug_print('Getting player server ID from party manager...')
    -- Get player server ID from party manager (index 0 is always the player)
    local player_server_id = party:GetMemberServerId(0)
    debug_print('Party manager GetMemberServerId(0) result: ' .. tostring(player_server_id))
    
    if player_server_id and player_server_id > 0 then
        cached_player_server_id = player_server_id
        debug_print('Player server ID cached: ' .. cached_player_server_id)
        return cached_player_server_id
    else
        debug_print('Failed to get valid player server ID from party manager')
    end
    
    return nil
end

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

-- Helper function to get table keys
local function table_keys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    return table.concat(keys, ', ')
end

-- Load state from file (Lua only)
local function load_state()
    local default_state = {
        timestamps = {},
        owned = {},
        storage_canteens = 0,
        last_canteen_time = 0,
        dynamis_d_entry_time = 0  -- Timestamp of last Dynamis [D] entry
    }
    
    -- Get player server ID for character-specific file
    local playerServerId = get_player_server_id()
    debug_print('Player server ID for loading: ' .. tostring(playerServerId))
    
    -- Only use character-specific file if we have a valid player server ID
    local settings_file
    if playerServerId then
        settings_file = addon_path .. 'data/keyring_settings_' .. playerServerId .. '.lua'
        debug_print('Loading character-specific persistence file: ' .. settings_file)
    else
        settings_file = addon_path .. 'data/keyring_settings.lua'
        debug_print('Loading generic persistence file: ' .. settings_file)
    end
    
    local file = io.open(settings_file, 'r')
    if file then
        local content = file:read('*all')
        file:close()
        
        debug_print('Found persistence file: ' .. settings_file)
        debug_print('File content length: ' .. string.len(content))
        debug_print('File content preview: ' .. string.sub(content, 1, 200) .. '...')
        
        -- Create a safe environment for loading the Lua file
        local env = {}
        local func, err = loadstring(content)
        if func then
            -- Use pcall to safely set environment (setfenv might not be available in all Lua versions)
            local success, result = pcall(function()
                if setfenv then
                    setfenv(func, env)
                end
                return func()
            end)
            debug_print('Persistence file loaded successfully')
            
            if success then
                -- Check if the function returned a table directly
                if type(result) == 'table' then
                    if result.timestamps and result.owned and 
                       type(result.timestamps) == 'table' and type(result.owned) == 'table' then
                        debug_print('State loaded successfully')
                        debug_print('Loaded timestamps: ' .. table_keys(result.timestamps))
                        debug_print('Loaded owned: ' .. table_keys(result.owned))
                        return result
                    else
                        debug_print('Invalid state structure in returned table')
                    end
                -- Check if env.state is a table
                elseif env.state and type(env.state) == 'table' then
                    if env.state.timestamps and env.state.owned and 
                       type(env.state.timestamps) == 'table' and type(env.state.owned) == 'table' then
                        debug_print('State loaded successfully')
                        return env.state
                    else
                        debug_print('Invalid state structure in env.state')
                    end
                else
                    debug_print('No valid state found in Lua file - result type: ' .. type(result) .. ', env.state type: ' .. type(env.state))
                end
            else
                debug_print('Failed to execute Lua state file: ' .. tostring(result))
            end
        else
            debug_print('Failed to load Lua state file: ' .. tostring(err))
        end
    else
        debug_print('Persistence file not found')
    end
    
    debug_print('Starting with fresh state')
    return default_state
end

-- Helper function to serialize tables for Lua file output
local function serialize_table(tbl)
    if not tbl or type(tbl) ~= 'table' then
        return '{}'
    end
    
    local parts = {}
    local seen_keys = {} -- Track seen keys to prevent duplicates
    
    for k, v in pairs(tbl) do
        local key_str = tostring(k)
        if not seen_keys[key_str] then
            seen_keys[key_str] = true
            if type(v) == 'number' then
                table.insert(parts, string.format('[%s] = %d', key_str, v))
            elseif type(v) == 'boolean' then
                table.insert(parts, string.format('[%s] = %s', key_str, tostring(v)))
            elseif type(v) == 'string' then
                table.insert(parts, string.format('[%s] = "%s"', key_str, v))
            end
        end
    end
    
    return '{' .. table.concat(parts, ', ') .. '}'
end

-- Initialize with empty state - will be loaded when player is ready
local state = {
    timestamps = {},
    owned = {},
    storage_canteens = 0,
    last_canteen_time = 0
}

local firstLoad = false

-- Module loaded
debug_print('Module loaded')

-- Create a protected state accessor to prevent corruption
local function get_state()
    if type(state) ~= 'table' then
        debug_print('State corrupted, recreating')
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

-- Now define save_state after get_state is available
local function save_state()
    local current_state = get_state()
    debug_print('Saving state')
    
    -- Get player server ID for character-specific file
    local playerServerId = get_player_server_id()
    debug_print('Player server ID for saving: ' .. tostring(playerServerId))
    
    -- Only use character-specific file if we have a valid player server ID
    local settings_file
    if playerServerId then
        settings_file = addon_path .. 'data/keyring_settings_' .. playerServerId .. '.lua'
        debug_print('Saving to character-specific file: ' .. settings_file)
    else
        settings_file = addon_path .. 'data/keyring_settings.lua'
        debug_print('Saving to generic file: ' .. settings_file)
    end
    
    -- Ensure data directory exists (without using os.execute)
    local dir = string.match(settings_file, '(.+)/[^/]*$')
    if dir then
        -- Try to create directory using Lua file operations instead of os.execute
        local test_file = dir .. '/test_write.tmp'
        local test_handle = io.open(test_file, 'w')
        if test_handle then
            test_handle:close()
            os.remove(test_file)  -- Clean up test file
        else
            debug_print('Warning: Could not write to directory: ' .. dir)
        end
    end
    
    local file = io.open(settings_file, 'w')
    if file then
        -- Use the already-validated player server ID for file header
        local characterId = playerServerId or "Unknown"
        
        -- Create Lua file with state data
        local lua_content = string.format([[
-- Keyring Addon State File
-- Generated automatically - do not edit manually
-- Character Server ID: %s

local state = {
    timestamps = %s,
    owned = %s,
    storage_canteens = %d,
    last_canteen_time = %d,
    dynamis_d_entry_time = %d
}

return state
]], 
            characterId,
            serialize_table(current_state.timestamps or {}),
            serialize_table(current_state.owned or {}),
            current_state.storage_canteens or 0,
            current_state.last_canteen_time or 0,
            current_state.dynamis_d_entry_time or 0
        )
        file:write(lua_content)
        file:close()
        debug_print('State saved')
    else
        debug_print('Failed to save state')
    end
end

-- Callback hooks
local currency_callback = nil
local zone_callback = nil

-- Flag to track if we've already requested canteen data after login/reload
local canteen_requested = false



--Init vars
local mem = AshitaCore:GetMemoryManager()
local player = mem:GetPlayer()



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
    current_state.timestamps[id] = now
    current_state.owned[id] = true
    debug_print('Key item acquired: ' .. tostring(id))

    if id == 3137 then
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
        return nil
    end
    
    local cooldown = trackedKeyItems[id]
    local ts = current_state.timestamps[id]
    if not cooldown then return nil end
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
    
    last_zone_id = zone_id
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
        -- Validate canteen generation timer - if it's too old, reset it
        if loaded_state.last_canteen_time and loaded_state.last_canteen_time > 0 then
            local currentTime = os.time()
            local timeSinceTimerStart = currentTime - loaded_state.last_canteen_time
            
            -- If the timer is more than 24 hours old, it's probably stale
            if timeSinceTimerStart > 86400 then  -- 24 hours
                debug_print('Canteen generation timer is stale, resetting')
                loaded_state.last_canteen_time = 0
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

-- Key item list (0x55) - Using Thorny's approach
ashita.events.register('packet_in', 'KeyItems_0x55', function(e)
    if e.id ~= 0x55 then return end

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
                    
                    -- Special handling for Shiny Rakaznar Plate loss
                    if ki == 3300 then
                        -- Shiny Rakaznar Plate was lost - start cooldown timer
                        local now = os.time()
                        current_state.timestamps[ki] = now  -- Set timestamp when plate is lost
                        debug_print('Shiny Rakaznar Plate lost via 0x55 packet - 20-hour cooldown started')
                        print(chat.header('Keyring'):append(chat.message('Shiny Rakaznar Plate lost - 20-hour cooldown started')))
                    end
                    
                    save_state()
                end
            end
        end
    end
end)

-- Improved zone change detection system using direct packet parsing
local last_zone_id = nil

-- Zone change detection using 0x0A packets with direct packet parsing
ashita.events.register('packet_in', 'Keyring_0x0A', function(e)
    if e.id ~= 0x0A then return end

    -- Extract zone ID directly from packet data (more reliable than player:GetZone())
    local zoneId = struct.unpack('H', e.data, 0x10+1)
    
    debug_print('Zone change packet received - zone ID: ' .. zoneId)
    
    -- Only process if zone actually changed
    if zoneId == last_zone_id then
        debug_print('Zone unchanged: ' .. zoneId)
        return
    end
    
    debug_print('Zone changed from ' .. (last_zone_id or 'unknown') .. ' to ' .. zoneId)
    last_zone_id = zoneId
    
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
        if zoneId == dynamis_zone_id then
            -- We're in a Dynamis [D] zone - record the entry
            local now = os.time()
            current_state.dynamis_d_entry_time = now
            save_state()
            
            debug_print('Dynamis [D] entry detected - zone ' .. dynamis_zone_id)
            print(chat.header('Keyring'):append(chat.message(string.format('Entered Dynamis [D] zone (ID: %d) - cooldown started', dynamis_zone_id))))
            break
        end
    end
    
    -- Check for Ra'Kaznar zone transitions (Shiny Rakaznar Plate usage detection)
    for pre_zone_id, target_zones in pairs(rakaznar_zone_transitions) do
        if last_zone_id == pre_zone_id then
            -- Check if we're transitioning from Kamihr Drifts to any Outer Ra'Kaznar zone
            for _, target_zone_id in ipairs(target_zones) do
                if zoneId == target_zone_id then
                    -- Player used their Shiny Rakaznar Plate - start cooldown timer
                    local plate_id = 3300  -- Shiny Rakaznar Plate ID
                    if current_state.owned and current_state.owned[plate_id] == true then
                        local now = os.time()
                        current_state.owned[plate_id] = false
                        current_state.timestamps[plate_id] = now  -- Set timestamp when plate is used
                        save_state()
                        
                        debug_print('Shiny Rakaznar Plate usage detected - zone transition from ' .. pre_zone_id .. ' to ' .. zoneId)
                        print(chat.header('Keyring'):append(chat.message('Shiny Rakaznar Plate used - 20-hour cooldown started')))
                    end
                    break
                end
            end
        end
    end
end)

-- Canteen storage response (0x118)
ashita.events.register('packet_in', 'Keyring_0x118', function(e)
    if e.id ~= 0x118 then return end

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
    
    debug_print('Current state in get_key_item_statuses:')
    debug_print('  timestamps: ' .. (current_state.timestamps and 'exists' or 'nil'))
    debug_print('  owned: ' .. (current_state.owned and 'exists' or 'nil'))
    if current_state.timestamps then
        for id, timestamp in pairs(current_state.timestamps) do
            debug_print('    ID ' .. id .. ': ' .. timestamp)
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

-- Flag to track if we've done the post-0x0A key item check
local post_zone_check_done = false

return handler