-- Keyring Persistence Module
-- Handles all character-specific data persistence for the keyring addon

local chat = require('chat')

local persistence = {}

-- Player server ID storage - will be set once player is available
local cached_player_server_id = nil

-- Helper function to get and cache player server ID
local function get_player_server_id()
    if cached_player_server_id then
        return cached_player_server_id
    end
    
    local mem = AshitaCore:GetMemoryManager()
    if not mem then
        return nil
    end
    
    local party = mem:GetParty()
    if not party then
        return nil
    end
    
    local player_server_id = party:GetMemberServerId(0)
    if player_server_id and player_server_id > 0 then
        cached_player_server_id = player_server_id
        return cached_player_server_id
    end
    
    return nil
end

-- Helper function to get table keys as a string (for debugging)
local function table_keys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    return table.concat(keys, ', ')
end

-- Helper function to serialize a table to string representation
local function serialize_table(tbl)
    if type(tbl) ~= 'table' then
        return '{}'
    end
    
    local result = '{'
    local first = true
    for k, v in pairs(tbl) do
        if not first then
            result = result .. ', '
        end
        result = result .. '[' .. tostring(k) .. '] = ' .. tostring(v)
        first = false
    end
    result = result .. '}'
    return result
end

-- Load state from character-specific persistence file
function persistence.load_state(debug_print)
    local default_state = {
        timestamps = {},
        owned = {},
        storage_canteens = 0,
        last_canteen_time = 0,
        dynamis_d_entry_time = 0,  -- Timestamp of last Dynamis [D] entry
        hourglass_time = 0,  -- Timestamp of last hourglass use
        hourglass_increment_start_time = 0,  -- Timestamp when hourglass increment started (when Dynamis becomes available)
        hourglass_packet_timestamp = 0  -- Timestamp when hourglass time was received from 0x02A packet
    }
    
    -- Get addon path for absolute file paths
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    
    -- Get player server ID for character-specific file
    local playerServerId = get_player_server_id()
    if debug_print then debug_print('Player server ID for loading: ' .. tostring(playerServerId)) end
    
    -- Only use character-specific file if we have a valid player server ID
    local settings_file
    if playerServerId then
        settings_file = addon_path .. 'data/keyring_settings_' .. playerServerId .. '.lua'
        if debug_print then debug_print('Using character-specific settings file: ' .. settings_file) end
    else
        settings_file = addon_path .. 'data/keyring_settings.lua'
        if debug_print then debug_print('Player server ID not available, using generic settings file: ' .. settings_file) end
    end
    
    -- Try to load from file
    if debug_print then debug_print('Attempting to load from: ' .. settings_file) end
    
    -- Load the file
    local file, err = io.open(settings_file, 'r')
    if file then
        local content = file:read('*all')
        file:close()
        
        -- Try to execute the file content as Lua code
        local success, result = pcall(function()
            local chunk = loadstring(content)
            if chunk then
                return chunk()
            else
                return nil
            end
        end)
        
        if success and result and type(result) == 'table' then
            if debug_print then debug_print('Successfully loaded persistence file') end
            
            -- Merge with default state to ensure all required fields exist
            local merged_state = {}
            for k, v in pairs(default_state) do
                merged_state[k] = result[k] or v
            end
            
            -- Validate and clean up the loaded state
            if not merged_state.timestamps or type(merged_state.timestamps) ~= 'table' then
                merged_state.timestamps = {}
            end
            
            if not merged_state.owned or type(merged_state.owned) ~= 'table' then
                merged_state.owned = {}
            end
            
            -- Ensure numeric fields are numbers
            merged_state.storage_canteens = tonumber(merged_state.storage_canteens) or 0
            merged_state.last_canteen_time = tonumber(merged_state.last_canteen_time) or 0
            merged_state.dynamis_d_entry_time = tonumber(merged_state.dynamis_d_entry_time) or 0
            merged_state.hourglass_time = tonumber(merged_state.hourglass_time) or 0
            merged_state.hourglass_increment_start_time = tonumber(merged_state.hourglass_increment_start_time) or 0
            merged_state.hourglass_packet_timestamp = tonumber(merged_state.hourglass_packet_timestamp) or 0
            
            if debug_print then 
                debug_print('Loaded state keys: ' .. table_keys(merged_state))
                debug_print('Timestamps count: ' .. (merged_state.timestamps and #merged_state.timestamps or 0))
                debug_print('Owned count: ' .. (merged_state.owned and #merged_state.owned or 0))
            end
            
            return merged_state
        else
            if debug_print then debug_print('Failed to parse persistence file: ' .. tostring(err or 'unknown error')) end
        end
    else
        if debug_print then debug_print('Could not open persistence file: ' .. tostring(err)) end
    end
    
    -- Return default state if loading failed
    if debug_print then debug_print('Using default state') end
    return default_state
end

-- Save state to character-specific persistence file
function persistence.save_state(state, debug_print)
    if not state or type(state) ~= 'table' then
        if debug_print then debug_print('Invalid state provided for saving') end
        return false
    end
    
    -- Get addon path for absolute file paths
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    
    -- Ensure data directory exists
    local data_dir = addon_path .. 'data/'
    local data_dir_exists = io.open(data_dir, 'r')
    if not data_dir_exists then
        -- Try to create the data directory
        os.execute('mkdir "' .. data_dir .. '"')
        if debug_print then debug_print('Created data directory: ' .. data_dir) end
    else
        data_dir_exists:close()
    end
    
    -- Get player server ID for character-specific file
    local playerServerId = get_player_server_id()
    if debug_print then debug_print('Player server ID for saving: ' .. tostring(playerServerId)) end
    
    -- Use character-specific file if we have a valid player server ID
    local settings_file
    if playerServerId then
        settings_file = data_dir .. 'keyring_settings_' .. playerServerId .. '.lua'
        if debug_print then debug_print('Using character-specific settings file: ' .. settings_file) end
    else
        settings_file = data_dir .. 'keyring_settings.lua'
        if debug_print then debug_print('Player server ID not available, using generic settings file: ' .. settings_file) end
    end
    
    -- Prepare the state for serialization
    local state_to_save = {
        timestamps = state.timestamps or {},
        owned = state.owned or {},
        storage_canteens = tonumber(state.storage_canteens) or 0,
        last_canteen_time = tonumber(state.last_canteen_time) or 0,
        dynamis_d_entry_time = tonumber(state.dynamis_d_entry_time) or 0,
        hourglass_time = tonumber(state.hourglass_time) or 0,
        hourglass_increment_start_time = tonumber(state.hourglass_increment_start_time) or 0,
        hourglass_packet_timestamp = tonumber(state.hourglass_packet_timestamp) or 0
    }
    
    -- Create the file content
    local file_content = '-- Keyring Settings File\n'
    file_content = file_content .. '-- Generated automatically by Keyring addon\n'
    file_content = file_content .. '-- Do not edit manually\n\n'
    file_content = file_content .. 'return {\n'
    
    -- Add timestamps
    file_content = file_content .. '    timestamps = {\n'
    for id, timestamp in pairs(state_to_save.timestamps) do
        file_content = file_content .. '        [' .. tostring(id) .. '] = ' .. tostring(timestamp) .. ',\n'
    end
    file_content = file_content .. '    },\n'
    
    -- Add owned status
    file_content = file_content .. '    owned = {\n'
    for id, owned in pairs(state_to_save.owned) do
        file_content = file_content .. '        [' .. tostring(id) .. '] = ' .. tostring(owned) .. ',\n'
    end
    file_content = file_content .. '    },\n'
    
    -- Add other fields
    file_content = file_content .. '    storage_canteens = ' .. tostring(state_to_save.storage_canteens) .. ',\n'
    file_content = file_content .. '    last_canteen_time = ' .. tostring(state_to_save.last_canteen_time) .. ',\n'
    file_content = file_content .. '    dynamis_d_entry_time = ' .. tostring(state_to_save.dynamis_d_entry_time) .. ',\n'
    file_content = file_content .. '    hourglass_time = ' .. tostring(state_to_save.hourglass_time) .. ',\n'
    file_content = file_content .. '    hourglass_increment_start_time = ' .. tostring(state_to_save.hourglass_increment_start_time) .. ',\n'
    file_content = file_content .. '    hourglass_packet_timestamp = ' .. tostring(state_to_save.hourglass_packet_timestamp) .. ',\n'
    file_content = file_content .. '}\n'
    
    -- Write to file
    local file, err = io.open(settings_file, 'w')
    if file then
        file:write(file_content)
        file:close()
        
        if debug_print then 
            debug_print('Successfully saved persistence file: ' .. settings_file)
            debug_print('Saved state keys: ' .. table_keys(state_to_save))
        end
        
        return true
    else
        if debug_print then debug_print('Failed to save persistence file: ' .. tostring(err)) end
        return false
    end
end

return persistence
