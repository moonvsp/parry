local Players = game:GetService("Players")
local Workspace = workspace or game:GetService("Workspace")
local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local INSTANCE_KEY = "__VV_AUTOPARRY_MATCHA_STATE"
local old = _G and _G[INSTANCE_KEY]
if old then
    old.running = false
    if type(old.cleanup) == "function" then pcall(old.cleanup) end
end
local script_state = { running = true, drawings = {} }
if _G then _G[INSTANCE_KEY] = script_state end

-- CONFIGURATION
local USER = (_G and _G.VV_AUTOPARRY) or {}
local function C(key, default)
    local v = USER[key]
    if v ~= nil then return v end
    return default
end

local LOCK_KEY = C("LOCK_KEY", "G")
local PING_MS = C("PING_MS", 0)
local AUTO_PING = C("AUTO_PING", true)
local SHOW_RADIUS = C("SHOW_RADIUS", true)
local RADIUS_SIZE = C("RADIUS_SIZE", nil)

-- IMPROVED TIMING VALUES
local PARRY_WINDOW_START = 0.05  -- Start parry slightly earlier
local PARRY_WINDOW_END = 0.35    -- Longer parry window
local PARRY_COOLDOWN = 0.25       -- Reduced cooldown
local ACTION_LOCKOUT = 0.20       -- Reduced lockout
local DODGE_WINDOW = 0.25
local DODGE_COOLDOWN = 0.35

-- Better prediction
local PREDICTION_FACTOR = 1.2
local PING_BUFFER = 15 -- ms buffer for ping

local DEFAULT_RANGE = 14
local RANGE = DEFAULT_RANGE
local RANGE_SQ = RANGE * RANGE
local LivingFolderName = "Living"

local CLASH_EFFECT = "CanClash"
local SIGNAL_EFFECT = "AttackingSignal"
local ATTACK_EFFECT = "Attacking"

-- IMPROVED MOVE DETECTION
local MOVES = {
    ["Heavy Kick"] = { action = "dodge", windup = 0.555, dodge_dir = "back", priority = 1 },
    ["False Cutter"] = { action = "dodge", windup = 0.735, dodge_dir = "back", priority = 1 },
    ["Overhead Strike"] = { action = "dodge", windup = 1.10, dodge_dir = "back", priority = 1 },
    ["Skyscraper"] = { action = "dodge", windup = 0.80, dodge_dir = "back", priority = 1 },
    ["GelumAOE"] = { action = "dodge", windup = 2.00, dodge_dir = "back", priority = 2 },
    ["GelumMeteor"] = { action = "block", windup = 0.552, hold = 0.50, priority = 2 },
    ["Cyclone"] = { action = "block", windup = 0.670, hold = 0.60, priority = 2 },
    ["Running Attack"] = { action = "parry", windup = 0.670, priority = 3 },
    ["ScorpionHollow_PoisonBreath"] = { action = "block", windup = 1.382, hold = 0.55, priority = 2 },
    ["Roar"] = { action = "block", windup = 0.30, hold = 0.80, priority = 2 },
    ["ScorpionPoison"] = { action = "block", windup = 0.25, hold = 0.70, priority = 2 },
    ["GiantDragonfly_Slam"] = { action = "block", windup = 0.753, hold = 0.45, priority = 2 },
    ["GiantDragonfly_Tailwhip"] = { action = "block", windup = 1.457, hold = 0.45, priority = 2 },
    ["GiantDragonfly_Grab"] = { action = "dodge", windup = 1.493, dodge_dir = "back", priority = 1 },
}

local v3 = Vector3.new
local color_green = Color3.new(0, 1, 0)
local color_red = Color3.new(1, 0, 0)
local color_cyan = Color3.new(0, 1, 1)
local segs = 16

