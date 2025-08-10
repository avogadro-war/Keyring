# Keyring - Final Fantasy XI Key Item Cooldown Tracker

A Final Fantasy XI addon for Ashita4 that tracks key items with cooldown timers, providing real-time status updates and individual item notifications.

## Features

- **Automatic Detection**: Automatically detects when key items are acquired via packet interception
- **Real-time Tracking**: Live countdown timers for key item cooldowns
- **Individual Notifications**: Each item gets specific callouts instead of general messages
- **Zone Change Alerts**: Individual "ready for pickup" notifications when zoning
- **Special Canteen Tracking**: Advanced tracking for Mystical Canteen with storage system (1/3, 2/3, 3/3)
- **Dynamis [D] Tracking**: Automatic detection of Dynamis [D] zone entries with 60-hour cooldown tracking
- **Empty Hourglass Tracking**: Automatic detection via NPC interactions with time value tracking and status display
- **Manual Fix Command**: Recover from missed packets with manual acquisition triggers
- **Persistent State**: Remembers timestamps across game sessions
- **Modern GUI**: Clean, responsive interface with dynamic sizing
- **Toggleable Notifications**: Full control over zone change notifications

## Tracked Items

The addon currently tracks these items with their respective cooldowns:

### Key Items
- **Moglophone** (20h cooldown) - Cooldown starts when acquired
- **Mystical Canteen** (20h generation cycle) - Storage-based tracking (up to 3 canteens)
- **Shiny Rakaznar Plate** (20h cooldown) - Cooldown starts when used for teleport

### Special Cooldowns
- **Dynamis [D] Entry** (60h cooldown) - Auto-detected when entering Dynamis [D] zones:
  - Southern San d'Oria (230) → Dynamis-San d'Oria [D] (294)
  - Bastok Mines (234) → Dynamis-Bastok [D] (295)
  - Windurst Walls (239) → Dynamis-Windurst [D] (296)
  - Ru'Lude Gardens (243) → Dynamis-Jeuno [D] (297)
- **Empty Hourglass** - Time value tracked via NPC interactions with status display

## Installation

1. Download the addon files
2. Place the `Keyring` folder in your Ashita4 `addons` directory:
   ```
   Ashita4/addons/Keyring/
   ```
3. Load the addon in-game with:
   ```
   /addon load keyring
   ```

## Commands

| Command | Description |
|---------|-------------|
| `/keyring` or `/keyring gui` | Toggle the GUI window |
| `/keyring check` | Check for available key items (individual callouts) |
| `/keyring fix <item>` | Manually trigger acquisition for missed packets |
| `/keyring notify` | Toggle zone change notifications (default: on) |
| `/keyring status` | Show addon status and cooldown information |
| `/keyring hourglass <seconds>` | Manually set hourglass time for missed packets |
| `/keyring reset_hourglass` | Reset hourglass time to 0 |
| `/keyring force_hourglass <seconds>` | Force hourglass time (bypasses validation) |
| `/keyring debug` | Toggle debug messages in chat |
| `/keyring help` | Show comprehensive help information |

### Fix Command Examples
- `/keyring fix moglophone` or `/keyring fix mog`
- `/keyring fix canteen` or `/keyring fix mystical`
- `/keyring fix plate` or `/keyring fix rakaznar`

## GUI Interface

The addon provides a clean, responsive GUI with two main sections:

### Key Items Section
- **Key Item**: Name of the tracked item
- **Have?**: Whether you currently possess the item (Yes/No)
- **Time Remaining**: Current status with countdown timer

### Dynamis [D] Section
- **Status**: Whether Dynamis [D] entry is available or on cooldown
- **Time Remaining**: Countdown timer for the 60-hour cooldown
- **Last Entry**: Timestamp of the last Dynamis [D] entry

### Empty Hourglass Section
- **Status**: "Ready" (green) when hourglass time ≥ remaining Dynamis cooldown, "Not enough time" (red) otherwise
- **Time Display**: Shows the current hourglass time value in hh:mm:ss format

### Status Colors

- **Gray**: "Unknown" - No acquisition time recorded yet
- **Green**: "Available" - Item is off cooldown and can be acquired
- **Red**: Countdown timer - Shows remaining time until available
- **White**: Canteen storage count (e.g., "Available (2/3)")
- **Yellow**: Dynamis [D] section header
- **Green/Red**: Dynamis [D] availability status
- **Green/Red**: Empty Hourglass status ("Ready" / "Not enough time")

