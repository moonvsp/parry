_G.VV_AUTOPARRY = {
    LOCK_KEY    = "G",
    PING_MS     = 0,
    AUTO_PING   = true,
    SHOW_RADIUS = true,
    RADIUS_SIZE = nil,
}

-- Use this fixed URL instead (I'll provide the complete fixed script)
-- You need to upload this fixed version to your own raw GitHub URL

local Players = game:GetService("Players")
local Workspace = workspace or game:GetService("Workspace")
local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInputManager")

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

-- FIXED TIMING VALUES (more reliable)
local PARRY_HOLD_TIME = 0.25      -- How long to hold parry
local PARRY_COOLDOWN = 0.20       -- Faster cooldown
local PARRY_WINDOW = 0.30         -- Parry active window
local CLASH_PARRY_WINDOW = 0.15   -- Faster clash response

local DEFAULT_RANGE = 14
local RANGE = DEFAULT_RANGE
local RANGE_SQ = RANGE * RANGE
local LivingFolderName = "Living"

local CLASH_EFFECT = "CanClash"
local SIGNAL_EFFECT = "AttackingSignal"
local ATTACK_EFFECT = "Attacking"

-- MOVES database
local MOVES = {
    ["Heavy Kick"] = { action = "dodge", windup = 0.555, dodge_dir = "back" },
    ["False Cutter"] = { action = "dodge", windup = 0.735, dodge_dir = "back" },
    ["Overhead Strike"] = { action = "dodge", windup = 1.10, dodge_dir = "back" },
    ["Skyscraper"] = { action = "dodge", windup = 0.80, dodge_dir = "back" },
    ["GelumAOE"] = { action = "dodge", windup = 2.00, dodge_dir = "back" },
    ["GelumMeteor"] = { action = "block", windup = 0.552, hold = 0.50 },
    ["Cyclone"] = { action = "block", windup = 0.670, hold = 0.60 },
    ["Running Attack"] = { action = "parry", windup = 0.670 },
    ["ScorpionHollow_PoisonBreath"] = { action = "block", windup = 1.382, hold = 0.55 },
    ["Roar"] = { action = "block", windup = 0.30, hold = 0.80 },
    ["ScorpionPoison"] = { action = "block", windup = 0.25, hold = 0.70 },
    ["GiantDragonfly_Slam"] = { action = "block", windup = 0.753, hold = 0.45 },
    ["GiantDragonfly_Tailwhip"] = { action = "block", windup = 1.457, hold = 0.45 },
    ["GiantDragonfly_Grab"] = { action = "dodge", windup = 1.493, dodge_dir = "back" },
}

local v3 = Vector3.new
local color_green = Color3.new(0, 1, 0)
local color_red = Color3.new(1, 0, 0)
local color_cyan = Color3.new(0, 1, 1)
local segs = 16
local Camera = workspace.CurrentCamera

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

local function has_effect(m, name)
    local s = status_folder(m)
    return s ~= nil and s:FindFirstChild(name) ~= nil
end

local function enemy_attacking(m)
    return has_effect(m, ATTACK_EFFECT) or has_effect(m, "AttackingCanBlock") or has_effect(m, SIGNAL_EFFECT) or has_effect(m, CLASH_EFFECT)
end

-- PING DETECTION (simplified but effective)
local ping_ms = 50

local function update_ping()
    local p = safe(function() return LP:GetNetworkPing() end)
    if type(p) == "number" and p > 0 then
        ping_ms = ping_ms * 0.8 + (p * 1000) * 0.2
    end
end

local function get_ping_lead()
    if AUTO_PING then
        return ping_ms / 1000
    end
    return PING_MS / 1000
end

-- TARGETING
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

local function closest_to_cursor()
    local mr = my_root()
    if not mr then return nil end
    local mx, my = Mouse.X, Mouse.Y
    local closest = nil
    local closest_dist = math.huge
    
    -- Check Living folder first
    local folder = living_folder()
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if is_enemy(m) then
                local r = get_hrp(m)
                if r then
                    local sp, on = Camera:WorldToScreenPoint(r.Position)
                    if on then
                        local dx, dy = sp.X - mx, sp.Y - my
                        local dist = dx * dx + dy * dy
                        if dist < closest_dist then
                            closest_dist = dist
                            closest = m
                        end
                    end
                end
            end
        end
    end
    
    -- Check players
    for _, pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        if ch and ch ~= my_char() and is_enemy(ch) then
            local r = get_hrp(ch)
            if r then
                local sp, on = Camera:WorldToScreenPoint(r.Position)
                if on then
                    local dx, dy = sp.X - mx, sp.Y - my
                    local dist = dx * dx + dy * dy
                    if dist < closest_dist then
                        closest_dist = dist
                        closest = ch
                    end
                end
            end
        end
    end
    
    return closest
end

-- PARRY SYSTEM
local blocking = false
local parry_busy = false
local last_parry_time = 0
local dodge_busy = false
local last_dodge_time = 0

-- FIXED: Use VirtualInputManager for reliable input
local function set_block(s)
    if s == blocking then return end
    blocking = s
    if s then
        VirtualInput:SendMouseButtonEvent(Enum.UserInputType.MouseButton2, Enum.UserInputState.Begin, nil, false)
    else
        VirtualInput:SendMouseButtonEvent(Enum.UserInputType.MouseButton2, Enum.UserInputState.End, nil, false)
    end
end

local function tap_parry(reason)
    local now = tick()
    if parry_busy then return false end
    if now - last_parry_time < PARRY_COOLDOWN then return false end
    
    parry_busy = true
    last_parry_time = now
    
    task.spawn(function()
        if not script_state.running then
            parry_busy = false
            return
        end
        
        set_block(true)
        task.wait(PARRY_HOLD_TIME)
        set_block(false)
        
        parry_busy = false
    end)
    return true
end

local function tap_dodge(reason, direction)
    local now = tick()
    if dodge_busy then return false end
    if now - last_dodge_time < 0.35 then return false end
    
    dodge_busy = true
    last_dodge_time = now
    
    task.spawn(function()
        if not script_state.running then
            dodge_busy = false
            return
        end
        
        local dir_key = Enum.KeyCode.S
        if direction == "left" then dir_key = Enum.KeyCode.A
        elseif direction == "right" then dir_key = Enum.KeyCode.D
        elseif direction == "forward" then dir_key = Enum.KeyCode.W end
        
        VirtualInput:SendKeyEvent(true, dir_key, false, game)
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        task.wait(0.2)
        VirtualInput:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        VirtualInput:SendKeyEvent(false, dir_key, false, game)
        
        dodge_busy = false
    end)
    return true
end

-- VISUALS
local function draw_visuals(mr, tr, target, is_parrying)
    if not SHOW_RADIUS then return end
    
    local step = 6.283185307179586 / segs
    local col = (is_parrying and color_cyan) or (target and color_green or color_red)
    local cx, cy, cz = mr.Position.X, mr.Position.Y - 3, mr.Position.Z
    
    for i = 1, segs do
        local a1 = (i - 1) * step
        local a2 = i * step
        local p1 = Camera:WorldToScreenPoint(v3(cx + math.cos(a1) * RANGE, cy, cz + math.sin(a1) * RANGE))
        local p2 = Camera:WorldToScreenPoint(v3(cx + math.cos(a2) * RANGE, cy, cz + math.sin(a2) * RANGE))
        
        if p1 and p2 then
            circle[i].From = Vector2.new(p1.X, p1.Y)
            circle[i].To = Vector2.new(p2.X, p2.Y)
            circle[i].Color = col
            circle[i].Visible = true
        else
            circle[i].Visible = false
        end
    end
    
    if target and tr and enemy_label then
        local lp = Camera:WorldToScreenPoint(tr.Position + v3(0, 4, 0))
        if lp then
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
local target = nil
local last_lock = false
local last_clash_time = 0
local last_attack_detect = 0

while script_state.running do
    RunService.Heartbeat:Wait()
    local now = tick()
    
    update_ping()
    
    -- Lock-on toggle
    local lock_now = UserInputService:IsKeyDown(Enum.KeyCode[LOCK_KEY] or Enum.KeyCode.G)
    if lock_now and not last_lock then
        if target then
            target = nil
            set_block(false)
        else
            target = closest_to_cursor()
        end
    end
    last_lock = lock_now
    
    -- Update range
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
            
            if in_range and not parry_busy and not dodge_busy then
                local ping_lead = get_ping_lead()
                local reacted = false
                
                -- Check for clash (fastest response)
                if has_effect(target, CLASH_EFFECT) and (now - last_clash_time) > 0.1 then
                    if tap_parry("clash") then
                        last_clash_time = now
                        reacted = true
                    end
                end
                
                -- Check for specific moves
                if not reacted then
                    for move_name, move_info in pairs(MOVES) do
                        if has_effect(target, move_name) then
                            local delay = math.max(0.05, move_info.windup - 0.1 - ping_lead)
                            if delay < 0.3 then
                                task.wait(delay)
                                if move_info.action == "parry" then
                                    tap_parry(move_name)
                                elseif move_info.action == "dodge" then
                                    tap_dodge(move_name, move_info.dodge_dir or "back")
                                end
                                reacted = true
                                break
                            end
                        end
                    end
                end
                
                -- Generic attack detection (backup)
                if not reacted and enemy_attacking(target) and (now - last_attack_detect) > 0.25 then
                    task.wait(0.12) -- Fixed delay for generic attacks
                    tap_parry("generic")
                    last_attack_detect = now
                end
            end
            
            -- Draw visuals - FIXED TYPO HERE
            if SHOW_RADIUS then
                draw_visuals(mr, er, target, parry_busy or dodge_busy)
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
