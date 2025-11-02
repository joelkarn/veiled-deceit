# Multiplayer Implementation Plan

## Executive Summary

**Decision: Host-Based (Authoritative Server) is the RIGHT approach for this game.**

For a 5-player, 10-minute match game, a host-based architecture is:
- ✅ **Simplest to implement** - Single source of truth prevents desync issues
- ✅ **Secure** - Host validates all game logic, reducing cheating
- ✅ **Cost-effective** - No server infrastructure needed
- ✅ **Fast to develop** - Easier than peer-to-peer or dedicated servers
- ✅ **Godot-friendly** - Built-in networking (ENet) works perfectly

**Major Changes Required:**
1. **Player Script** - Separate input collection from processing, add network sync
2. **Enemy Script** - Make damage host-authoritative, sync state
3. **Scene Structure** - Remove hardcoded player/enemy, add dynamic spawning
4. **New Network Manager** - Handle connections, player spawning, game state
5. **Input Handling** - Collect input locally, send to host for processing

**Estimated Complexity:** Medium
**Estimated Time:** 3-4 weeks for basic multiplayer
**Files to Modify:** 3 major files, 1 new file, 1 scene file

---

## Architecture Decision: Host-Based (Authoritative Server)

Your proposed approach is **excellent** for this type of game. Here's why:

### ✅ Advantages:
1. **Simplicity**: Single source of truth (host) prevents desync issues
2. **Security**: Host validates all game logic, reducing cheating
3. **Performance**: 5 players, 10-minute matches = minimal host overhead
4. **Godot-Friendly**: Godot's built-in networking (ENet) works perfectly for this
5. **Development Speed**: Easier to implement than peer-to-peer or dedicated servers
6. **Low Cost**: No server infrastructure needed initially

### ⚠️ Considerations:
- **Host advantage**: Host's machine handles all processing (but for 5 players, this is fine)
- **Host disconnection**: If host leaves, game ends (consider host migration later)
- **NAT traversal**: May need relay server for some networks (Godot can handle this via WebRTC or NAT punchthrough)
- **Network latency**: Host may have slight input lag advantage (mitigated with client-side prediction)

### 🔄 Alternative Approaches (for comparison):

#### 1. **Full Peer-to-Peer (Not Recommended)**
- ❌ Complex state synchronization
- ❌ Easy to cheat (no central authority)
- ❌ Desync issues common
- ❌ Harder to debug

#### 2. **Dedicated Server (Future Consideration)**
- ✅ Fair gameplay (no host advantage)
- ✅ Better for competitive play
- ❌ Requires server infrastructure/costs
- ❌ More complex deployment
- **Recommendation**: Start with host-based, migrate to dedicated servers later if needed

#### 3. **Hybrid (Client-Server with Host)**
- ✅ Current approach - perfect for MVP
- Can evolve into dedicated servers later

---

## Required Code Changes

Based on the current codebase analysis, here are the specific changes needed:

### 1. **Player Script (`scripts/player.gd`)** - MAJOR CHANGES

#### Current State (from code review):
- ✅ Directly reads `Input.get_vector()` and `Input.is_action_pressed()` in `_physics_process()`
- ✅ Processes mouse motion locally in `_input()` 
- ✅ Health managed locally (`health` variable)
- ✅ Melee damage calculated locally in `auto_attack()` and `_on_melee_area_body_entered()`
- ✅ Camera attached directly to player node
- ✅ Animation state managed locally

#### Needed Changes:

**1.1 Add Network Properties:**
```gdscript
# Add to top of player.gd
@export var player_id: int = 0  # Unique ID for this player
var is_local_player: bool = false  # Only true for the player controlled by this client
var is_host: bool = false  # True if this is the host instance
```