## How It Works

### Automatic Detection
The addon intercepts network packets to detect when key items are acquired, automatically recording timestamps for accurate cooldown tracking.

### Individual Notifications System
The addon provides specific, individual notifications for each key item:

#### Acquisition Notifications (Always On)
- "Moglophone acquired - 20-hour cooldown started"
- "Acquired Shiny Rakaznar Plate - cooldown will start when used"
- "Shiny Rakaznar Plate used - 20-hour cooldown started"

#### Zone Change Notifications (Toggleable)
When you zone into a new area, individual "ready for pickup" alerts:
- "Moglophone is ready for pickup"
- "Mystical Canteen is ready for pickup"
- "Shiny Rakaznar Plate is ready for pickup"

**No general notifications** - each item gets its own specific callout instead of grouped messages.

### Special Canteen Handling
The Mystical Canteen has a unique storage system where you can hold up to 3 canteens. The addon tracks this storage count and displays it alongside the availability status.

### Dynamis [D] Tracking
The addon automatically detects when you enter a Dynamis [D] zone by monitoring zone transitions from specific pre-Dynamis areas. When a valid transition is detected, it records the entry time and starts the 60-hour cooldown timer.

### Empty Hourglass Tracking
The addon tracks the time value stored in the Empty Hourglass by intercepting 0x02A packets when interacting with the Enigmatic Footprints NPC. The hourglass time is displayed in the GUI with a status indicator showing whether it's sufficient to bypass the current Dynamis [D] cooldown.

### Persistent Storage
All timestamps and state information are saved between game sessions, ensuring your tracking continues even after logging out and back in.

## File Structure

```
Keyring/
├── keyring.lua                    # Main addon file (GUI code modularized)
├── keyring_packet_handler.lua     # Packet interception and state management
├── keyring_gui.lua               # GUI rendering module
├── key_items_optimized.lua       # Auto-generated optimized key item mappings
├── tracked_key_items.lua         # Configuration of tracked items
├── key_items_reference.lua       # Full key item reference (renamed from key_items.lua)
├── data/                         # Data directory for settings
│   └── keyring_settings_[CharacterName].lua  # Character-specific persistent state files
└── README.md                     # This file
```

### Module Overview

- **`keyring.lua`**: Main addon entry point, command handling, and event registration (GUI code modularized)
- **`keyring_packet_handler.lua`**: Network packet interception and state management
- **`keyring_gui.lua`**: ImGui rendering logic and window management
- **`key_items_optimized.lua`**: Auto-generated memory-efficient key item mappings (only tracked items)
- **`tracked_key_items.lua`**: Configuration of which items to track and their cooldowns
- **`key_items_reference.lua`**: Complete key item ID to name mappings (renamed from key_items.lua)

## Requirements

- Final Fantasy XI
- Ashita4 client
- Windows operating system

## Troubleshooting

### Settings Module Error
If you encounter a settings module error on first load, the addon will automatically fall back to internal storage. This is normal for fresh installations.

### Debug Mode
Enable debug mode with `/keyring debug` to see detailed packet information and troubleshooting messages.

### Manual State Reset
If tracking becomes inaccurate, you can:

#### Fix Individual Items
Use the fix command to manually trigger acquisition for missed packets:
- `/keyring fix moglophone` - If the addon missed your Moglophone acquisition
- `/keyring fix canteen` - If canteen tracking is out of sync
- `/keyring fix plate` - If Rakaznar Plate cooldown wasn't detected

#### Complete Reset
For complete reset:
1. Unloading the addon: `/addon unload keyring`
2. Deleting the character-specific settings file: `data/keyring_settings_[YourCharacterName].lua`
3. Reloading the addon: `/addon load keyring`

**Note**: Each character has their own settings file, so you can reset tracking for one character without affecting others.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the addon.

## Credits

- **Author**: Avogadro
- **Assistance**: Thorny and Will
- **Special Thanks**: To the Ashita4 community for packet analysis and technical support

## License

This addon is provided as-is for the Final Fantasy XI community. Use at your own discretion.

## Performance & Optimization

The addon has been optimized for performance and maintainability:

