-- Keyring Persistence Module
-- Handles all character-specific data persistence for the keyring addon

local chat = require('chat')

local persistence = {}

-- Player server ID storage - will be set once player is available
local cached_player_server_id = nil

-- Backup system variables
local last_backup_time = 0
local BACKUP_INTERVAL = 3600 -- 1 hour in seconds
local MAX_BACKUPS = 24 -- Keep 24 hourly backups (1 day worth)

-- Helper function to get and cache player server ID
local function get_player_server_id()
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
        -- Only cache if it's different from the current cached value
        if cached_player_server_id ~= player_server_id then
            cached_player_server_id = player_server_id
        end
        return cached_player_server_id
    end
    
    return nil
end

-- Function to clear cached player server ID (for character changes)
function persistence.clear_cached_player_id()
    cached_player_server_id = nil
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

-- Helper function to create backup filename with timestamp
local function create_backup_filename(player_server_id)
    local timestamp = os.date('%Y%m%d_%H%M%S')
    return 'keyring_backup_' .. player_server_id .. '_' .. timestamp .. '.lua'
end

-- Helper function to clean old backups
local function clean_old_backups(addon_path, debug_print)
    local backup_dir = addon_path .. 'data/backups/'
    
    -- Get list of backup files
    local backup_files = {}
    local handle = io.popen('dir "' .. backup_dir .. 'keyring_backup_*.lua" /b 2>nul')
    if handle then
        for file in handle:lines() do
            table.insert(backup_files, file)
        end
        handle:close()
    end
    
    -- Sort files by modification time (oldest first)
    table.sort(backup_files)
    
    -- Remove oldest files if we have too many
    local files_to_remove = #backup_files - MAX_BACKUPS
    if files_to_remove > 0 then
        for i = 1, files_to_remove do
            local file_to_remove = backup_dir .. backup_files[i]
            os.remove(file_to_remove)
            if debug_print then
                debug_print('Removed old backup: ' .. backup_files[i])
            end
        end
    end
end

-- Function to create backup of current persistence file
local function create_backup(settings_file, debug_print)
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    local backup_dir = addon_path .. 'data/backups/'
    
    -- Create backup directory if it doesn't exist
    local backup_dir_exists = io.open(backup_dir, 'r')
    if not backup_dir_exists then
        -- Try to create the directory by writing a temporary file and then removing it
        local temp_file = backup_dir .. 'temp.txt'
        local temp_handle = io.open(temp_file, 'w')
        if temp_handle then
            temp_handle:close()
            os.remove(temp_file)
            if debug_print then debug_print('Created backup directory: ' .. backup_dir) end
        else
            if debug_print then debug_print('Failed to create backup directory: ' .. backup_dir) end
            return false
        end
    else
        backup_dir_exists:close()
    end
    
    -- Get player server ID for backup filename
    local playerServerId = get_player_server_id()
    if not playerServerId then
        if debug_print then debug_print('Cannot create backup: Player server ID not available') end
        return false
    end
    
    -- Check if source file exists
    local source_file = io.open(settings_file, 'r')
    if not source_file then
        if debug_print then debug_print('Cannot create backup: Source file does not exist') end
        return false
    end
    source_file:close()
    
    -- Create backup filename
    local backup_filename = create_backup_filename(playerServerId)
    local backup_file_path = backup_dir .. backup_filename
    
    -- Copy the file using Lua file operations
    local source_file = io.open(settings_file, 'rb')
    local dest_file = io.open(backup_file_path, 'wb')
    
    if source_file and dest_file then
        local content = source_file:read('*all')
        dest_file:write(content)
        source_file:close()
        dest_file:close()
        
        if debug_print then debug_print('Created backup: ' .. backup_filename) end
        
        -- Clean old backups
        clean_old_backups(addon_path, debug_print)
        
        return true
    else
        if source_file then source_file:close() end
        if dest_file then dest_file:close() end
        if debug_print then debug_print('Failed to create backup: ' .. backup_filename) end
        return false
    end
end

-- Function to check if backup is needed and create it
local function check_and_create_backup(settings_file, debug_print)
    local current_time = os.time()
    
    -- Check if it's time for a backup
    if current_time - last_backup_time >= BACKUP_INTERVAL then
        if create_backup(settings_file, debug_print) then
            last_backup_time = current_time
        end
    end
end