**1.2 Refactor Input Handling:**
```gdscript
# Separate input collection from processing
var input_buffer = {
    "movement": Vector2.ZERO,
    "jump": false,
    "attack": false,
    "camera_rotation": Vector2.ZERO
}

# Modify _input() to only collect input for local player
func _input(event: InputEvent) -> void:
    if not is_local_player:
        return  # Remote players don't process input
    
    if ui_manager and ui_manager.is_menu_active():
        return
    
    if event is InputEventMouseMotion:
        handle_mouse_motion(event)
        input_buffer.camera_rotation = event.relative
    
    if event.is_action_pressed("attack"):
        input_buffer.attack = true
```

**1.3 Add Network Input Sending:**
```gdscript
# Add new method to send input to host
func send_player_input() -> void:
    if not is_local_player:
        return
    
    if multiplayer.is_server():
        # We are the host, process directly
        process_player_input(input_buffer)
    else:
        # Send to host (peer_id 1)
        rpc_id(1, "process_player_input", input_buffer)
    
    # Reset one-time inputs
    input_buffer.attack = false

# Host processes input (called via RPC or directly)
@rpc("any_peer", "call_local", "reliable")
func process_player_input(input_data: Dictionary) -> void:
    if not multiplayer.is_server():
        return  # Only host processes
    
    # Process movement, jump, attack from input_data
    # Similar to current _physics_process logic
```

**1.4 Refactor Movement to Network-Aware:**
```gdscript
# Modify _physics_process to handle network state
func _physics_process(delta: float) -> void:
    if ui_manager and ui_manager.is_menu_active():
        stop_movement(delta)
        return
    
    if is_local_player:
        # Collect and send input
        input_buffer.movement = Input.get_vector("left", "right", "forward", "backward")
        input_buffer.jump = Input.is_action_just_pressed("jump")
        send_player_input()
    
    # Host will process physics and broadcast state
    # Remote clients receive and interpolate state
    
    # For now, keep existing movement code but wrap in host check
    if multiplayer.is_server() or is_local_player:
        # Process movement (existing code)
        _process_movement(delta)
```

**1.5 Add State Synchronization:**
```gdscript
# Add method to sync player state to clients
func sync_player_state() -> void:
    if not multiplayer.is_server():
        return
    
    var state = {
        "position": position,
        "rotation_y": rotation.y,
        "camera_pitch": camera_mount.rotation.x,
        "health": health,
        "velocity": velocity,
        "is_jumping": is_jumping,
        "animation": animation_player.current_animation if animation_player else "idle"
    }
    
    rpc("update_player_state", state)

# Clients receive state
@rpc("authority", "call_remote", "unreliable")
func update_player_state(state: Dictionary) -> void:
    if is_local_player:
        return  # Don't overwrite local player with server state (client prediction)
    
    # Interpolate position smoothly
    position = position.lerp(state.position, 0.3)
    rotation.y = state.rotation_y
    camera_mount.rotation.x = state.camera_pitch
    health = state.health
    velocity = state.velocity
    
    # Update animation
    if animation_player and state.animation != animation_player.current_animation:
        animation_player.play(state.animation)
```

**1.6 Network Melee Attack:**
```gdscript
# Modify _on_melee_area_body_entered to be host-authoritative
func _on_melee_area_body_entered(body: Node) -> void:
    if not auto_attack_active:
        return
    
    if already_hit.has(body):
        return
    
    already_hit[body] = true
    
    if multiplayer.is_server():
        # Host validates and processes damage
        if body.has_method("take_damage"):
            body.take_damage(AUTO_ATTACK_DAMAGE)
    else:
        # Client sends attack to host for validation
        rpc_id(1, "process_melee_hit", body.get_path())
```

**Key Points:**
- Local player: Reads input → sends to host
- Remote players: Receives state → interpolates position
- Host: Receives all inputs → processes → broadcasts state
- Melee damage must be validated on host

---

### 2. **Enemy Script (`scripts/enemy.gd`)** - MAJOR CHANGES