- **Memory Efficiency**: Uses optimized key item mappings that only load tracked items
- **Caching**: Implements intelligent caching for storage calculations to reduce redundant computations
- **Modular Design**: Separated concerns into dedicated modules for better maintainability
- **Error Handling**: Comprehensive input validation and error handling throughout
- **Settings Management**: Unified Lua-based settings system

## Version History

- **v0.3.2**: Empty Hourglass tracking and status display improvements
  - **Empty Hourglass tracking**: Added automatic detection of hourglass time via 0x02A packet parsing
  - **Status display**: Shows "Ready" (green) when hourglass time ≥ remaining Dynamis cooldown, "Not enough time" (red) otherwise
  - **Manual hourglass commands**: Added `/keyring hourglass`, `/keyring reset_hourglass`, and `/keyring force_hourglass` commands
  - **Packet parsing fix**: Corrected 0x02A packet offset for accurate hourglass time reading
  - **GUI integration**: Added Empty Hourglass section to the GUI with time display and status indicators
  - **Debug cleanup**: Removed superfluous debug output for cleaner chat experience

- **v0.3.1**: Individual notifications and manual fix functionality
  - **Individual item notifications**: Replaced general "One or more items available" with specific per-item callouts
  - **Zone change individual alerts**: Each available item now gets its own "ready for pickup" notification
  - **Manual fix command**: Added `/keyring fix <item>` to manually trigger acquisition for missed packets
  - **Enhanced help system**: Comprehensive help with organized sections for commands, notifications, and features
  - **Improved notification control**: Cleaner distinction between always-on acquisition alerts and toggleable zone notifications
  - **Better user experience**: No more grouped notifications - each item gets specific, actionable feedback
  - **Flexible item name matching**: Fix command accepts partial names (e.g., "mog", "canteen", "plate")
  - **Enhanced command documentation**: Updated README and help with detailed examples and usage instructions

- **v0.3.1**: Performance improvements and character identification fixes
  - **Fixed player identification**: Replaced unreliable player name retrieval with server ID-based character identification
  - **Improved persistence loading**: More reliable character-specific file loading using server IDs instead of player names
  - **Performance optimization**: Removed blocking delay loops that caused addon load performance issues
  - **Enhanced error handling**: Better handling of player data retrieval with proper fallback mechanisms
  - **Simplified character caching**: Streamlined player server ID caching system for faster access
  - **Fixed function definition order**: Resolved runtime errors caused by function definition order issues
  - **Improved debug output**: Enhanced debugging information for troubleshooting character identification issues
  - **Better file naming**: Character-specific files now use server IDs for more reliable identification

- **v0.3**: Enhanced Shiny Rakaznar Plate tracking and improved detection systems
  - **Fixed Shiny Rakaznar Plate cooldown logic**: Cooldown now starts when the plate is used/lost, not when acquired
  - **Dual detection system**: Both zone transition detection (0x0A packets) and key item loss detection (0x55 packets) for Shiny Rakaznar Plate
  - **Improved zone transition detection**: More reliable detection of Ra'Kaznar zone transitions from Kamihr Drifts to Outer Ra'Kaznar zones
  - **Enhanced packet handling**: Better handling of key item acquisition and loss events
  - **Redundant safety systems**: Multiple detection methods ensure accurate cooldown tracking even if one method fails
  - **Updated persistence system**: Improved state management for accurate timestamp tracking
  - **Character-specific persistence**: Each character now has their own settings file, preventing data conflicts between characters
  - **Better user feedback**: Clear messages when Shiny Rakaznar Plate is acquired, used, or lost
  - **Dynamis [D] tracking system**: Automatic detection of Dynamis [D] zone entries with 60-hour cooldown tracking
  - **Zone transition monitoring**: Monitors transitions from pre-Dynamis zones to Dynamis [D] zones for accurate entry detection

- **v0.2**: Performance and code organization improvements
  - Modular architecture with separated GUI and settings management
  - Memory optimization with targeted key item mappings
  - Caching system for storage calculations
  - Enhanced error handling and input validation
  - Centralized constants and configuration
  - Improved documentation and code structure

- **v0.1**: Initial release with core tracking functionality
  - Basic key item cooldown tracking
  - GUI interface
  - Packet-based detection
  - Zone change notifications
  - Special canteen handling
  - Persistent state storage 