-- Load state from character-specific persistence file
function persistence.load_state(debug_print)
    local default_state = {
        timestamps = {},
        owned = {},
        storage_canteens = 0,
        last_canteen_time = 0,
        dynamis_d_entry_time = 0,  -- Timestamp of last Dynamis [D] entry
        dynamis_projected_ready_time = 0,  -- Calculated time when Dynamis [D] becomes available (entry_time + 60 hours)
        hourglass_time = 0,  -- Time value stored in the hourglass (duration in seconds)
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
            merged_state.dynamis_projected_ready_time = tonumber(merged_state.dynamis_projected_ready_time) or 0
            merged_state.hourglass_time = tonumber(merged_state.hourglass_time) or 0
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
        -- Try to create the directory by writing a temporary file and then removing it
        local temp_file = data_dir .. 'temp.txt'
        local temp_handle = io.open(temp_file, 'w')
        if temp_handle then
            temp_handle:close()
            os.remove(temp_file)
            if debug_print then debug_print('Created data directory: ' .. data_dir) end
        else
            if debug_print then debug_print('Failed to create data directory: ' .. data_dir) end
            return false
        end
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
        dynamis_projected_ready_time = tonumber(state.dynamis_projected_ready_time) or 0,
        hourglass_time = tonumber(state.hourglass_time) or 0,
        hourglass_packet_timestamp = tonumber(state.hourglass_packet_timestamp) or 0
    }
    
    -- Create the file content using table.concat for better performance
    local content_parts = {
        '-- Keyring Settings File\n',
        '-- Generated automatically by Keyring addon\n',
        '-- Do not edit manually\n\n',
        'return {\n'
    }
    
    -- Add timestamps
    table.insert(content_parts, '    timestamps = {\n')
    for id, timestamp in pairs(state_to_save.timestamps) do
        table.insert(content_parts, '        [' .. tostring(id) .. '] = ' .. tostring(timestamp) .. ',\n')
    end
    table.insert(content_parts, '    },\n')
    
    -- Add owned status
    table.insert(content_parts, '    owned = {\n')
    for id, owned in pairs(state_to_save.owned) do
        table.insert(content_parts, '        [' .. tostring(id) .. '] = ' .. tostring(owned) .. ',\n')
    end
    table.insert(content_parts, '    },\n')
    
    -- Add other fields
    table.insert(content_parts, '    storage_canteens = ' .. tostring(state_to_save.storage_canteens) .. ',\n')
    table.insert(content_parts, '    last_canteen_time = ' .. tostring(state_to_save.last_canteen_time) .. ',\n')
    table.insert(content_parts, '    dynamis_d_entry_time = ' .. tostring(state_to_save.dynamis_d_entry_time) .. ',\n')
    table.insert(content_parts, '    dynamis_projected_ready_time = ' .. tostring(state_to_save.dynamis_projected_ready_time) .. ',\n')
    table.insert(content_parts, '    hourglass_time = ' .. tostring(state_to_save.hourglass_time) .. ',\n')
    table.insert(content_parts, '    hourglass_packet_timestamp = ' .. tostring(state_to_save.hourglass_packet_timestamp) .. ',\n')
    table.insert(content_parts, '}\n')
    
    local file_content = table.concat(content_parts)
    
    -- Write to file
    local file, err = io.open(settings_file, 'w')
    if file then
        file:write(file_content)
        file:close()
        
        -- Check if backup is needed after successful save
        check_and_create_backup(settings_file, debug_print)
        
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

-- Function to manually create a backup (for user commands)
function persistence.create_manual_backup(debug_print)
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    local playerServerId = get_player_server_id()
    
    if not playerServerId then
        if debug_print then debug_print('Cannot create manual backup: Player server ID not available') end
        return false
    end
    
    local settings_file = addon_path .. 'data/keyring_settings_' .. playerServerId .. '.lua'
    return create_backup(settings_file, debug_print)
end

-- Function to list available backups
function persistence.list_backups(debug_print)
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    local backup_dir = addon_path .. 'data/backups/'
    local playerServerId = get_player_server_id()
    
    if not playerServerId then
        if debug_print then debug_print('Cannot list backups: Player server ID not available') end
        return {}
    end
    
    local backups = {}
    -- Use Lua file operations instead of dir command
    local pattern = 'keyring_backup_' .. playerServerId .. '_'
    local handle = io.popen('dir "' .. backup_dir .. '" /b 2>nul')
    if handle then
        for file in handle:lines() do
            if file:find(pattern, 1, true) then
                table.insert(backups, file)
            end
        end
        handle:close()
    end
    
    -- Sort by modification time (newest first)
    table.sort(backups, function(a, b) return a > b end)
    
    if debug_print then
        debug_print('Found ' .. #backups .. ' backups for player ' .. playerServerId)
        for i, backup in ipairs(backups) do
            debug_print('  ' .. i .. '. ' .. backup)
        end
    end
    
    return backups
end

-- Function to restore from a backup
function persistence.restore_from_backup(backup_filename, debug_print)
    local addon_path = AshitaCore:GetInstallPath() .. '/addons/Keyring/'
    local backup_dir = addon_path .. 'data/backups/'
    local playerServerId = get_player_server_id()
    
    if not playerServerId then
        if debug_print then debug_print('Cannot restore backup: Player server ID not available') end
        return false
    end
    
    local backup_file_path = backup_dir .. backup_filename
    local settings_file = addon_path .. 'data/keyring_settings_' .. playerServerId .. '.lua'
    
    -- Check if backup file exists
    local backup_exists = io.open(backup_file_path, 'r')
    if not backup_exists then
        if debug_print then debug_print('Backup file does not exist: ' .. backup_filename) end
        return false
    end
    backup_exists:close()
    
    -- Create a backup of current file before restoring
    if debug_print then debug_print('Creating backup of current file before restore...') end
    create_backup(settings_file, debug_print)
    
    -- Copy backup to current settings file using Lua file operations
    local source_file = io.open(backup_file_path, 'rb')
    local dest_file = io.open(settings_file, 'wb')
    
    if source_file and dest_file then
        local content = source_file:read('*all')
        dest_file:write(content)
        source_file:close()
        dest_file:close()
        
        if debug_print then debug_print('Successfully restored from backup: ' .. backup_filename) end
        return true
    else
        if source_file then source_file:close() end
        if dest_file then dest_file:close() end
        if debug_print then debug_print('Failed to restore from backup: ' .. backup_filename) end
        return false
    end
end

return persistence