#### Current State (from code review):
- ✅ `take_damage()` called directly by player's melee hitbox
- ✅ Health managed locally (`health` variable)
- ✅ Dies locally when `health <= 0` (calls `queue_free()`)
- ✅ Visual flash on damage handled locally
- ✅ Simple enemy (no AI yet)

#### Needed Changes:

**2.1 Add Network Authority Check:**
```gdscript
# Modify take_damage() to be host-authoritative
func take_damage(amount: float, attacker_id: int = 0) -> void:
    if not multiplayer.is_server():
        # Clients can't process damage, only host
        return
    
    health -= amount
    print("Enemy took ", amount, " damage. Health: ", health)
    
    # Broadcast health update to all clients
    rpc("update_enemy_health", health)
    
    # Visual feedback - flash red (host)
    if mesh_instance:
        flash_damage()
    
    if health <= 0:
        die()

# Clients receive health updates
@rpc("authority", "call_remote", "reliable")
func update_enemy_health(new_health: float) -> void:
    health = new_health
    
    # Visual feedback on clients
    if mesh_instance:
        flash_damage()
    
    if health <= 0:
        die()

# Modify die() to sync destruction
func die() -> void:
    print("Enemy died!")
    
    if multiplayer.is_server():
        # Host broadcasts death to all clients
        rpc("sync_enemy_death")
        queue_free()
    else:
        # Clients just destroy locally
        queue_free()

@rpc("authority", "call_remote", "reliable")
func sync_enemy_death() -> void:
    queue_free()
```

**2.2 Enemy Spawning (Host-Only):**
```gdscript
# Option A: Enemies only exist on host (RECOMMENDED for simplicity)
# - Host spawns/manages all enemies
# - Host broadcasts enemy positions/health/animations to clients
# - Clients render enemy state but don't control them

# Option B: Synchronized enemies (more complex, better for large enemy counts)
# - All clients have enemy instances
# - Host is authoritative for enemy AI/damage
# - Clients receive state updates

# For Option A, enemies should be spawned only on host:
# In network_manager.gd or main scene:
func spawn_enemy(position: Vector3) -> void:
    if not multiplayer.is_server():
        return  # Only host spawns
    
    var enemy_scene = load("res://scenes/enemy.tscn")
    var enemy = enemy_scene.instantiate()
    enemy.position = position
    add_child(enemy)
    
    # Broadcast spawn to clients
    rpc("sync_enemy_spawn", position)
```

**Key Points:**
- Host validates and processes all enemy damage
- Host controls enemy lifecycle (spawn/death)
- Clients receive state updates and render enemies
- Damage must be validated on host to prevent cheating

---

### 3. **Game State Management** - NEW SYSTEM NEEDED

#### Create: `game_manager.gd` (or `network_manager.gd`)

```gdscript
extends Node

enum GameState { LOBBY, IN_GAME, ENDED }
var current_state = GameState.LOBBY
var players = {}  # Dictionary: peer_id -> player_data

func _ready():
    # Set up multiplayer
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    
    # If hosting
    if create_lobby():
        is_host = true
        start_hosting()

func start_hosting():
    var peer = ENetMultiplayerPeer.new()
    peer.create_server(7777, 5)  # Port 7777, max 5 players
    multiplayer.multiplayer_peer = peer
    
func join_lobby(ip: String):
    var peer = ENetMultiplayerPeer.new()
    peer.create_client(ip, 7777)
    multiplayer.multiplayer_peer = peer

# Synchronize game state (match timer, score, etc.)
@rpc("authority", "call_remote", "reliable")
func sync_game_state(state_data: Dictionary):
    # Host sends game state to all clients
    pass
```

---

### 4. **Scene Structure Changes**

#### Current: `scenes/main.tscn` (from code review):
- ❌ Hardcoded player instance at `[node name="player" parent="."]`
- ❌ Hardcoded enemy instance at `[node name="Enemy" parent="."]`
- ✅ UIManager exists
- ✅ HealthBarsLayer exists
- ✅ Static map geometry (floor, boxes)

#### Needed Changes:

