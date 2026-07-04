-- // Originally made by @unkamui
-- // Remastered by @yuhjinxx

_G.VV_AutoParry = {
    ToggleKey       = "G",
    BlockKey        = "F",
    DodgeKey        = "Q",
    PingMs          = 10,
    AutoPing        = true,
    ShowRange       = true,
    FallbackEnabled = true,
    HealthCheck     = true,
    ShowPing        = true,
    ShowWeapon      = true,
    ShowName        = true,
}

_G.VV_WeaponLog = {
    ["Club"]        = { timing = 0.600, range = 6.88 },
    ["DualKatana"]  = { timing = 0.550, range = 6.25 },
    ["Hakuda"] = {
        ["Fists"]     = { timing = 0.380, range = 5.95 },
        ["Boxing"]    = { timing = 0.420, range = 5.8  },
        ["Karate"]    = { timing = 0.425, range = 6    },
        ["MuayThai"]  = { timing = 0.425, range = 6.1  },
        ["Wrestling"] = { timing = 0.470, range = 6.05 },
    },
    ["Flail"]       = { timing = 0.770, range = 6.25 },
    ["Greataxe"]    = { timing = 0.550, range = 6.7  },
    ["Greatsword"]  = { timing = 0.600, range = 7    },
    ["Hammer"]      = { timing = 0.890, range = 6.7  },
    ["Katana"]      = { timing = 0.510, range = 6.25 },
    ["Lance"]       = { timing = 0.630, range = 7.45 },
    ["Minigun"]     = { timing = 0.500, range = 7.05 },
    ["Nunchucks"]   = { timing = 0.640, range = 6    },
    ["Odachi"]      = { timing = 0.510, range = 6.8  },
    ["Rapier"]      = { timing = 0.440, range = 6.5  },
    ["ReishiGun"]   = { timing = 0.700, range = 7.125},
    ["Rifle"]       = { timing = 0.460, range = 6.6  },
    ["Scythe"]      = { timing = 0.450, range = 6.95 },
    ["Spear"]       = { timing = 0.500, range = 13.3 },
    ["Tanto"]       = { timing = 0.510, range = 6.05 },
}

local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()
local Camera      = Workspace.CurrentCamera

local WeaponLog      = _G.VV_WeaponLog or {}
local TIMING_DEFAULT = 0.42
local RANGE_DEFAULT  = 14

local InstanceKey = "VVUltiParrybyJinx"
do
    local Old = _G and _G[InstanceKey]
    if Old then
        Old.Running = false
        if type(Old.Cleanup) == "function" then pcall(Old.Cleanup) end
    end
end

local State = { Running=true, Drawings={}, Cleanup=nil }
if _G then _G[InstanceKey] = State end

local function SafeCall(fn, fallback)
    local ok, result = pcall(fn)
    return ok and result or fallback
end

local function KeyPress(code)
    if type(keypress) == "function" then SafeCall(function() keypress(code) end) end
end

local function KeyRelease(code)
    if type(keyrelease) == "function" then SafeCall(function() keyrelease(code) end) end
end

local LastNotify = 0
local function Notify(msg, force)
    if type(notify) ~= "function" then return end
    local t = tick()
    if not force and t - LastNotify < 0.4 then return end
    LastNotify = t
    SafeCall(function() notify(tostring(msg), "VV AutoParry", 2) end)
end

local function GetHRP(m)       return m and m:FindFirstChild("HumanoidRootPart") end
local function GetChar()       return LocalPlayer and LocalPlayer.Character end
local function GetMyRoot()     return GetHRP(GetChar()) end
local function GetLiving()     return Workspace and Workspace:FindFirstChild("Living") end
local function GetStatus(m)    return m and m:FindFirstChild("Status") end
local function GetCooldowns(m) return m and m:FindFirstChild("Cooldowns") end

local function GetWeaponModel(char)
    if not char then return nil end
    local wm = char:FindFirstChild("WeaponModel")
    if wm then return wm end
    for _, child in ipairs(char:GetChildren()) do
        if child:FindFirstChild("WeaponType") then return child end
    end
    return nil
end

local function GetHakudaType(target)
    if not target then return nil end
    local status = GetStatus(target)
    if not status then return nil end
    local hakuda = status:FindFirstChild("Hakuda")
    if not hakuda then return nil end
    local hakudaTypes = {"Fists", "Boxing", "Karate", "MuayThai", "Wrestling"}
    for _, typeName in ipairs(hakudaTypes) do
        if hakuda:FindFirstChild(typeName) then return typeName end
    end
    return "Fists"
end

local function GetWeaponType(weaponModel)
    if not weaponModel then return "Unknown" end
    local wt = weaponModel:FindFirstChild("WeaponType")
    if wt then
        if type(wt.Value) == "string" and #wt.Value > 0 then return wt.Value end
        if type(wt.Value) == "number" then
            local names = {
                [0]="Fists",[1]="Sword",[2]="Katana",[3]="Greatsword",
                [4]="Scythe",[5]="Hammer",[6]="Rapier",[7]="Lance",
                [8]="Minigun",[9]="DualKatana",[10]="Club",[11]="Flail",
                [12]="Greataxe",[13]="Nunchucks",[14]="Odachi",[15]="ReishiGun",
                [16]="Rifle",[17]="Spear",[18]="Tanto"
            }
            return names[wt.Value] or ("Weapon_"..tostring(wt.Value))
        end
    end
    return "Unknown"
end

local function HasEffect(model, name)
    local s = GetStatus(model)
    return s ~= nil and s:FindFirstChild(name) ~= nil
end

local function SelfHasEffect(name)
    return HasEffect(GetChar(), name)
end

local PingMs = 0

local function GetPingMsFromConfig()
    local v = _G.VV_AutoParry.PingMs
    return type(v) == "number" and math.max(0, v) or 10
end

local function GetAutoPingEnabled()
    return _G.VV_AutoParry.AutoPing == true
end

local function UpdatePing()
    if GetAutoPingEnabled() then
        if type(GetPingValue) == "function" then
            local p = SafeCall(GetPingValue)
            if type(p) == "number" and p > 0 then
                PingMs = p
                return
            end
        end
    end
    PingMs = GetPingMsFromConfig()
end

local function GetPingLead()
    return math.max(PingMs, 0) / 1000
