-- Optimized Key Items Mapping
-- Automatically generates mapping from tracked_key_items and key_items reference
-- This reduces memory usage from ~3235 entries to just the needed ones

-- Load the tracked items configuration
local trackedKeyItems = require('tracked_key_items')

-- Try to load the key items reference (prefer the smaller reference file)
local key_items_reference = {}
local success, ref_items = pcall(require, 'key_items_reference')
if success and ref_items then
    key_items_reference = ref_items.idToName or {}
else
    -- Fallback to full key_items.lua if reference not available
    local success2, full_key_items = pcall(require, 'key_items')
    if success2 and full_key_items then
        key_items_reference = full_key_items.idToName or {}
    else
        -- Final fallback minimal mapping for the tracked items
        key_items_reference = {
            [3212] = "Moglophone",
            [3137] = "Mystical Canteen", 
            [3300] = "Shiny Rakaznar Plate",
        }
    end
end

-- Auto-generate the optimized mappings
local key_items = {
    nameToId = {},
    idToName = {}
}

-- Build the optimized mappings from tracked items
for id, _ in pairs(trackedKeyItems) do
    local name = key_items_reference[id] or ("Unknown ID: " .. tostring(id))
    key_items.idToName[id] = name
    key_items.nameToId[name] = id
end

-- Fallback function for unknown items
function key_items.get_name(id)
    return key_items.idToName[id] or ("Unknown ID: " .. tostring(id))
end

function key_items.get_id(name)
    return key_items.nameToId[name]
end

return key_items