**4.1 Remove Hardcoded Instances:**
- Remove `[node name="player" parent="." instance=ExtResource("5_0fqgh")]` from `main.tscn`
- Remove `[node name="Enemy" parent="." instance=ExtResource("6_enemy")]` from `main.tscn`
- Keep map geometry (floor, boxes)

**4.2 Add Spawn Points:**
```gdscript
# Create spawn points node in main.tscn
# Add a Node3D named "SpawnPoints" with 5 Marker3D children
# Or create spawn points array in network_manager.gd:

var spawn_points = [
    Vector3(-0.179691, 0, 4.3177),  # Current player position
    Vector3(5, 0, 4.3177),
    Vector3(-5, 0, 4.3177),
    Vector3(0, 0, 10),
    Vector3(0, 0, -2)
]
```

**4.3 Add Network Manager to Scene:**
- Add `NetworkManager` node to `main.tscn`
- Network manager will handle player/enemy spawning

**4.4 Dynamic Player Spawning:**
```gdscript
# In network_manager.gd or main scene script:
func spawn_player(peer_id: int) -> void:
    var player_scene = load("res://scenes/player.tscn")
    var player = player_scene.instantiate()
    player.name = "Player_" + str(peer_id)
    player.player_id = peer_id
    player.is_local_player = (peer_id == multiplayer.get_unique_id())
    player.is_host = multiplayer.is_server()
    
    # Set spawn position based on peer_id
    var spawn_index = peer_id % spawn_points.size()
    player.position = spawn_points[spawn_index]
    
    # Add to scene
    add_child(player, true)  # force_readable_name = true for networking
    
    # Broadcast spawn to other clients (host only)
    if multiplayer.is_server():
        rpc("sync_player_spawn", peer_id, spawn_points[spawn_index])

@rpc("authority", "call_remote", "reliable")
func sync_player_spawn(peer_id: int, position: Vector3) -> void:
    # Other clients spawn this player
    if peer_id == multiplayer.get_unique_id():
        return  # Don't spawn self
    
    spawn_player(peer_id)
```

**Scene Changes Summary:**
- ✅ Remove hardcoded player instance from `main.tscn`
- ✅ Remove hardcoded enemy instance from `main.tscn`
- ✅ Add spawn points (5 locations for 5 players)
- ✅ Add NetworkManager node to scene
- ✅ Spawn players dynamically via network manager
- ✅ Enemies spawned dynamically by host

---

### 5. **Input Handling** - REFACTOR

#### Current (from code review):
- ✅ `player.gd` directly reads `Input.get_vector()` in `_physics_process()`
- ✅ `Input.is_action_just_pressed("jump")` and `Input.is_action_pressed("attack")` in `_physics_process()`
- ✅ `Input.is_action_pressed("backward")` for speed multiplier
- ✅ Mouse motion handled in `_input()` directly calling `handle_mouse_motion()`
- ✅ Menu check via `ui_manager.is_menu_active()`

#### Needed Changes:

**5.1 Separate Input Collection from Processing:**
```gdscript
# Add input buffer to player.gd (covered in section 1.2)
var input_buffer = {
    "movement": Vector2.ZERO,
    "jump": false,
    "attack": false,
    "camera_rotation": Vector2.ZERO,
    "speed_multiplier": 1.0
}

# Refactor _physics_process to collect input, then send:
func _physics_process(delta: float) -> void:
    if ui_manager and ui_manager.is_menu_active():
        stop_movement(delta)
        return
    
    if is_local_player:
        # Collect input locally
        input_buffer.movement = Input.get_vector("left", "right", "forward", "backward")
        input_buffer.jump = Input.is_action_just_pressed("jump")
        input_buffer.attack = Input.is_action_pressed("attack")
        input_buffer.speed_multiplier = 0.5 if Input.is_action_pressed("backward") else 1.0
        
        # Send to host
        send_player_input()
    
    # Host processes all inputs and broadcasts state
    # Remote clients receive and interpolate
```