end

local function GetServerWindup(weaponType, target)
    local entry
    if weaponType == "Hakuda" and target then
        local hakudaType = GetHakudaType(target)
        if hakudaType then
            local hakudaEntry = WeaponLog["Hakuda"]
            if hakudaEntry and hakudaEntry[hakudaType] then
                entry = hakudaEntry[hakudaType]
            end
        end
    else
        entry = WeaponLog[weaponType]
    end
    if entry and type(entry.timing) == "number" then
        return entry.timing, true
    end
    return TIMING_DEFAULT, false
end

local function GetWeaponRange(weaponType, target)
    if weaponType == "Hakuda" then
        local hakudaType = GetHakudaType(target)
        if hakudaType then
            local hakudaEntry = WeaponLog["Hakuda"]
            if hakudaEntry and hakudaEntry[hakudaType] then
                return hakudaEntry[hakudaType].range
            end
        end
        return 5.95
    end
    local entry = WeaponLog[weaponType]
    if entry and type(entry.range) == "number" then return entry.range end
    return RANGE_DEFAULT
end

local function ComputeFireAt(signalStartedAt, weaponType, target)
    local windup   = GetServerWindup(weaponType, target)
    local ping     = GetPingLead()
    local holdHalf = 0.18
    return signalStartedAt + windup - holdHalf - ping
end

local CurrentWeaponType = "Unknown"
local EnemyWeaponRange  = RANGE_DEFAULT
local MyWeaponRange     = 6.5
local RangeSquared      = RANGE_DEFAULT * RANGE_DEFAULT

local function UpdateRange()
    RangeSquared = EnemyWeaponRange * EnemyWeaponRange
end

local function UpdateCurrentWeapon(target)
    if not target then
        CurrentWeaponType = "Unknown"
        EnemyWeaponRange  = RANGE_DEFAULT
        return
    end
    local hakudaType = GetHakudaType(target)
    if hakudaType then
        CurrentWeaponType = "Hakuda"
        EnemyWeaponRange  = GetWeaponRange("Hakuda", target)
        return
    end
    local wm = GetWeaponModel(target)
    if wm then
        local wt = GetWeaponType(wm)
        CurrentWeaponType = (wt and wt ~= "Unknown") and wt or "Unknown"
        EnemyWeaponRange  = GetWeaponRange(CurrentWeaponType, target)
    else
        CurrentWeaponType = "Unknown"
        EnemyWeaponRange  = RANGE_DEFAULT
    end
end

local function UpdateMyWeaponRange()
    local myChar = GetChar()
    if not myChar then MyWeaponRange = 6.5; return end
    local myWeaponModel = GetWeaponModel(myChar)
    if not myWeaponModel then MyWeaponRange = 6.5; return end
    local myWeaponType = GetWeaponType(myWeaponModel)
    if not myWeaponType or myWeaponType == "Unknown" then MyWeaponRange = 6.5; return end
    if myWeaponType == "Hakuda" then
        local hakudaType = GetHakudaType(myChar)
        if hakudaType then
            local hakudaEntry = WeaponLog["Hakuda"]
            if hakudaEntry and hakudaEntry[hakudaType] then
                MyWeaponRange = hakudaEntry[hakudaType].range
                return
            end
        end
        MyWeaponRange = 5.95
        return
    end
    local entry = WeaponLog[myWeaponType]
    MyWeaponRange = (entry and entry.range) or 6.5
end

local function IsAttackPresent(model, moveName)
    local cd = GetCooldowns(model)
    if cd and cd:FindFirstChild(moveName) then return true end
    local st = GetStatus(model)
    if st and st:FindFirstChild(moveName) then return true end
    return false
end

local function IsEnemyAttacking(model)
    return HasEffect(model, "Attacking")
        or HasEffect(model, "AttackingCanBlock")
        or HasEffect(model, "AttackingSignal")
end

local SpecialKeys = {
    F1=0x70,F2=0x71,F3=0x72,F4=0x73,F5=0x74,F6=0x75,
    F7=0x76,F8=0x77,F9=0x78,F10=0x79,F11=0x7A,F12=0x7B,
    Shift=0x10,Control=0x11,Alt=0x12,CapsLock=0x14,
    Space=0x20,Enter=0x0D,Backspace=0x08,Tab=0x09,
    Escape=0x1B,Delete=0x2E,Insert=0x2D,
    Home=0x24,End=0x23,PageUp=0x21,PageDown=0x22,
    Up=0x26,Down=0x28,Left=0x25,Right=0x27,
    Button1=0x01,Button2=0x02,Button3=0x04,
    MouseButton1=0x01,MouseButton2=0x02,MouseButton3=0x04,
    NumPad0=0x60,NumPad1=0x61,NumPad2=0x62,NumPad3=0x63,
    NumPad4=0x64,NumPad5=0x65,NumPad6=0x66,NumPad7=0x67,
    NumPad8=0x68,NumPad9=0x69,NumPadMultiply=0x6A,
    NumPadAdd=0x6B,NumPadSubtract=0x6D,
    NumPadDecimal=0x6E,NumPadDivide=0x6F,
}

local SpecialKeyNames = {}
for name, code in pairs(SpecialKeys) do
    if not SpecialKeyNames[code] then SpecialKeyNames[code] = name end
end

local function ResolveKey(key, fallback)
    if type(key) == "number" then return key end
    if type(key) == "string" then
        if SpecialKeys[key] then return SpecialKeys[key] end
        if #key >= 1 then return key:upper():sub(1,1):byte() end
    end
    return type(fallback) == "string" and fallback:byte() or fallback
end

local function KeyCodeToLabel(code)
    if type(code) ~= "number" then return "?" end
    if SpecialKeyNames[code] then return SpecialKeyNames[code] end
    if code >= 0x30 and code <= 0x5A then return string.char(code) end
    return "0x" .. string.format("%X", code)
end