-- VISUALS
local function track(o) script_state.drawings[#script_state.drawings + 1] = o; return o end
local function remove_drawing(o)
    if not o then return end
    pcall(function() o.Visible = false end)
    if type(o.Remove) == "function" then pcall(function() o:Remove() end)
    elseif type(o.Destroy) == "function" then pcall(function() o:Destroy() end) end
end

script_state.cleanup = function()
    for i = 1, #script_state.drawings do remove_drawing(script_state.drawings[i]) end
    script_state.drawings = {}
end

local circle = {}
local enemy_label = nil
if SHOW_RADIUS then
    for i = 1, segs do
        local l = track(Drawing.new("Line"))
        l.Thickness = 2
        l.Visible = false
        circle[i] = l
    end
    enemy_label = track(Drawing.new("Text"))
    enemy_label.Outline = true
    enemy_label.Center = true
    enemy_label.Size = 14
    enemy_label.Color = color_red
    enemy_label.Visible = false
end

-- UTILITY FUNCTIONS
local function safe(fn, fb)
    local ok, r = pcall(fn)
    if ok then return r end
    return fb
end

local function get_hrp(m)
    return m and m:FindFirstChild("HumanoidRootPart")
end

local function my_char()
    return LP and LP.Character
end

local function my_root()
    return get_hrp(my_char())
end

local function living_folder()
    return Workspace and Workspace:FindFirstChild(LivingFolderName)
end

local function status_folder(m)
    return m and m:FindFirstChild("Status")
end

local function cooldowns_folder(m)
    return m and m:FindFirstChild("Cooldowns")
end

local function has_effect(m, name)
    local s = status_folder(m)
    return s ~= nil and s:FindFirstChild(name) ~= nil
end

local function self_has_effect(name)
    return has_effect(my_char(), name)
end

local function enemy_attacking(m)
    return has_effect(m, ATTACK_EFFECT) or has_effect(m, "AttackingCanBlock") or has_effect(m, SIGNAL_EFFECT)
end

-- IMPROVED PING DETECTION
local ping_raw_ms = -1
local ping_smooth_ms = 50
local ping_initialized = false

local function update_ping()
    local p = safe(function() return LP:GetNetworkPing() end)
    if type(p) == "number" and p > 0 then
        ping_raw_ms = p * 1000
        if not ping_initialized then
            ping_smooth_ms = ping_raw_ms
            ping_initialized = true
        else
            ping_smooth_ms = ping_smooth_ms * 0.7 + ping_raw_ms * 0.3
        end
    end
end

local function get_ping_lead()
    if AUTO_PING and ping_initialized then
        return (ping_smooth_ms + PING_BUFFER) / 1000
    end
    return PING_MS / 1000
end

-- IMPROVED TARGETING
local function is_enemy(m)
    if not m or not m.Parent then return false end
    if m == my_char() then return false end
    if m.Name == LP.Name then return false end
    return get_hrp(m) ~= nil
end

local function dist_sq(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return dx * dx + dy * dy + dz * dz
end

local function candidate_targets()
    local list, seen = {}, {}
    local folder = living_folder()
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if not seen[m] then
                seen[m] = true
                list[#list + 1] = m
            end
        end
    end
    for _, pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        if ch and ch ~= my_char() and not seen[ch] then
            seen[ch] = true
            list[#list + 1] = ch
        end
    end
    return list
end

local function closest_to_cursor()
    local mr = my_root()
    if not mr then return nil end
    local mx, my = Mouse.X, Mouse.Y
    local closest_screen, closest_dist = nil, math.huge
    
    for _, m in ipairs(candidate_targets()) do
        if is_enemy(m) then
            local r = get_hrp(m)
            if r then
                local sp, on = Camera:WorldToScreenPoint(r.Position)
                if on then
                    local dx, dy = sp.X - mx, sp.Y - my
                    local dist = dx * dx + dy * dy
                    if dist < closest_dist then
                        closest_dist = dist
                        closest_screen = m
                    end
                end
            end
        end
    end
    return closest_screen
end

-- IMPROVED PARRY SYSTEM
local blocking = false
local parry_busy = false
local last_parry_time = 0
local dodge_busy = false
local last_dodge_time = 0
local last_action_time = 0

local function set_block(s)
    if s == blocking then return end
    blocking = s
    if s then
        safe(function() mousepress(2) end)
    else
        safe(function() mouserelease(2) end)
    end
end

local function tap_parry(reason)
    local now = tick()
    if parry_busy then return false end
    if now - last_parry_time < PARRY_COOLDOWN then return false end
    
    parry_busy = true
    last_parry_time = now
    last_action_time = now
    
    task.spawn(function()
        if not script_state.running then
            parry_busy = false
            return
        end
        
        -- Hold RMB for parry
        set_block(true)
        task.wait(PARRY_WINDOW_END)
        set_block(false)
        
        parry_busy = false
    end)
    return true
end

local function tap_dodge(reason, direction)
    local now = tick()
    if dodge_busy then return false end
    if now - last_dodge_time < DODGE_COOLDOWN then return false end
    
    dodge_busy = true
    last_dodge_time = now
    last_action_time = now
    
    task.spawn(function()
        if not script_state.running then
            dodge_busy = false
            return
        end
        
        local dir_key = 0x53 -- S key for back dodge
        if direction == "left" then dir_key = 0x41
        elseif direction == "right" then dir_key = 0x44
        elseif direction == "forward" then dir_key = 0x57 end
        
        safe(function() keypress(dir_key) end)
        safe(function() keypress(0x51) end) -- Q key
        task.wait(DODGE_WINDOW)
        safe(function() keyrelease(0x51) end)
        safe(function() keyrelease(dir_key) end)
        
        dodge_busy = false
    end)
    return true
end

-- IMPROVED MOVE DETECTION AND RESPONSE
local move_history = {}
local last_attack_time = 0
local attack_buffer = {}

local function should_parry_attack(move_name, enemy)
    -- Check if we're in range
    local mr = my_root()
    local er = get_hrp(enemy)
    if not mr or not er then return false end
    
    if dist_sq(er.Position, mr.Position) > RANGE_SQ then
        return false
    end
    
    -- Check if enemy is actually attacking
    if not enemy_attacking(enemy) then
        return false
    end
    
    return true
end

local function predict_parry_timing(enemy, move_info)
    local now = tick()
    local ping_lead = get_ping_lead()
    local windup = move_info.windup
    
    -- Add prediction for ping
    local predicted_time = now + (windup * PREDICTION_FACTOR) - ping_lead
    
    -- Clamp to reasonable values
    predicted_time = math.max(now + 0.05, math.min(now + 0.8, predicted_time))
    
    return predicted_time
end

-- VISUAL DEBUGGING
local function draw_visuals(mr, tr, target, mode)
    if not SHOW_RADIUS then return end
    
    local step = 6.283185307179586 / segs
    local col = (mode == "timed" and color_cyan) or (target and color_green or color_red)
    local cx, cy, cz = mr.Position.X, mr.Position.Y - 3, mr.Position.Z
    
    for i = 0, segs do
        local a = i * step
        local sp, on = Camera:WorldToScreenPoint(v3(cx + math.cos(a) * RANGE, cy, cz + math.sin(a) * RANGE))
        if i > 0 and circle[i] then
            local prev_sp, prev_on = Camera:WorldToScreenPoint(v3(cx + math.cos((i - 1) * step) * RANGE, cy, cz + math.sin((i - 1) * step) * RANGE))
            if on and prev_on then
                circle[i].From = Vector2.new(prev_sp.X, prev_sp.Y)
                circle[i].To = Vector2.new(sp.X, sp.Y)
                circle[i].Color = col
                circle[i].Visible = true
            else
                circle[i].Visible = false
            end
        end
    end
    
    if target and tr and enemy_label then
        local lp, on = Camera:WorldToScreenPoint(tr.Position + v3(0, 4, 0))
        if on then
            enemy_label.Text = target.Name
            enemy_label.Position = Vector2.new(lp.X, lp.Y)
            enemy_label.Visible = true
        else
            enemy_label.Visible = false
        end
    elseif enemy_label then
        enemy_label.Visible = false
    end
end

-- MAIN LOOP
local Camera = workspace.CurrentCamera
local target = nil
local last_lock = false
local last_frame_time = tick()

while script_state.running do
    local delta_time = RunService.Heartbeat:Wait()
    local now = tick()
    last_frame_time = now
    
    update_ping()
    
    -- Toggle lock-on with key
    local lock_now = UserInputService:IsKeyDown(Enum.KeyCode[LOCK_KEY] or Enum.KeyCode.C)
    if lock_now and not last_lock then
        if target then
            target = nil
            set_block(false)
        else
            target = closest_to_cursor()
        end
    end
    last_lock = lock_now
    
    -- Update range if using custom radius
    if RADIUS_SIZE and RADIUS_SIZE > 0 then
        RANGE = RADIUS_SIZE
        RANGE_SQ = RANGE * RANGE
    end
    
    local mr = my_root()
    if not mr or not target or not target.Parent or not is_enemy(target) then
        if target then target = nil end
        set_block(false)
        if SHOW_RADIUS then
            for i = 1, segs do circle[i].Visible = false end
            if enemy_label then enemy_label.Visible = false end
        end
    else
        local er = get_hrp(target)
        if er then
            local in_range = dist_sq(er.Position, mr.Position) <= RANGE_SQ
            
            -- Check for enemy attacks
            local attacking = enemy_attacking(target)
            local clash = has_effect(target, CLASH_EFFECT)
            
            if in_range and attacking and not parry_busy and not dodge_busy then
                local parried = false
                
                -- Priority 1: Clash parry (instant response)
                if clash and (now - last_action_time) > 0.1 then
                    if tap_parry("clash") then
                        parried = true
                    end
                end
                
                -- Priority 2: Check for known moves
                if not parried then
                    for move_name, move_info in pairs(MOVES) do
                        if has_effect(target, move_name) then
                            if should_parry_attack(move_name, target) then
                                local predicted_time = predict_parry_timing(target, move_info)
                                local delay = predicted_time - now
                                
                                if delay > 0 and delay < 0.5 then
                                    task.wait(delay * 0.8) -- Slight early parry for safety
                                    if move_info.action == "parry" then
                                        tap_parry(move_name)
                                    elseif move_info.action == "dodge" then
                                        tap_dodge(move_name, move_info.dodge_dir or "back")
                                    end
                                    parried = true
                                    break
                                end
                            end
                        end
                    end
                end
                
                -- Priority 3: Generic attack detection (backup)
                if not parried and (now - last_attack_time) > 0.3 then
                    -- Detect attack startup by checking for effect changes
                    local effect_found = false
                    local status = status_folder(target)
                    if status then
                        for _, effect in ipairs(status:GetChildren()) do
                            local effect_name = effect.Name
                            if effect_name:find("Attack") or effect_name:find("Swing") or effect_name:find("Cast") then
                                effect_found = true
                                break
                            end
                        end
                    end
                    
                    if effect_found then
                        -- Use a generic parry timing
                        task.wait(0.15)
                        tap_parry("generic")
                        last_attack_time = now
                    end
                end
            end
            
            -- Draw visuals
            if SHOW_RADIUS then
                draw_visuals(mr, er, target, (parry_busic or dodge_busy) and "timed" or nil)
            end
        end
    end
end

-- Cleanup
set_block(false)
if SHOW_RADIUS then
    for i = 1, segs do circle[i].Visible = false end
    if enemy_label then enemy_label.Visible = false end
end
script_state.cleanup()
if _G and _G[INSTANCE_KEY] == script_state then _G[INSTANCE_KEY] = nil end