**5.2 Mouse Input Handling:**
```gdscript
# Modify _input() to only collect for local player:
func _input(event: InputEvent) -> void:
    if not is_local_player:
        return  # Remote players don't process input
    
    if ui_manager and ui_manager.is_menu_active():
        return
    
    if event is InputEventMouseMotion:
        # Store camera rotation delta
        input_buffer.camera_rotation = event.relative
        handle_mouse_motion(event)  # Also update local camera immediately
```

**Key Points:**
- Only local player collects input
- All input sent to host for validation
- Host processes all player inputs
- Clients receive processed state

---

### 6. **Synchronization Strategy**

#### Recommended: **Server Authoritative + Client Prediction**

**Host does:**
- Game physics (movement, collisions)
- Damage calculations
- Enemy AI
- Match timer
- Win/loss conditions

**Clients do:**
- Input collection → send to host
- Render received state (with interpolation)
- Client-side prediction (for responsiveness)

**Network Update Frequency:**
- Position/rotation: ~20-30 Hz (every 33-50ms)
- Health: Reliable, on change
- Animations: On state change

---

## Implementation Priority

### Phase 1: Foundation (Week 1-2)
1. Create `network_manager.gd` with lobby/connection
2. Make players network nodes
3. Basic input replication (movement only)

### Phase 2: Core Gameplay (Week 2-3)
4. Synchronize player positions
5. Host-authoritative enemy spawning
6. Network damage system

### Phase 3: Polish (Week 3-4)
7. Client prediction for smooth movement
8. Match timer/end conditions
9. Error handling (host disconnect, reconnection)

---

## Godot-Specific Tips

### Use Godot's Multiplayer API:
```gdscript
# Mark functions for networking
@rpc("authority", "call_remote", "reliable")
func take_damage(amount):
    pass

@rpc("any_peer", "call_local", "reliable")
func process_input(input_data):
    pass
```

### Node Path Considerations:
- Use `get_node_or_null()` for networked nodes (may not exist on all clients)
- Don't assume node paths are the same on all clients
- Use unique names based on peer_id

### Performance:
- Use `@rpc("unreliable")` for high-frequency updates (position)
- Use `@rpc("reliable")` for important events (damage, death)
- Batch updates when possible

---

## Testing Strategy

1. **Local Testing**: Run multiple instances (host + clients on same machine)
2. **LAN Testing**: Test with multiple devices on same network
3. **Internet Testing**: Test with port forwarding/NAT traversal
4. **Stress Testing**: Simulate network lag, packet loss

---

## Files That Need Changes

### Major Refactors (Based on Current Code Review):

**1. `scripts/player.gd`** - **MAJOR CHANGES REQUIRED**
- **Current State**: Direct input processing, local health management, local melee damage
- **Changes Needed**:
  - Add network properties (`player_id`, `is_local_player`, `is_host`)
  - Create `input_buffer` dictionary for input collection
  - Separate `_input()` to only collect input for local player
  - Refactor `_physics_process()` to send input to host instead of processing directly
  - Add `send_player_input()` method
  - Add `process_player_input()` RPC method (host processes)
  - Add `sync_player_state()` and `update_player_state()` RPC methods
  - Modify `_on_melee_area_body_entered()` to be host-authoritative
  - Add state interpolation for remote players
- **Complexity**: High (core gameplay logic)
- **Estimated Time**: 1-2 weeks

**2. `scripts/enemy.gd`** - **MODERATE CHANGES REQUIRED**
- **Current State**: Local damage processing, local health, local death handling
- **Changes Needed**:
  - Add host authority check to `take_damage()`
  - Add `update_enemy_health()` RPC method for clients
  - Modify `die()` to sync death to all clients
  - Add `sync_enemy_death()` RPC method
- **Complexity**: Medium (straightforward networking)
- **Estimated Time**: 2-3 days

