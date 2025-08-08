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
        hourglass_increment_start_time = 0  -- Timestamp when hourglass increment started (when Dynamis becomes available)
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
        
        if debug_print then debug_print('File content loaded, length: ' .. #content) end
        
        -- Try to execute the Lua code safely
        local env = {}
        local chunk, compile_error = load(content, settings_file, 't', env)
        if chunk then
            local success, result = pcall(chunk)
            if success then
                if type(result) == 'table' then
                    if result.timestamps and result.owned and 
                       type(result.timestamps) == 'table' and type(result.owned) == 'table' then
                        if debug_print then debug_print('State loaded successfully') end
                        if debug_print then debug_print('Loaded timestamps: ' .. table_keys(result.timestamps)) end
                        if debug_print then debug_print('Loaded owned: ' .. table_keys(result.owned)) end
                        return result
                    else
                        if debug_print then debug_print('Invalid state structure in returned table') end
                    end
                elseif env.state and type(env.state) == 'table' then
                    if env.state.timestamps and env.state.owned and 
                       type(env.state.timestamps) == 'table' and type(env.state.owned) == 'table' then
                        if debug_print then debug_print('State loaded successfully') end
                        return env.state
                    else
                        if debug_print then debug_print('Invalid state structure in env.state') end
                    end
                else
                    if debug_print then debug_print('No valid state found in loaded file') end
                end
            else
                if debug_print then debug_print('Error executing loaded content: ' .. tostring(result)) end
            end
        else
            if debug_print then debug_print('Error compiling loaded content: ' .. tostring(compile_error)) end
        end
    else
        if debug_print then debug_print('Could not open file: ' .. tostring(err)) end
    end
    
    if debug_print then debug_print('Using default state') end
    return default_state
end

-- Save state to character-specific persistence file
function persistence.save_state(current_state, debug_print)
    if debug_print then debug_print('Saving state') end
    
    -- Get addon path for absolute file paths
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    
    -- Get player server ID for character-specific file
    local playerServerId = get_player_server_id()
    if debug_print then debug_print('Player server ID for saving: ' .. tostring(playerServerId)) end
    
    -- Only use character-specific file if we have a valid player server ID
    local settings_file
    if playerServerId then
        settings_file = addon_path .. 'data/keyring_settings_' .. playerServerId .. '.lua'
        if debug_print then debug_print('Using character-specific settings file: ' .. settings_file) end
    else
        settings_file = addon_path .. 'data/keyring_settings.lua'
        if debug_print then debug_print('Player server ID not available, using generic settings file: ' .. settings_file) end
    end
    
    -- Prepare the content to write
    local characterId = playerServerId or 'unknown'
    local content = string.format([[-- Keyring Addon State File
-- Generated automatically - do not edit manually
-- Character Server ID: %s

local state = {
    timestamps = %s,
    owned = %s,
    storage_canteens = %d,
    last_canteen_time = %d,
    dynamis_d_entry_time = %d
}

return state]], 
            characterId,
            serialize_table(current_state.timestamps or {}),
            serialize_table(current_state.owned or {}),
            current_state.storage_canteens or 0,
            current_state.last_canteen_time or 0,
            current_state.dynamis_d_entry_time or 0
        )
    
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
            if debug_print then debug_print('Warning: Could not write to directory: ' .. dir) end
        end
    end
    
    -- Write to file
    local file, err = io.open(settings_file, 'w')
    if file then
        file:write(content)
        file:close()
        if debug_print then debug_print('State saved to: ' .. settings_file) end
        return true
    else
        if debug_print then debug_print('Error saving state: ' .. tostring(err)) end
        return false
    end
end

-- Get player server ID (public API)
function persistence.get_player_server_id()
    return get_player_server_id()
end

-- Clear cached player server ID (for testing/reloading)
function persistence.clear_player_cache()
    cached_player_server_id = nil
end

return persistence
