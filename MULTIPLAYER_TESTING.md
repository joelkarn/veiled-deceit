# Multiplayer Testing Guide

## Basic Setup

The game now has basic multiplayer support! Here's how to test it:

### Current Implementation

1. **NetworkManager** - Handles connections and player spawning
2. **Player Script** - Network-aware with input sync
3. **Main Scene** - Removed hardcoded player, added NetworkManager

### How to Test Locally (2 Players on Same Machine)

1. **Start Host Instance:**
   - Run the game normally
   - The NetworkManager will auto-host on startup (see console for confirmation)
   - Your player should spawn automatically

2. **Start Client Instance:**
   - Run a second instance of the game
   - In the Godot console or remote debugger, run:
     ```gdscript
     get_node("/root/world/NetworkManager").join_game("localhost")
     ```
   - Or modify the NetworkManager `_ready()` to auto-join instead of auto-host for testing

### How to Test on Network (2 Players on Different Machines)

1. **Host Machine:**
   - Run the game normally (auto-hosts)
   - Find your local IP address (e.g., `192.168.1.100`)
   - Share this IP with the client

2. **Client Machine:**
   - Run the game
   - In Godot console, run:
     ```gdscript
     get_node("/root/world/NetworkManager").join_game("192.168.1.100")
     ```

### Testing Checklist

- [ ] Host spawns correctly
- [ ] Client connects to host
- [ ] Both players see each other
- [ ] Movement syncs between players
- [ ] Jump works for both players
- [ ] Camera rotation works
- [ ] Remote players interpolate smoothly

### Known Issues / TODO

- **No UI yet** - Currently auto-hosts/joins via code. Need to add lobby UI
- **No enemy networking** - Enemies are disabled (removed from scene)
- **Basic input sync** - Movement and jump work, attack not fully networked yet
- **No host migration** - If host disconnects, game ends
- **No NAT traversal** - May need port forwarding for internet play

### Next Steps

1. Add lobby UI (host/join buttons)
2. Add enemy networking
3. Add attack networking
4. Improve state interpolation
5. Add client-side prediction improvements
6. Add reconnection handling

### Troubleshooting

**Connection fails:**
- Check firewall settings
- Ensure port 7777 is open
- For internet: may need port forwarding

**Players don't sync:**
- Check console for RPC errors
- Ensure both instances are running latest code
- Check NetworkManager prints in console

**Player doesn't spawn:**
- Check console for spawn messages
- Verify NetworkManager node exists in scene
- Check that player scene path is correct