**3. `scenes/main.tscn`** - **SCENE STRUCTURE CHANGES**
- **Current State**: Hardcoded player and enemy instances
- **Changes Needed**:
  - Remove hardcoded `[node name="player"]` instance
  - Remove hardcoded `[node name="Enemy"]` instance
  - Add `NetworkManager` node to scene
  - Create spawn points (5 locations for 5 players)
- **Complexity**: Low (mostly editor work)
- **Estimated Time**: 1-2 days

### New Files Needed:

**4. `scripts/network_manager.gd`** - **NEW FILE - HIGH PRIORITY**
- **Purpose**: Core networking logic
- **Responsibilities**:
  - Handle lobby creation/joining
  - Manage peer connections/disconnections
  - Spawn players dynamically
  - Spawn enemies (host only)
  - Sync game state (match timer, etc.)
  - Handle host migration (future)
- **Complexity**: High (foundation for multiplayer)
- **Estimated Time**: 1 week

**5. `scripts/game_state.gd`** - **NEW FILE - MEDIUM PRIORITY**
- **Purpose**: Match timer, win conditions, game state management
- **Responsibilities**:
  - 10-minute match timer
  - Win/loss conditions
  - Player scores
  - Game state synchronization
- **Complexity**: Medium
- **Estimated Time**: 3-5 days

**6. `scenes/lobby.tscn`** - **NEW FILE - MEDIUM PRIORITY**
- **Purpose**: UI for hosting/joining games
- **Responsibilities**:
  - Host game button
  - Join game (IP input)
  - Player list
  - Start game button (host only)
- **Complexity**: Medium (UI work)
- **Estimated Time**: 3-5 days

### Minor Changes:

**7. `scripts/ui_manager.gd`** - **MINOR CHANGES**
- **Current State**: Already handles menu state properly
- **Changes Needed**:
  - Potentially add network-aware menu handling (disable menus during connection)
  - May need to pause network sync when menu is open (optional)
- **Complexity**: Low
- **Estimated Time**: 1-2 days

**8. `scripts/health_bar.gd`** - **MINOR CHANGES**
- **Current State**: Already reads health from parent node dynamically
- **Changes Needed**:
  - Should work automatically since it reads parent health dynamically
  - May need to handle network updates (already covered by parent sync)
- **Complexity**: Low (mostly already compatible)
- **Estimated Time**: Minimal (verify compatibility)

### Summary:
- **Major Refactors**: 3 files
- **New Files**: 3 files
- **Minor Changes**: 2 files
- **Total Files**: 8 files
- **Estimated Total Time**: 3-4 weeks for basic multiplayer functionality

---

## Next Steps

1. **Start Small**: Get 2 players moving on the same screen first
2. **Iterate**: Add one feature at a time (movement → damage → enemies)
3. **Test Often**: Don't wait until everything is done to test multiplayer
4. **Document**: Keep track of network events/state synchronization

---

## Conclusion

**Your host-based approach is solid and recommended for this game.**

The main challenge will be refactoring the player/enemy scripts to separate local input from networked state, but Godot's multiplayer API makes this straightforward!

### Quick Answer to Your Questions:

**Q: What do you think? Would that be a good idea?**
**A: YES - Host-based authoritative server is perfect for your use case (5 players, 10 min matches).** It's simpler, more secure, and faster to implement than alternatives.

**Q: What will I need to change of the code that is already in place?**
**A: See detailed breakdown above, but in summary:**
1. **Player Script** - Separate input collection from processing, add network sync
2. **Enemy Script** - Make damage host-authoritative
3. **Main Scene** - Remove hardcoded instances, add dynamic spawning
4. **New Network Manager** - Handle connections and spawning
5. **Input Handling** - Collect locally, send to host

The good news is that your current code structure is relatively clean and will be straightforward to refactor. The health bar system already reads dynamically from parent nodes, which will work well with networked state.

**Recommendation**: Start with basic player movement sync (2 players), then add damage, then enemies. Test incrementally!