local CaptureCandidates = {}
for c = 0x30, 0x39 do CaptureCandidates[#CaptureCandidates+1] = c end
for c = 0x41, 0x5A do CaptureCandidates[#CaptureCandidates+1] = c end
for _, code in pairs(SpecialKeys) do
    local dup = false
    for _, existing in ipairs(CaptureCandidates) do
        if existing == code then dup = true; break end
    end
    if not dup then CaptureCandidates[#CaptureCandidates+1] = code end
end

local Cfg = _G.VV_AutoParry
local function GetCfg(key, default)
    local val = Cfg[key]
    if val == nil then return default end
    return val
end

local KEY_TOGGLE = ResolveKey(GetCfg("ToggleKey", "G"), "G")
local KEY_BLOCK  = ResolveKey(GetCfg("BlockKey",  "F"), "F")
local KEY_DODGE  = ResolveKey(GetCfg("DodgeKey",  "Q"), "Q")

local IsBlocking   = false
local IsParryBusy  = false
local IsDodgeBusy  = false
local ParryBusyAt  = 0
local DodgeBusyAt  = 0
local LastParryTime  = 0
local LastDodgeTime  = 0
local LastActionTime = 0
local LastParryAttempt = 0

local PARRY_HOLD     = 0.25
local PARRY_COOLDOWN = 0.10
local DODGE_DURATION = 0.18
local DODGE_COOLDOWN = 0.10
local ACTION_LOCKOUT = 0.20
local BUSY_TIMEOUT   = 2.0

local function IsActionLocked(now)
    return (now - LastActionTime) < ACTION_LOCKOUT
end

local function CheckStuckBusy(now)
    if IsParryBusy and (now - ParryBusyAt) > BUSY_TIMEOUT then IsParryBusy = false end
    if IsDodgeBusy and (now - DodgeBusyAt) > BUSY_TIMEOUT then IsDodgeBusy = false end
end

local Stats = { Parries=0, Dodges=0, Blocks=0 }

local function SetBlock(state)
    if state == IsBlocking then return end
    IsBlocking = state
    if state then
        KeyPress(KEY_BLOCK)
        Stats.Blocks = Stats.Blocks + 1
    else
        KeyRelease(KEY_BLOCK)
    end
end

local function TapParry(reason, slot)
    if IsParryBusy then return false end
    if tick() - LastParryTime < PARRY_COOLDOWN then return false end
    IsParryBusy      = true
    ParryBusyAt      = tick()
    LastParryTime    = tick()
    LastParryAttempt = tick()
    Stats.Parries    = Stats.Parries + 1
    task.spawn(function()
        if not State.Running then IsParryBusy = false; return end
        SetBlock(true)
        Notify("PARRY")
        task.wait(PARRY_HOLD)
        SetBlock(false)
        IsParryBusy = false
    end)
    return true
end

local DirKeys = { back=0x53, left=0x41, right=0x44, forward=0x57 }

local function TapDodge(reason, direction)
    if IsDodgeBusy then return false end
    if tick() - LastDodgeTime < DODGE_COOLDOWN then return false end
    IsDodgeBusy   = true
    DodgeBusyAt   = tick()
    LastDodgeTime = tick()
    Stats.Dodges  = Stats.Dodges + 1
    Notify("DODGE")
    task.spawn(function()
        if not State.Running then IsDodgeBusy = false; return end
        local dirKey = DirKeys[direction] or DirKeys.back
        KeyPress(dirKey)
        KeyPress(KEY_DODGE)
        task.wait(DODGE_DURATION)
        KeyRelease(KEY_DODGE)
        KeyRelease(dirKey)
        IsDodgeBusy = false
    end)
    return true
end

local Moves = {
    ["Heavy Kick"]      = { Action="dodge", Windup=0.555, DodgeDir="back" },
    ["Uppercut"]        = { Action="parry", Windup=0.500 },
    ["Spin Kick"]       = { Action="dodge", Windup=0.600, DodgeDir="back" },
    ["Ground Slam"]     = { Action="dodge", Windup=0.900, DodgeDir="back" },
    ["Running Attack"]  = { Action="parry", Windup=0.670 },
    ["False Cutter"]    = { Action="dodge", Windup=0.735, DodgeDir="back", Signal="FalseCutterStart", SignalWindup=1.48 },
    ["Overhead Strike"] = { Action="dodge", Windup=1.10,  DodgeDir="back" },
    ["Skyscraper"]      = { Action="dodge", Windup=0.80,  DodgeDir="back" },
    ["AxeSlam"]         = { Action="dodge", Windup=0.735, DodgeDir="back" },
    ["Panther_Attack"]  = { Action="parry", Windup=0.974 },
    ["GelumAOE"]        = { Action="dodge", Windup=2.00,  DodgeDir="back" },
    ["GelumMeteor"]     = { Action="block", Windup=0.552, Hold=0.50 },
    ["Cyclone"]         = { Action="block", Windup=0.670, Hold=0.60, Signal="MoveActive", SignalWindup=0.670 },
    ["ScorpionHollow_PoisonBreath"] = { Action="block", Windup=1.382, Hold=0.55 },
    ["Roar"]                        = { Action="block", Windup=0.30,  Hold=0.80 },
    ["ScorpionPoison"]              = { Action="block", Windup=0.25,  Hold=0.70 },
    ["GiantDragonfly_Slam"]         = { Action="block", Windup=0.753, Hold=0.45 },
    ["GiantDragonfly_Tailwhip"]     = { Action="block", Windup=1.457, Hold=0.45 },
    ["GiantDragonfly_Grab"]         = { Action="dodge", Windup=1.493, DodgeDir="back" },
}

local MoveNames   = {}
local SignalMoves = {}
for name, info in pairs(Moves) do
    MoveNames[#MoveNames+1] = name
    if info.Signal then
        SignalMoves[info.Signal] = { Name=name, Info=info }
    end
end
local SignalNames = {}
for k in pairs(SignalMoves) do SignalNames[#SignalNames+1] = k end

local BLOCK_LEAD    = 0.15
local CLASH_TO_HIT  = 0.09
local MOVE_COOLDOWN = 0.45

local ParryFire = {}
local DodgeFire = {}
local BlockStart = 0
local BlockEnd   = 0
local MovePrev   = {}
local MoveLast   = {}
local SignalPrev  = {}

local function ExecuteMove(moveName, info, now, lead)
    if IsActionLocked(now) then return end
    LastActionTime = now
    ParryFire = {}
    DodgeFire = {}
    if info.Action == "dodge" then
        local t = math.max(now + info.Windup - 0.20 - lead, now + 0.04)
        DodgeFire[moveName] = t
    elseif info.Action == "block" then
        BlockStart = now + info.Windup - BLOCK_LEAD - lead
        BlockEnd   = BlockStart + (info.Hold or 0.5)
    else
        local t = math.max(now + info.Windup - CLASH_TO_HIT - lead, now + 0.04)
        ParryFire[moveName] = t
    end
end

local function IsEnemy(model)
    if not model or not model.Parent then return false end
    if model == GetChar() then return false end
    if model.Name == LocalPlayer.Name then return false end
    return GetHRP(model) ~= nil
end

local function GetCandidates()
    local list, seen = {}, {}
    local living = GetLiving()
    if living then
        for _, m in ipairs(living:GetChildren()) do
            if not seen[m] then seen[m]=true; list[#list+1]=m end
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        if c and not seen[c] then seen[c]=true; list[#list+1]=c end
    end
    return list
end

local function DistSq(a, b)
    local dx, dy, dz = a.X-b.X, a.Y-b.Y, a.Z-b.Z
    return dx*dx + dy*dy + dz*dz
end

local function GetClosestToCursor()
    local myRoot = GetMyRoot()
    if not myRoot then return nil end
    local mx, my = Mouse.X, Mouse.Y
    local bestScreen, bestScreenDist = nil, math.huge
    local bestWorld,  bestWorldDist  = nil, math.huge

    local worldToScreen = WorldToScreen
    if type(worldToScreen) ~= "function" then
        worldToScreen = function(pos)
            local cam = Camera
            if not cam then return nil, false end
            local vec, onScreen = cam:WorldToScreenPoint(pos)
            return Vector2.new(vec.X, vec.Y), onScreen
        end
    end

    for _, model in ipairs(GetCandidates()) do
        if IsEnemy(model) then
            local hrp = GetHRP(model)
            if hrp then
                local wd = DistSq(hrp.Position, myRoot.Position)
                if wd < bestWorldDist then bestWorldDist = wd; bestWorld = model end
                local sp, on = worldToScreen(hrp.Position)
                if on and sp then
                    local dx, dy = sp.X-mx, sp.Y-my
                    local sd = dx*dx + dy*dy
                    if sd < bestScreenDist then bestScreenDist = sd; bestScreen = model end
                end
            end
        end
    end
    return bestScreen or bestWorld
end

local function GetDisplayName(model)
    if model and type(model.Name) == "string" and #model.Name > 0 then return model.Name end
    return "Enemy"
end

local SignalWatch = {
    Active    = false,
    StartedAt = 0,
    Weapon    = "Unknown",
    FiredAt   = nil,
    DidHit    = false,
}

local ParryAttempt = { State="IDLE", FireAt=0, Slot=nil, RetryCount=0 }
local function ResetParryAttempt()
    ParryAttempt.State      = "IDLE"
    ParryAttempt.FireAt     = 0
    ParryAttempt.Slot       = nil
    ParryAttempt.RetryCount = 0
end

local CurrentTarget = nil
local LastLockState = false
local PrevClash     = false
local PrevSignal    = false
local PrevAttacking = false

local function ResetDetection()
    PrevClash     = false
    PrevSignal    = false
    PrevAttacking = false
    MovePrev   = {}
    MoveLast   = {}
    SignalPrev = {}
    ParryFire  = {}
    DodgeFire  = {}
    BlockStart = 0
    BlockEnd   = 0
    ResetParryAttempt()
    SignalWatch.Active = false
end

local SEGMENTS = 16
local TWO_PI   = math.pi * 2
local CircleLines       = {}
local TargetCircleLines = {}
local EnemyLabel  = nil
local WeaponLabel = nil
local PingLabel   = nil
local DrawingsInitialized = false

local VISUAL_HZ       = 1 / 30
local LastVisualUpdate = 0
local LastMyPos        = Vector3.new(0, 0, 0)
local LastTargetPos    = Vector3.new(0, 0, 0)
local LastMyRange      = 0
local LastEnemyRange   = 0
local LastMode         = nil
local LastInRange      = false
local CachedMyPts      = {}
local CachedMyVis      = {}
local CachedTargetPts  = {}
local CachedTargetVis  = {}
local MOVE_THRESH_SQ   = 0.25

local Colors = {
    MyRangeIn       = Color3.fromRGB(0, 255, 0),
    MyRangeOut      = Color3.fromRGB(77, 179, 255),
    EnemyRangeIn    = Color3.fromRGB(255, 0, 0),
    EnemyRangeOut   = Color3.fromRGB(255, 255, 0),
    EnemyRangeParry = Color3.fromRGB(0, 255, 255),
    PingColor       = Color3.fromRGB(255, 255, 255),
    WeaponColor     = Color3.fromRGB(51, 153, 255),
    EnemyNameColor  = Color3.fromRGB(255, 0, 0),
}

local function TrackDrawing(obj)
    State.Drawings[#State.Drawings+1] = obj
    return obj
end

local function KillDrawing(d)
    if not d then return end
    pcall(function() d.Visible = false end)
    if type(d.Remove)  == "function" then pcall(function() d:Remove()  end) end
    if type(d.Destroy) == "function" then pcall(function() d:Destroy() end) end
end
State.Cleanup = function()
    for _, d in ipairs(State.Drawings) do KillDrawing(d) end
    State.Drawings = {}
end

local function InitDrawings()
    if DrawingsInitialized then return end
    for i = 1, SEGMENTS do
        local ln = TrackDrawing(Drawing.new("Line"))
        ln.Thickness = 1.5; ln.Visible = false; CircleLines[i] = ln
        local ln2 = TrackDrawing(Drawing.new("Line"))
        ln2.Thickness = 2; ln2.Visible = false; TargetCircleLines[i] = ln2
    end
    EnemyLabel = TrackDrawing(Drawing.new("Text"))
    EnemyLabel.Outline = true; EnemyLabel.Center = true
    EnemyLabel.Size = 16; EnemyLabel.Color = Colors.EnemyNameColor
    EnemyLabel.Visible = false
    WeaponLabel = TrackDrawing(Drawing.new("Text"))
    WeaponLabel.Outline = true; WeaponLabel.Center = true
    WeaponLabel.Size = 13; WeaponLabel.Color = Colors.WeaponColor
    WeaponLabel.Visible = false
    PingLabel = TrackDrawing(Drawing.new("Text"))
    PingLabel.Outline = true; PingLabel.Center = false
    PingLabel.Size = 14; PingLabel.Color = Colors.PingColor
    PingLabel.Visible = false
    DrawingsInitialized = true
end

local function HideVisuals()
    for i = 1, SEGMENTS do
        if CircleLines[i]       then CircleLines[i].Visible       = false end
        if TargetCircleLines[i] then TargetCircleLines[i].Visible = false end
    end
    if EnemyLabel  then EnemyLabel.Visible  = false end
    if WeaponLabel then WeaponLabel.Visible = false end
    if PingLabel   then PingLabel.Visible   = false end
end

local function WorldToScreenSafe(pos)
    if type(WorldToScreen) == "function" then
        return WorldToScreen(pos)
    end
    local cam = Camera
    if not cam then return nil, false end
    local vec, on = cam:WorldToScreenPoint(pos)
    return Vector2.new(vec.X, vec.Y), on
end

local function RebuildCirclePoints(cx, cy, cz, radius, ptsOut, visOut)
    local step = TWO_PI / SEGMENTS
    for i = 0, SEGMENTS do
        local a = i * step
        local sp, on = WorldToScreenSafe(Vector3.new(
            cx + math.cos(a) * radius, cy, cz + math.sin(a) * radius))
        ptsOut[i] = sp
        visOut[i] = on
    end
end

local function ApplyCircleColor(lines, pts, vis, color)
    for i = 1, SEGMENTS do
        local ln = lines[i]
        if ln and vis[i-1] and vis[i] and pts[i-1] and pts[i] then
            ln.From    = Vector2.new(pts[i-1].X, pts[i-1].Y)
            ln.To      = Vector2.new(pts[i].X,   pts[i].Y)
            ln.Color   = color
            ln.Visible = true
        elseif ln then
            ln.Visible = false
        end
    end
end

local function DrawVisuals(myRoot, targetRoot, target, mode, inRange, now)
    local showRange  = _G.VV_AutoParry.ShowRange
    local showPing   = _G.VV_AutoParry.ShowPing
    local showWeapon = _G.VV_AutoParry.ShowWeapon
    local showName   = _G.VV_AutoParry.ShowName

    if not showRange then
        for i = 1, SEGMENTS do
            if CircleLines[i]       then CircleLines[i].Visible       = false end
            if TargetCircleLines[i] then TargetCircleLines[i].Visible = false end
        end
        if EnemyLabel  then EnemyLabel.Visible  = false end
        if WeaponLabel then WeaponLabel.Visible = false end
    else
        InitDrawings()

        local myPos     = myRoot.Position
        local myMoved   = DistSq(myPos, LastMyPos) > MOVE_THRESH_SQ
        local rangeDiff = MyWeaponRange ~= LastMyRange

        if myMoved or rangeDiff or (now - LastVisualUpdate) >= VISUAL_HZ then
            RebuildCirclePoints(myPos.X, myPos.Y - 3, myPos.Z, MyWeaponRange, CachedMyPts, CachedMyVis)
            LastMyPos   = myPos
            LastMyRange = MyWeaponRange
        end

        local inMyRange = false
        if target and targetRoot then
            inMyRange = DistSq(myPos, targetRoot.Position) <= (MyWeaponRange * MyWeaponRange)
        end
        ApplyCircleColor(CircleLines, CachedMyPts, CachedMyVis,
            inMyRange and Colors.MyRangeIn or Colors.MyRangeOut)

        if target and targetRoot then
            local tPos      = targetRoot.Position
            local tMoved    = DistSq(tPos, LastTargetPos) > MOVE_THRESH_SQ
            local tRangeDiff = EnemyWeaponRange ~= LastEnemyRange

            if tMoved or tRangeDiff or mode ~= LastMode or inRange ~= LastInRange
               or (now - LastVisualUpdate) >= VISUAL_HZ then
                RebuildCirclePoints(tPos.X, tPos.Y - 3, tPos.Z, EnemyWeaponRange, CachedTargetPts, CachedTargetVis)
                LastTargetPos  = tPos
                LastEnemyRange = EnemyWeaponRange
            end

            local enemyColor
            if mode == "parry" or mode == "timed" then
                enemyColor = Colors.EnemyRangeParry
            elseif inRange then
                enemyColor = Colors.EnemyRangeIn
            else
                enemyColor = Colors.EnemyRangeOut
            end
            ApplyCircleColor(TargetCircleLines, CachedTargetPts, CachedTargetVis, enemyColor)

            local lp, on = WorldToScreenSafe(tPos + Vector3.new(0, 3.5, 0))
            if on and lp then
                local nameY = lp.Y
                if showName and EnemyLabel then
                    EnemyLabel.Text     = GetDisplayName(target)
                    EnemyLabel.Position = Vector2.new(lp.X, nameY)
                    EnemyLabel.Color    = Colors.EnemyNameColor
                    EnemyLabel.Visible  = true
                    nameY = nameY + 20
                elseif EnemyLabel then
                    EnemyLabel.Visible = false
                end
                if showWeapon and WeaponLabel then
                    local displayType = CurrentWeaponType
                    if displayType == "Hakuda" then
                        local ht = GetHakudaType(target)
                        if ht then displayType = "Hakuda - " .. ht end
                    end
                    WeaponLabel.Text     = "[" .. displayType .. "]"
                    WeaponLabel.Position = Vector2.new(lp.X, nameY)
                    WeaponLabel.Color    = Colors.WeaponColor
                    WeaponLabel.Visible  = true
                elseif WeaponLabel then
                    WeaponLabel.Visible = false
                end
            else
                if EnemyLabel  then EnemyLabel.Visible  = false end
                if WeaponLabel then WeaponLabel.Visible = false end
            end
        else
            if EnemyLabel  then EnemyLabel.Visible  = false end
            if WeaponLabel then WeaponLabel.Visible = false end
            for i = 1, SEGMENTS do
                if TargetCircleLines[i] then TargetCircleLines[i].Visible = false end
            end
            CachedTargetPts = {}
            CachedTargetVis = {}
            LastTargetPos   = Vector3.new(0, 0, 0)
        end

        LastMode         = mode
        LastInRange      = inRange
        LastVisualUpdate = now
    end

    if PingLabel then
        if showPing then
            InitDrawings()
            local label = GetAutoPingEnabled()
                and string.format("Ping: %.0fms", PingMs)
                or  string.format("Ping: %.0fms (Manual)", PingMs)
            PingLabel.Text     = label
            PingLabel.Position = Vector2.new(8, 15)
            PingLabel.Color    = Colors.PingColor
            PingLabel.Visible  = true
        else
            PingLabel.Visible = false
        end
    end
end

local KeybindListening = nil
local KeybindButtons   = {}
local KeybindClickTime = 0
local KEYBIND_DELAY    = 0.3

local function StartKeybindCapture(configKey)
    KeybindListening = configKey
    KeybindClickTime = tick()
    Notify("Press any key to bind " .. configKey .. "...", true)
end

local function TryUpdateButtonLabel(configKey, label)
    local btn = KeybindButtons[configKey]
    if not btn then return end
    SafeCall(function() btn:SetText(label) end)
    SafeCall(function() btn.Text = label end)
    SafeCall(function() btn:Set(label) end)
end

local function CommitKeybind(configKey, code)
    Cfg[configKey] = KeyCodeToLabel(code)
    if configKey == "ToggleKey" then KEY_TOGGLE = code
    elseif configKey == "BlockKey" then KEY_BLOCK = code
    elseif configKey == "DodgeKey" then KEY_DODGE = code end
    TryUpdateButtonLabel(configKey, configKey .. ": " .. KeyCodeToLabel(code))
    Notify(configKey .. " bound to " .. KeyCodeToLabel(code), true)
    KeybindListening = nil
    KeybindClickTime = 0
end

local function PollKeybindCapture()
    if not KeybindListening then return end
    if type(iskeypressed) ~= "function" then
        Notify("Key capture unsupported by this executor", true)
        KeybindListening = nil
        KeybindClickTime = 0
        return
    end
    local now = tick()
    if now - KeybindClickTime < KEYBIND_DELAY then return end
    for _, code in ipairs(CaptureCandidates) do
        if iskeypressed(code) then
            CommitKeybind(KeybindListening, code)
            return
        end
    end
end

local Lib = SafeCall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.lua"))()
end, nil) or INSui

if type(Lib) == "table" then
    Lib:SetTheme({
        accentA = Color3.fromRGB(82, 122, 246),
        accentB = Color3.fromRGB(120, 152, 255),
        bg      = Color3.fromRGB(10, 12, 18),
        sidebar = Color3.fromRGB(13, 15, 22),
    })

    local win = Lib:CreateWindow({
        title      = "VV AutoParry",
        subtitle   = "made by @yuhjinxx",
        size       = Vector2.new(750, 600),
        configName = "vva_autoparry",
        menuKey    = "Insert",
        autoSave   = true,
        smartFps   = true,
        logo       = "https://tr.rbxcdn.com/180DAY-b37eb206561635a8e049057f69b046a2/150/150/Image/Webp/noFilter",
    })

    Lib:SetPerformance(true)
    Lib:SetOpacity(0.97)

    local mainTab = win:Tab("Main", "settings")

    local keybinds = mainTab:Section("Key Bindings", "Left", "configure control keys")
    keybinds:Label("Click a button, then press any key to bind it")
    keybinds:Divider()
    KeybindButtons["ToggleKey"] = keybinds:Button("ToggleKey: " .. tostring(Cfg.ToggleKey), function()
        StartKeybindCapture("ToggleKey")
    end)
    KeybindButtons["BlockKey"] = keybinds:Button("BlockKey: " .. tostring(Cfg.BlockKey), function()
        StartKeybindCapture("BlockKey")
    end)
    KeybindButtons["DodgeKey"] = keybinds:Button("DodgeKey: " .. tostring(Cfg.DodgeKey), function()
        StartKeybindCapture("DodgeKey")
    end)

    local combat = mainTab:Section("Combat Settings", "Right", "adjust combat behavior")
    combat:Toggle("Health Check", GetCfg("HealthCheck", true), function(v)
        _G.VV_AutoParry.HealthCheck = v
        Notify("Health Check: " .. tostring(v), true)
    end)
    combat:Toggle("Fallback Mode", GetCfg("FallbackEnabled", true), function(v)
        _G.VV_AutoParry.FallbackEnabled = v
        Notify("Fallback Mode: " .. tostring(v), true)
    end)
    combat:Divider()
    combat:Toggle("Auto Ping", GetCfg("AutoPing", true), function(v)
        _G.VV_AutoParry.AutoPing = v
        Notify("Auto Ping: " .. tostring(v), true)
    end)
    combat:Slider("Manual Ping (ms)", GetCfg("PingMs", 10), 1, 0, 200, "ms", function(v)
        _G.VV_AutoParry.PingMs = v
        Notify("Manual Ping: " .. tostring(v) .. "ms", true)
    end)

    local actions = mainTab:Section("Quick Actions", "Right", "quick access controls")
    actions:Button("Find Target", function()
        if not CurrentTarget then
            CurrentTarget = GetClosestToCursor()
            ResetDetection()
            if CurrentTarget then
                UpdateCurrentWeapon(CurrentTarget)
                UpdateRange()
                Notify("Locked: " .. GetDisplayName(CurrentTarget), true)
            else
                Notify("No target found", true)
            end
        else
            Notify("Already locked: " .. GetDisplayName(CurrentTarget), true)
        end
    end)
    actions:Button("Emergency Stop", function()
        Lib:Dialog({
            title   = "Emergency Stop?",
            text    = "This will immediately stop all actions. Continue?",
            confirm = "Stop",
            cancel  = "Cancel",
            onConfirm = function()
                CurrentTarget     = nil
                CurrentWeaponType = "Unknown"
                EnemyWeaponRange  = RANGE_DEFAULT
                SetBlock(false)
                ResetDetection()
                Notify("All actions stopped", true)
            end,
        })
    end)

    local visualTab = win:Tab("Visuals", "eye")

    local display = visualTab:Section("Display Settings", "Left", "configure visual feedback")
    display:Toggle("Show Range", GetCfg("ShowRange", true), function(v)
        _G.VV_AutoParry.ShowRange = v
        if not v then HideVisuals() end
        Notify("Show Range: " .. tostring(v), true)
    end)
    display:Toggle("Show Ping", GetCfg("ShowPing", true), function(v)
        _G.VV_AutoParry.ShowPing = v
        Notify("Show Ping: " .. tostring(v), true)
    end)
    display:Toggle("Show Weapon Info", GetCfg("ShowWeapon", true), function(v)
        _G.VV_AutoParry.ShowWeapon = v
        Notify("Show Weapon: " .. tostring(v), true)
    end)
    display:Toggle("Show Enemy Name", GetCfg("ShowName", true), function(v)
        _G.VV_AutoParry.ShowName = v
        Notify("Show Name: " .. tostring(v), true)
    end)
    display:Divider()
    display:Slider("UI Opacity", 95, 1, 50, 100, "%", function(v)
        Lib:SetOpacity(v / 100)
    end)

    local colorsSection = visualTab:Section("Range Colors", "Right", "customize range circle colors")
    colorsSection:Label("My Range")
    colorsSection:Colorpicker("In Range",     Colors.MyRangeIn,  function(c) Colors.MyRangeIn  = c end)
    colorsSection:Colorpicker("Out of Range", Colors.MyRangeOut, function(c) Colors.MyRangeOut = c end)
    colorsSection:Divider()
    colorsSection:Label("Enemy Range")
    colorsSection:Colorpicker("In Range",     Colors.EnemyRangeIn,    function(c) Colors.EnemyRangeIn    = c end)
    colorsSection:Colorpicker("Out of Range", Colors.EnemyRangeOut,   function(c) Colors.EnemyRangeOut   = c end)
    colorsSection:Colorpicker("Parry Mode",   Colors.EnemyRangeParry, function(c) Colors.EnemyRangeParry = c end)

    local textColors = visualTab:Section("Text Colors", "Left", "customize text label colors")
    textColors:Colorpicker("Ping Color",        Colors.PingColor,      function(c) Colors.PingColor      = c end)
    textColors:Colorpicker("Weapon Info Color", Colors.WeaponColor,    function(c) Colors.WeaponColor    = c end)
    textColors:Colorpicker("Enemy Name Color",  Colors.EnemyNameColor, function(c) Colors.EnemyNameColor = c end)

    local statusTab  = win:Tab("Status", "user")
    local statusInfo = statusTab:Section("Live Status", "Left", "live values are pushed via notifications")
    statusInfo:Label("This panel doesn't refresh live.")
    statusInfo:Label("Watch the notification popups instead:")
    statusInfo:Label("• Target lock / unlock")
    statusInfo:Label("• Parry / Dodge / Block events")
    statusInfo:Divider()
    statusInfo:Button("Show Current Stats", function()
        Notify(string.format("Parries: %d | Dodges: %d | Blocks: %d",
            Stats.Parries, Stats.Dodges, Stats.Blocks), true)
    end)
    statusInfo:Button("Show Current Target", function()
        if CurrentTarget then
            Notify("Target: " .. GetDisplayName(CurrentTarget) .. " | Weapon: " .. CurrentWeaponType, true)
        else
            Notify("No target locked", true)
        end
    end)
    statusInfo:Button("Reset Statistics", function()
        Lib:Dialog({
            title   = "Reset Statistics?",
            text    = "This will reset all stat counters. Continue?",
            confirm = "Reset",
            cancel  = "Cancel",
            onConfirm = function()
                Stats.Parries = 0; Stats.Dodges = 0; Stats.Blocks = 0
                Notify("Statistics reset", true)
            end,
        })
    end)

    local creditinfo = statusTab:Section("Credits", "Right", "People that made ts")
    creditinfo:Label("CREDITS")
    creditinfo:Divider()
    creditinfo:Label("Original Script - @unkamui")
    creditinfo:Label("Remastered Version - @yuhjinxx")
    creditinfo:Label("User Interface - @inspecttor")
    creditinfo:Label("Optimization - Claude by Anthropic Studios")
    win:AddSettingsTab("cog")

    Lib:Notify("VV AutoParry", "Press Insert to toggle menu | " .. _G.VV_AutoParry.ToggleKey .. " to lock target", 5)
end

if type(setrobloxinput) == "function" then SafeCall(function() setrobloxinput(true) end) end
UpdatePing()
Notify("VV AutoParry Initialised")

while State.Running do
    local ok, err = pcall(function()
        if not State.Running then return end
        task.wait()
        if not State.Running then return end

        local now = tick()

        PollKeybindCapture()
        UpdatePing()
        CheckStuckBusy(now)
        UpdateMyWeaponRange()

        local lockPressed = type(iskeypressed) == "function" and iskeypressed(KEY_TOGGLE) or false
        if lockPressed and not LastLockState then
            if CurrentTarget then
                CurrentTarget     = nil
                CurrentWeaponType = "Unknown"
                EnemyWeaponRange  = RANGE_DEFAULT
                SetBlock(false)
                ResetDetection()
                Notify("Unlocked", true)
            else
                CurrentTarget = GetClosestToCursor()
                ResetDetection()
                if CurrentTarget then
                    UpdateCurrentWeapon(CurrentTarget)
                    UpdateRange()
                    Notify("Locked: " .. GetDisplayName(CurrentTarget), true)
                else
                    Notify("No target found", true)
                end
            end
        end
        LastLockState = lockPressed

        local myRoot = GetMyRoot()
        if not myRoot then
            CurrentTarget = nil
            SetBlock(false)
            ResetDetection()
            HideVisuals()
            return
        end

        local targetRoot      = nil
        local currentMode     = nil
        local inRange         = false
        local healthCheck     = GetCfg("HealthCheck", true)
        local fallbackEnabled = GetCfg("FallbackEnabled", true)

        if CurrentTarget and healthCheck then
            local hrp = GetHRP(CurrentTarget)
            if not hrp or not CurrentTarget.Parent then
                CurrentTarget     = nil
                CurrentWeaponType = "Unknown"
                EnemyWeaponRange  = RANGE_DEFAULT
                SetBlock(false)
                ResetDetection()
                Notify("Target lost", true)
            end
        end

        if CurrentTarget and CurrentTarget.Parent and IsEnemy(CurrentTarget) then
            targetRoot = GetHRP(CurrentTarget)
            if targetRoot then
                UpdateCurrentWeapon(CurrentTarget)
                UpdateRange()
                inRange = DistSq(targetRoot.Position, myRoot.Position) <= RangeSquared
                local lead = GetPingLead()

                local currentSignals = {}
                local statusFolder = GetStatus(CurrentTarget)
                if statusFolder then
                    for _, child in ipairs(statusFolder:GetChildren()) do
                        currentSignals[child.Name] = true
                    end
                end

                local signalActive = currentSignals["AttackingSignal"]
                if signalActive and not PrevSignal then
                    ResetParryAttempt()
                    SignalWatch = {
                        Active    = true,
                        StartedAt = now,
                        Weapon    = CurrentWeaponType,
                        FiredAt   = nil,
                        DidHit    = false,
                    }
                elseif not signalActive and PrevSignal then
                    SignalWatch.Active = false
                    if ParryAttempt.State ~= "FIRED" then ResetParryAttempt() end
                end

                local namedMoveTriggered = false
                for _, moveName in ipairs(MoveNames) do
                    local info    = Moves[moveName]
                    local present = IsAttackPresent(CurrentTarget, moveName)
                    if present and not MovePrev[moveName]
                       and (now - (MoveLast[moveName] or -999)) > MOVE_COOLDOWN then
                        MoveLast[moveName] = now
                        ExecuteMove(moveName, info, now, lead)
                        namedMoveTriggered = true
                    end
                    MovePrev[moveName] = present
                end

                for _, sigName in ipairs(SignalNames) do
                    local sigData = SignalMoves[sigName]
                    local present = currentSignals[sigName]
                    if present and not SignalPrev[sigName]
                       and (now - (MoveLast[sigData.Name] or -999)) > MOVE_COOLDOWN
                       and not MovePrev[sigData.Name] then
                        MoveLast[sigData.Name] = now
                        local tempInfo = {
                            Action   = sigData.Info.Action,
                            Windup   = sigData.Info.SignalWindup or sigData.Info.Windup,
                            Hold     = sigData.Info.Hold,
                            DodgeDir = sigData.Info.DodgeDir,
                        }
                        ExecuteMove(sigData.Name, tempInfo, now, lead)
                        namedMoveTriggered = true
                    end
                    SignalPrev[sigName] = present
                end

                for moveName, fireAt in pairs(DodgeFire) do
                    if fireAt and now >= fireAt then
                        DodgeFire[moveName] = nil
                        local info = Moves[moveName]
                        TapDodge(moveName, info and info.DodgeDir or "back")
                        currentMode = "dodge"
                    end
                end
                for moveName, fireAt in pairs(ParryFire) do
                    if fireAt and now >= fireAt then
                        ParryFire[moveName] = nil
                        TapParry("timed:"..moveName, moveName)
                        currentMode = "timed"
                    end
                end

                local blockActive = false
                if BlockStart ~= 0 then
                    if now >= BlockStart and now <= BlockEnd then
                        blockActive = true
                    elseif now > BlockEnd then
                        BlockStart = 0; BlockEnd = 0
                    end
                end
                if blockActive then
                    SetBlock(true)
                    currentMode = "block"
                end

                if not blockActive and not namedMoveTriggered
                   and next(ParryFire) == nil and next(DodgeFire) == nil
                   and BlockStart == 0 then
                    local clashNow = HasEffect(CurrentTarget, "CanClash")
                                  or (SelfHasEffect("CanClash") and IsEnemyAttacking(CurrentTarget))

                    if ParryAttempt.State == "IDLE" and signalActive and not PrevSignal
                       and not IsActionLocked(now) and fallbackEnabled then
                        local fireAt = ComputeFireAt(SignalWatch.StartedAt, CurrentWeaponType, CurrentTarget)
                        fireAt = math.max(fireAt, now + 0.04)
                        ParryAttempt.State  = "SIGNAL_WAIT"
                        ParryAttempt.FireAt = fireAt
                        ParryAttempt.Slot   = "M1"
                    end

                    if ParryAttempt.State == "SIGNAL_WAIT" and clashNow and not PrevClash then
                        if now < ParryAttempt.FireAt then
                            ParryAttempt.FireAt = now
                        end
                    end

                    if ParryAttempt.State == "SIGNAL_WAIT" and now >= ParryAttempt.FireAt then
                        if not IsParryBusy and not IsDodgeBusy and not IsActionLocked(now) then
                            LastActionTime = now
                            local still_active = signalActive or clashNow or IsEnemyAttacking(CurrentTarget)
                            if still_active then
                                TapParry("M1", ParryAttempt.Slot)
                                currentMode             = "parry"
                                ParryAttempt.State      = "FIRED"
                                ParryAttempt.RetryCount = 0
                            else
                                ResetParryAttempt()
                            end
                        else
                            ParryAttempt.RetryCount = ParryAttempt.RetryCount + 1
                            if ParryAttempt.RetryCount > 10 or (now - ParryAttempt.FireAt) > 0.5 then
                                ResetParryAttempt()
                            end
                        end
                    end

                    PrevClash     = clashNow
                    PrevSignal    = signalActive
                    PrevAttacking = IsEnemyAttacking(CurrentTarget)
                else
                    PrevClash     = HasEffect(CurrentTarget, "CanClash")
                    PrevSignal    = currentSignals["AttackingSignal"]
                    PrevAttacking = IsEnemyAttacking(CurrentTarget)
                end

                if not blockActive and not IsParryBusy and not IsDodgeBusy then
                    SetBlock(false)
                end
            end
        else
            CurrentTarget     = nil
            CurrentWeaponType = "Unknown"
            EnemyWeaponRange  = RANGE_DEFAULT
            ResetDetection()
            if not IsParryBusy and not IsDodgeBusy then SetBlock(false) end
        end

        DrawVisuals(myRoot, targetRoot, CurrentTarget, currentMode, inRange, now)
    end)
    if not ok then warn("[VV AutoParry] " .. tostring(err)) end
end

if _G and _G[InstanceKey] == State then _G[InstanceKey] = nil end
SetBlock(false)
KeyRelease(KEY_BLOCK)
KeyRelease(KEY_DODGE)
for _, dk in pairs(DirKeys) do KeyRelease(dk) end
HideVisuals()
State.Cleanup()
