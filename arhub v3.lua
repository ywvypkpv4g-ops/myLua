-- ArHub | Bloxstrike ESP + Aimbot + NoRecoil + NoSpread + Triggerbot (lite)
-- Luau | Delta (mobile) | run via executor
-- Built for phones: everything starts OFF, ESP is capped and cheap, no full-game scans,
-- throttled raycasts, nothing is parented inside the game's own models.

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local cfg = {
    chams = false, names = false, health = false, team = false,
    aimbot = false, norecoil = false, nospread = false, wallcheck = true, trigger = false,
}
-- smooth: 0.18 soft, 0.55 strong, 1.0 hard snap. lead: seconds of movement prediction.
-- fov = circle radius in px. hold = seconds it stays on a target that drops out of view
-- before it is allowed to switch to someone else.
-- snap = degrees: once the crosshair is this close to the target the pull ramps up to a
-- full lock, so it sits dead still on the head. maxDist = farthest target in studs.
-- track = how fast the aim point follows the target (higher = tighter, lower = smoother).
local AIM = { fov = 130, smooth = 0.4, lead = 0.06, hold = 0.3, snap = 6, track = 22,
    maxDist = 3000, part = "Head", sticky = true }
local TB = { interval = 0.1, jitter = 0.03 }
local MAX_ESP = 8          -- most players tagged at once (nearest first)
local running = true
local marks = {}
local conns = {}

local function bind(signal, fn)
    local c = signal:Connect(fn)
    conns[#conns + 1] = c
    return c
end

-- breadcrumb: records the last risky action to bx_last.txt (if the executor has writefile),
-- so after a crash the file shows what was running. throttled to 5 writes/sec.
local lastCrumb = 0
local function crumb(msg)
    if not writefile then return end
    local now = os.clock()
    if now - lastCrumb < 0.2 then return end
    lastCrumb = now
    pcall(writefile, "bx_last.txt", msg .. " @" .. string.format("%.1f", now))
end

local COL = {
    enemy  = Color3.fromRGB(255, 60, 60),
    friend = Color3.fromRGB(60, 140, 255),
    bot    = Color3.fromRGB(255, 190, 40),
}

local gui = Instance.new("ScreenGui")
gui.Name = "BX_Tools"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
do
    local ok, parent = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    gui.Parent = (ok and parent) or lp:WaitForChild("PlayerGui")
end

local espFolder = Instance.new("Folder")
espFolder.Name = "BX_ESP"
espFolder.Parent = gui

-- ===== SHARED =====
local function playerOf(m)
    local direct = Players:FindFirstChild(m.Name)
    if direct then return direct end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == m or p.DisplayName == m.Name
            or m.Name:find(p.Name, 1, true) then
            return p
        end
    end
end

local kindCache = setmetatable({}, { __mode = "k" })

local function kindOf(m)
    local now = os.clock()
    local c = kindCache[m]
    if c and now - c.t < 1.5 then return c.k end
    local mine = lp:GetAttribute("Team")
    local pl = playerOf(m)
    local team = (pl and pl:GetAttribute("Team")) or m:GetAttribute("Team")
    local k
    if not pl and team == nil then
        k = "bot"
    elseif mine and team == mine then
        k = "friend"
    else
        k = "enemy"
    end
    kindCache[m] = { k = k, t = now }
    return k
end

local function valid(m)
    return m and m.Parent and m:GetAttribute("Dead") ~= true and kindOf(m) ~= "friend"
end

local function charFolder()
    return workspace:FindFirstChild("Characters")
end

-- ===== ESP (lite) =====
-- one Highlight + one small text label per tagged player, parented to our own folder.
local function drop(m)
    local k = marks[m]
    if not k then return end
    if k.hl then k.hl:Destroy() end
    if k.tag then k.tag:Destroy() end
    marks[m] = nil
end

local function build(m, root)
    crumb("esp build " .. m.Name)
    local hl = Instance.new("Highlight")
    hl.Adornee = m
    hl.FillTransparency = 0.6
    hl.OutlineTransparency = 0.2
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = espFolder

    local tag = Instance.new("BillboardGui")
    tag.Size = UDim2.fromOffset(120, 22)
    tag.StudsOffset = Vector3.new(0, 3.2, 0)
    tag.AlwaysOnTop = true
    tag.Adornee = root
    tag.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextStrokeTransparency = 0.4
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.Parent = tag

    return { hl = hl, tag = tag, label = label, root = root }
end

local function clearAll()
    for m in pairs(marks) do drop(m) end
end

local function sweep()
    if not (cfg.chams or cfg.names or cfg.health) then
        clearAll()
        return
    end
    local folder = charFolder()
    if not folder then clearAll() return end

    local cam = workspace.CurrentCamera
    local camPos = cam.CFrame.Position
    local cands = {}
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character and m:GetAttribute("Dead") ~= true then
            local root = m:FindFirstChild("HumanoidRootPart")
            if root then
                local kind = kindOf(m)
                if kind ~= "friend" or cfg.team then
                    cands[#cands + 1] = { m = m, root = root, kind = kind,
                        d = (root.Position - camPos).Magnitude }
                end
            end
        end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)

    local live = {}
    for i = 1, math.min(#cands, MAX_ESP) do
        local c = cands[i]
        local m = c.m
        live[m] = true
        local k = marks[m]
        if not k or k.root ~= c.root or not k.hl.Parent then
            drop(m)
            k = build(m, c.root)
            marks[m] = k
        end
        local col = COL[c.kind]
        k.hl.Enabled = cfg.chams
        k.hl.FillColor = col

        local h, mh = m:GetAttribute("Health"), m:GetAttribute("MaxHealth")
        local text = ""
        if cfg.names then text = m.Name end
        if cfg.health and h then
            text = text .. (text ~= "" and "  " or "") .. math.floor(h) .. "hp"
        end
        k.label.Text = text
        k.label.Visible = text ~= ""
        k.label.TextColor3 = (cfg.health and not cfg.names and h and mh and h / mh < 0.35)
            and Color3.fromRGB(255, 90, 90) or col
    end
    for m in pairs(marks) do
        if not live[m] then drop(m) end
    end
end

task.spawn(function()
    while running do
        pcall(sweep)
        task.wait(0.5)
    end
end)

-- ===== AIMBOT =====
local locked = nil
local lostAt = 0
local motion = setmetatable({}, { __mode = "k" })
local aimState = { pos = nil, part = nil }
local cached, nextScan = nil, 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local headCache = setmetatable({}, { __mode = "k" })

local function finite(v)
    return v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

local function visible(part)
    if not cfg.wallcheck then return true end
    local cam = workspace.CurrentCamera
    local filter = { cam }
    local folder = charFolder()
    if folder then filter[#filter + 1] = folder end
    if lp.Character then filter[#filter + 1] = lp.Character end
    rayParams.FilterDescendantsInstances = filter
    local o = cam.CFrame.Position
    return workspace:Raycast(o, part.Position - o, rayParams) == nil
end

local function headOf(m)
    local c = headCache[m]
    if c and c.Parent then return c end
    -- same aim point on every model: a real BasePart named Head, else the torso root
    local p = m:FindFirstChild(AIM.part)
    if not (p and p:IsA("BasePart")) then
        p = m:FindFirstChild(AIM.part, true)
    end
    if not (p and p:IsA("BasePart")) then
        p = m:FindFirstChild("HumanoidRootPart")
    end
    headCache[m] = p
    return p
end

local function getTarget()
    local cam = workspace.CurrentCamera
    local folder = charFolder()
    if not folder then return end
    local center = cam.ViewportSize / 2

    -- stay glued to the current target; only let go after it has been gone for AIM.hold
    if AIM.sticky and valid(locked) then
        local p = headOf(locked)
        local ok = false
        if p and finite(p.Position) then
            local v, on = cam:WorldToViewportPoint(p.Position)
            ok = on and (Vector2.new(v.X, v.Y) - center).Magnitude < AIM.fov * 2 and visible(p)
        end
        if ok then
            lostAt = 0
            return p
        end
        if lostAt == 0 then lostAt = os.clock() end
        if os.clock() - lostAt < AIM.hold then return nil end
    end
    lostAt = 0

    -- rank by screen distance first, ray-check only the closest few
    local list = {}
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character and valid(m) then
            local part = headOf(m)
            if part and finite(part.Position) then
                local v, on = cam:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(v.X, v.Y) - center).Magnitude
                    if d < AIM.fov and (part.Position - cam.CFrame.Position).Magnitude < AIM.maxDist then
                        list[#list + 1] = { part = part, m = m, d = d }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)

    for i = 1, math.min(#list, 4) do
        if visible(list[i].part) then
            crumb("aim lock " .. list[i].m.Name)
            locked = list[i].m
            return list[i].part
        end
    end
    locked = nil
end

-- runs LAST in the frame, after every camera / recoil / sway script, so nothing else can
-- push the camera after we set it (that fighting was a big part of the shake).
RunService:BindToRenderStep("BX_Aim", Enum.RenderPriority.Last.Value, function(dt)
    if not cfg.aimbot then locked, cached = nil, nil return end

    local now = os.clock()
    if now >= nextScan then
        nextScan = now + 0.03
        local ok, t = pcall(getTarget)
        cached = ok and t or nil
    end

    local t = cached
    if not (t and t.Parent) then return end
    local cam = workspace.CurrentCamera
    -- lead from measured movement of the target, identical for every player model
    -- (the part's own physics velocity can read 0 or odd values depending on the model)
    local mo = motion[t]
    local tnow = os.clock()
    if not mo or tnow - mo.t > 0.5 then
        mo = { p = t.Position, t = tnow, v = Vector3.zero }
        motion[t] = mo
    elseif tnow > mo.t then
        local inst = (t.Position - mo.p) / (tnow - mo.t)
        if finite(inst) and inst.Magnitude < 80 then mo.v = mo.v:Lerp(inst, 0.12) end
        mo.p, mo.t = t.Position, tnow
    end
    -- tiny speeds are measurement noise, not movement: ignoring them stops the wobble
    local vel = mo.v.Magnitude > 1.5 and mo.v or Vector3.zero
    local origin = cam.CFrame.Position
    -- lead matters at range, but a fixed offset turns into a huge angle up close,
    -- so it fades out with distance
    local dist = (t.Position - origin).Magnitude
    local lead = AIM.lead * math.clamp(dist / 80, 0, 1)
    local raw = t.Position + vel * lead

    -- low-pass the aim point: positions arrive in network-sized steps, and chasing each
    -- step raw is what made the camera shake. This follows the smoothed path instead.
    local pos = aimState.pos
    if aimState.part ~= t or not pos or (raw - pos).Magnitude > 25 then
        pos = raw
    else
        pos = pos:Lerp(raw, 1 - math.exp(-dt * AIM.track))
    end
    aimState.pos, aimState.part = pos, t
    if not finite(pos) or (pos - origin).Magnitude < 1 then return end

    -- far away: normal smooth pull. close to the head: ramps to a full lock, so the
    -- camera stops oscillating and stays dead on the target.
    local dir = (pos - origin).Unit
    local ang = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(dir), -1, 1)))
    local base = 1 - (1 - math.clamp(AIM.smooth, 0.01, 1)) ^ (dt * 60)
    local near = 1 - math.clamp(ang / AIM.snap, 0, 1)
    local alpha = base + (1 - base) * near * near * (3 - 2 * near)  -- eased, no sudden jump
    local nxt = cam.CFrame:Lerp(CFrame.lookAt(origin, pos), alpha)
    if finite(nxt.Position) then cam.CFrame = nxt end
end)

-- FOV ring
local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromOffset(AIM.fov * 2, AIM.fov * 2)
ring.BackgroundTransparency = 1
ring.Visible = false
ring.Parent = gui
Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
local rs = Instance.new("UIStroke", ring)
rs.Color = Color3.new(1, 1, 1)
rs.Transparency = 0.6
rs.Thickness = 1

-- ===== TRIGGERBOT =====
local nextShot, nextCheck = 0, 0
local tbParams = RaycastParams.new()
tbParams.FilterType = Enum.RaycastFilterType.Exclude

local function enemyAt(inst)
    local folder = charFolder()
    if not folder then return end
    local m = inst
    while m and m.Parent ~= folder do m = m.Parent end
    if m and m:IsA("Model") and m ~= lp.Character and valid(m) then return m end
end

-- no mouse1click: it hard-crashes on some mobile executors. Tool:Activate fires the
-- equipped weapon's own Activated event instead.
local function fire()
    crumb("trigger fire")
    local tool = lp.Character and lp.Character:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
end

bind(RunService.Heartbeat, function()
    if not cfg.trigger then return end
    local now = os.clock()
    if now < nextCheck or now < nextShot then return end
    nextCheck = now + 0.03

    local cam = workspace.CurrentCamera
    local c = cam.ViewportSize / 2
    local ray = cam:ViewportPointToRay(c.X, c.Y)
    local filter = { cam }
    if lp.Character then filter[2] = lp.Character end
    tbParams.FilterDescendantsInstances = filter

    local hit = workspace:Raycast(ray.Origin, ray.Direction * 3000, tbParams)
    if hit and enemyAt(hit.Instance) then
        nextShot = now + TB.interval + math.random() * TB.jitter
        fire()
    end
end)

-- ===== NO RECOIL (only touches the module if it is already loaded) =====
local backups = {}
local KEEP = { "time", "delay", "rate", "count", "index", "length" }

local function unlock(tbl)
    if setreadonly then pcall(setreadonly, tbl, false) end
end

local function deepcopy(t, seen, depth)
    seen, depth = seen or {}, depth or 0
    if seen[t] or depth > 6 then return seen[t] or {} end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do
        c[k] = type(v) == "table" and deepcopy(v, seen, depth + 1) or v
    end
    return c
end

local function keep(k)
    if type(k) ~= "string" then return false end
    k = k:lower()
    for _, w in ipairs(KEEP) do
        if k:find(w, 1, true) then return true end
    end
    return false
end

local function zeroAll(tbl, seen, depth)
    seen, depth = seen or {}, depth or 0
    if seen[tbl] or depth > 6 then return end
    seen[tbl] = true
    unlock(tbl)
    for k, v in pairs(tbl) do
        local tv = typeof(v)
        if tv == "table" then zeroAll(v, seen, depth + 1)
        elseif not keep(k) then
            if tv == "number" then tbl[k] = 0
            elseif tv == "Vector2" then tbl[k] = Vector2.zero
            elseif tv == "Vector3" then tbl[k] = Vector3.zero end
        end
    end
end

local function restoreInto(dst, src, seen, depth)
    seen, depth = seen or {}, depth or 0
    if seen[dst] or depth > 6 then return end
    seen[dst] = true
    unlock(dst)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            restoreInto(dst[k], v, seen, depth + 1)
        else
            dst[k] = v
        end
    end
end

local function findRecoil()
    if not getloadedmodules then return end
    for _, m in ipairs(getloadedmodules()) do
        if m.Name == "RecoilPatterns" then return m end
    end
end

-- v2, built from the Copy Info report: every gun module (ReplicatedStorage.Database.Custom.
-- Weapons.<gun>) has a Recoil table { Pattern = function, Scale, CameraScale, Speed,
-- Damper, RecoverySpeed }. Same method that made No Spread work: shrink the OUTPUT of the
-- game's own Pattern function and the two magnitude fields (Scale, CameraScale) to 5%.
-- Never a hard 0, because a zero can break the game's own math. Originals are saved and
-- put back when the toggle goes off. Re-equip your gun after switching it on.
local RECOIL_SCALE = 0.05
local recoilBackups = {}   -- { { table, key, original }, ... }
local recoilDone = setmetatable({}, { __mode = "k" })

-- scales numbers / Vector2 / Vector3 and passes everything else through untouched
local function scaleVals(...)
    local n = select("#", ...)
    local t = table.pack(...)
    for i = 1, n do
        local tv = typeof(t[i])
        if tv == "number" or tv == "Vector2" or tv == "Vector3" then
            t[i] = t[i] * RECOIL_SCALE
        end
    end
    return table.unpack(t, 1, n)
end

local function weaponModules()
    local out = {}
    if not getloadedmodules then return out end
    local db = game:GetService("ReplicatedStorage"):FindFirstChild("Database")
    local custom = db and db:FindFirstChild("Custom")
    local folder = custom and custom:FindFirstChild("Weapons")
    if not folder then return out end
    for _, m in ipairs(getloadedmodules()) do
        if m:IsDescendantOf(folder) then out[#out + 1] = m end
    end
    return out
end

local function hookRecoil()
    local n = 0
    for _, m in ipairs(weaponModules()) do
        local ok, data = pcall(require, m)
        local rec = ok and type(data) == "table" and rawget(data, "Recoil")
        if type(rec) == "table" and not recoilDone[rec] then
            unlock(rec)
            local pat = rawget(rec, "Pattern")
            if type(pat) == "function" then
                recoilBackups[#recoilBackups + 1] = { rec, "Pattern", pat }
                if pcall(function()
                    rec.Pattern = function(...) return scaleVals(pat(...)) end
                end) then n += 1 end
            end
            for _, key in ipairs({ "Scale", "CameraScale" }) do
                local v = rawget(rec, key)
                if type(v) == "number" then
                    recoilBackups[#recoilBackups + 1] = { rec, key, v }
                    if pcall(function() rec[key] = v * RECOIL_SCALE end) then n += 1 end
                end
            end
            recoilDone[rec] = true
        end
    end
    return n
end

local function unhookRecoil()
    for _, b in ipairs(recoilBackups) do
        unlock(b[1])
        pcall(function() b[1][b[2]] = b[3] end)
        recoilDone[b[1]] = nil
    end
    table.clear(recoilBackups)
end

-- returns how many parts it changed (the menu shows it in a pop-up)
local function setNoRecoil(on)
    local total = 0

    -- layer 1 (kept from before): the shared RecoilPatterns module
    local m = findRecoil()
    if m then
        local ok, data = pcall(require, m)
        if ok and type(data) == "table" then
            if on then
                backups[m] = backups[m] or deepcopy(data)
                pcall(zeroAll, data)
                total += 1
            elseif backups[m] then
                pcall(restoreInto, data, backups[m])
            end
        end
    end

    -- layer 2: the per-gun Recoil tables
    if on then
        local ok, n = pcall(hookRecoil)
        total += (ok and n) or 0
        if total == 0 then cfg.norecoil = false end
    else
        pcall(unhookRecoil)
    end
    return total
end

-- ===== NO SPREAD =====
-- Finds numbers named like "spread"/"inaccuracy" in already-loaded weapon modules and on
-- the equipped tool / character, sets them to 0, and remembers the originals to restore.
local spreadOn = false
local spreadBackups = setmetatable({}, { __mode = "k" })  -- [table] = { key = original }
local attrBackups = setmetatable({}, { __mode = "k" })    -- [instance] = { attr = original }
local valBackups = setmetatable({}, { __mode = "k" })     -- [NumberValue] = original

-- Values are scaled down to 3% instead of set to exactly 0: a hard 0 can end up as a
-- divide-by-zero or endless loop inside the game's own shooting code (that is what froze
-- the game). 3% is a dead-straight line in practice.
local SPREAD_SCALE = 0.03
local SKIP_WORDS = { "recover", "decay", "time", "rate", "speed", "delay", "reset",
    "interval", "count", "index" }

local function isSpreadKey(k)
    if type(k) ~= "string" then return false end
    k = k:lower()
    if k:find("spread", 1, true) == nil and k:find("inaccura", 1, true) == nil then
        return false
    end
    for _, w in ipairs(SKIP_WORDS) do
        if k:find(w, 1, true) then return false end
    end
    return true
end

local function isZero(v)
    return v == 0 or v == Vector2.zero or v == Vector3.zero
end

local function patchTable(tbl, seen, depth)
    if seen[tbl] or depth > 5 then return 0 end
    seen[tbl] = true
    unlock(tbl)
    local n = 0
    for k, v in pairs(tbl) do
        local tv = typeof(v)
        if tv == "table" then
            n += patchTable(v, seen, depth + 1)
        elseif isSpreadKey(k) and (tv == "number" or tv == "Vector2" or tv == "Vector3") then
            local bk = spreadBackups[tbl] or {}
            spreadBackups[tbl] = bk
            if bk[k] == nil then bk[k] = v end
            local target = bk[k] * SPREAD_SCALE
            if v ~= target and pcall(function() tbl[k] = target end) then n += 1 end
        end
    end
    return n
end

-- this game keeps weapon stats in modules named after the guns ("AK-47", "M4A4", ...),
-- so every loaded module is checked by KEY name, not by module name. Each module is only
-- walked once per activation.
local scannedMods = setmetatable({}, { __mode = "k" })

local function scanModules()
    if not getloadedmodules then return 0 end
    local n = 0
    for i, m in ipairs(getloadedmodules()) do
        if not scannedMods[m] then
            scannedMods[m] = true
            local ok, data = pcall(require, m)
            if ok and type(data) == "table" then n += patchTable(data, {}, 0) end
            if i % 8 == 0 then task.wait() end
        end
    end
    return n
end

local function scanInstance(inst, deep)
    local n = 0
    for k, v in pairs(inst:GetAttributes()) do
        if isSpreadKey(k) and type(v) == "number" then
            local bk = attrBackups[inst] or {}
            attrBackups[inst] = bk
            if bk[k] == nil then bk[k] = v end
            local target = bk[k] * SPREAD_SCALE
            if v ~= target then
                inst:SetAttribute(k, target)
                n += 1
            end
        end
    end
    if deep then
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("NumberValue") and isSpreadKey(d.Name) then
                if valBackups[d] == nil then valBackups[d] = d.Value end
                local target = valBackups[d] * SPREAD_SCALE
                if d.Value ~= target then
                    d.Value = target
                    n += 1
                end
            end
        end
    end
    return n
end

local function applySpread()
    local n = scanModules()
    local char = lp.Character
    if char then
        n += scanInstance(char, false)
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then n += scanInstance(tool, true) end
    end
    return n
end

local function restoreSpread()
    for tbl, bk in pairs(spreadBackups) do
        unlock(tbl)
        for k, v in pairs(bk) do tbl[k] = v end
    end
    for inst, bk in pairs(attrBackups) do
        for k, v in pairs(bk) do pcall(inst.SetAttribute, inst, k, v) end
    end
    for d, v in pairs(valBackups) do pcall(function() d.Value = v end) end
    table.clear(spreadBackups)
    table.clear(attrBackups)
    table.clear(valBackups)
    table.clear(scannedMods)
end

local function toast(msg)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(280, 28)
    l.AnchorPoint = Vector2.new(0.5, 0)
    l.Position = UDim2.new(0.5, 0, 0, 60)
    l.BackgroundColor3 = Color3.fromRGB(14, 6, 8)
    l.BackgroundTransparency = 0.2
    l.TextColor3 = Color3.new(1, 1, 1)
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 13
    l.Text = msg
    l.Parent = gui
    Instance.new("UICorner", l).CornerRadius = UDim.new(0, 8)
    task.delay(3, function() l:Destroy() end)
end

-- From the Copy Info report: this game computes spread in functions on the Bullet and
-- Weapon modules (Bullet.getTrueSpread, Weapon.getSpread, ...), and the weapon configs
-- only hold nested tuning values (PerShot, MovementMultiplier, ...). So instead of editing
-- any game data, the toggle wraps those functions and shrinks the number they return.
-- Nothing in the game's tables or configs is modified; toggling off puts the originals back.
local SPREAD_FUNCS = { "getTrueSpread", "getSpreadForConfig", "getMovementSpreadForConfig",
    "getBaseSpreadForConfig", "getBaseSpread", "getSpread" }
local hooks = {}       -- { tbl = module table, name = function name, fn = original }
local hooked = setmetatable({}, { __mode = "k" })

local function shrink(v)
    local tv = typeof(v)
    if tv == "number" or tv == "Vector2" or tv == "Vector3" then
        return v * SPREAD_SCALE
    end
    return v
end

local function hookSpread()
    if not getloadedmodules then return 0 end
    local n = 0
    for _, m in ipairs(getloadedmodules()) do
        if m.Name == "Bullet" or m.Name == "Weapon" then
            local ok, data = pcall(require, m)
            if ok and type(data) == "table" then
                for _, name in ipairs(SPREAD_FUNCS) do
                    local f = rawget(data, name)
                    hooked[data] = hooked[data] or {}
                    if type(f) == "function" and not hooked[data][name] then
                        unlock(data)
                        local wrapped = function(...)
                            local a, b = f(...)
                            return shrink(a), b
                        end
                        if pcall(function() data[name] = wrapped end) then
                            hooked[data][name] = true
                            hooks[#hooks + 1] = { tbl = data, name = name, fn = f }
                            n += 1
                        end
                    end
                end
            end
        end
    end
    return n
end

local function unhookSpread()
    for _, h in ipairs(hooks) do
        unlock(h.tbl)
        pcall(function() h.tbl[h.name] = h.fn end)
        hooked[h.tbl] = nil
    end
    table.clear(hooks)
end

local function setNoSpread(on)
    spreadOn = false   -- the old value-patching loop stays idle
    if on then
        local ok, n = pcall(hookSpread)
        n = ok and n or 0
        crumb("nospread hooked " .. n)
        toast(n > 0 and ("No Spread: hooked " .. n .. " functions")
            or "No Spread: spread functions not found")
    else
        pcall(unhookSpread)
        toast("No Spread: restored")
    end
end

-- weapons swap, respawns happen: keep patching while it is on
task.spawn(function()
    while running do
        if spreadOn then pcall(applySpread) end
        task.wait(1)
    end
end)

-- ===== INFO DUMP =====
-- One press collects how this game actually names its spread / recoil values (loaded
-- modules, the equipped tool, ReplicatedStorage) and copies the report to the clipboard.
local function showText(text)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(0.8, 0, 0.7, 0)
    f.Position = UDim2.fromScale(0.1, 0.15)
    f.BackgroundColor3 = Color3.fromRGB(14, 6, 8)
    f.Parent = gui
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)

    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, -16, 1, -48)
    sf.Position = UDim2.fromOffset(8, 40)
    sf.BackgroundTransparency = 1
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.CanvasSize = UDim2.new()
    sf.ScrollBarThickness = 4
    sf.Parent = f

    local tb = Instance.new("TextBox")
    tb.Size = UDim2.new(1, 0, 0, 0)
    tb.AutomaticSize = Enum.AutomaticSize.Y
    tb.BackgroundTransparency = 1
    tb.ClearTextOnFocus = false
    tb.MultiLine = true
    tb.TextWrapped = true
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.TextYAlignment = Enum.TextYAlignment.Top
    tb.TextColor3 = Color3.new(1, 1, 1)
    tb.Font = Enum.Font.Code
    tb.TextSize = 12
    tb.Text = text
    tb.Parent = sf

    local x = Instance.new("TextButton")
    x.Size = UDim2.fromOffset(60, 30)
    x.Position = UDim2.new(1, -68, 0, 5)
    x.BackgroundColor3 = Color3.fromRGB(176, 14, 26)
    x.Text = "Close"
    x.TextColor3 = Color3.new(1, 1, 1)
    x.Font = Enum.Font.GothamBold
    x.TextSize = 13
    x.Parent = f
    Instance.new("UICorner", x).CornerRadius = UDim.new(0, 8)
    x.MouseButton1Click:Connect(function() f:Destroy() end)
end

local function dumpInfo()
    local out = {}
    local function add(s) if #out < 500 then out[#out + 1] = s end end
    local WORDS = { "spread", "inaccur", "bloom", "cone", "deviat", "accura", "recoil", "sway" }
    local function hit(k)
        if type(k) ~= "string" then return false end
        k = k:lower()
        for _, w in ipairs(WORDS) do
            if k:find(w, 1, true) then return true end
        end
        return false
    end
    local function val(v)
        return (typeof(v) == "table") and "{table}" or tostring(v)
    end

    local budget = 30000
    local function walk(tbl, path, seen, depth)
        if seen[tbl] or depth > 4 or budget <= 0 then return end
        seen[tbl] = true
        for k, v in pairs(tbl) do
            budget -= 1
            if budget <= 0 then return end
            if typeof(v) == "table" then
                if hit(k) then add("  " .. path .. "." .. tostring(k) .. " = {table}") end
                walk(v, path .. "." .. tostring(k), seen, depth + 1)
            elseif hit(k) then
                add("  " .. path .. "." .. tostring(k) .. " = " .. val(v))
            end
        end
    end

    local char0 = lp.Character
    local tool0 = char0 and char0:FindFirstChildOfClass("Tool")
    local toolName = tool0 and tool0.Name or nil
    if getloadedmodules then
        local mods = getloadedmodules()
        add("== spread/recoil-like keys inside modules ==")
        for _, m in ipairs(mods) do
            local ok, data = pcall(require, m)
            if ok and type(data) == "table" then walk(data, m.Name, {}, 0) end
        end

        -- full shape of the modules that most likely hold weapon stats
        add("== weapon-stat modules (shape) ==")
        local WANT = { ["CameraController"] = true, ["GetWeaponCameraKick"] = true,
            ["RecoilPatterns"] = true, ["AK-47"] = true }
        if toolName then WANT[toolName] = true end
        local seenName = {}
        for _, m in ipairs(mods) do
            if WANT[m.Name] and (seenName[m.Name] or 0) < 2 then
                local ok, data = pcall(require, m)
                if ok and type(data) == "table" then
                    seenName[m.Name] = (seenName[m.Name] or 0) + 1
                    add("-- " .. m:GetFullName())
                    local lines = 0
                    for k, v in pairs(data) do
                        lines += 1
                        if lines > 40 then break end
                        if typeof(v) == "table" then
                            local sub, sc = {}, 0
                            for k2, v2 in pairs(v) do
                                sc += 1
                                if sc > 10 then break end
                                sub[#sub + 1] = tostring(k2) .. "=" .. val(v2)
                            end
                            add("  " .. tostring(k) .. " = {" .. table.concat(sub, ", ") .. "}")
                        else
                            add("  " .. tostring(k) .. " = " .. val(v))
                        end
                    end
                end
            end
        end
    else
        add("executor has no getloadedmodules")
    end

    local char = lp.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    add("== equipped tool: " .. (tool and tool.Name or "NONE (hold a gun first)") .. " ==")
    if tool then
        for k, v in pairs(tool:GetAttributes()) do add("  attr " .. k .. " = " .. val(v)) end
        local c = 0
        for _, d in ipairs(tool:GetDescendants()) do
            c += 1
            if c > 40 then break end
            add("  " .. d.ClassName .. " " .. d.Name
                .. (d:IsA("ValueBase") and (" = " .. tostring(d.Value)) or ""))
        end
    end
    if char then
        add("== character attributes ==")
        for k, v in pairs(char:GetAttributes()) do add("  " .. k .. " = " .. val(v)) end
    end

    add("== ReplicatedStorage spread-like ==")
    local c = 0
    for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        c += 1
        if c > 6000 then break end
        if hit(d.Name) then
            add("  " .. d:GetFullName() .. (d:IsA("ValueBase") and (" = " .. tostring(d.Value)) or ""))
        end
        for k, v in pairs(d:GetAttributes()) do
            if hit(k) then add("  " .. d:GetFullName() .. " attr " .. k .. " = " .. val(v)) end
        end
    end

    local text = table.concat(out, "\n")
    if #text > 12000 then text = text:sub(1, 12000) .. "\n...cut" end
    if writefile then pcall(writefile, "bx_info.txt", text) end
    local copied = setclipboard and pcall(setclipboard, text)
    toast(copied and "Info copied: paste it in the chat" or "Info shown on screen")
    if not copied then showText(text) end
end

-- ===== WORLD + GUN FX =====
-- Purely visual, client-side only: sky / lighting recolor, bloom, screen tint, and a
-- neon glow on your first-person gun. Every change is backed up and put back when you
-- switch the toggle off or unload.
local Lighting = game:GetService("Lighting")

cfg.sky, cfg.rainbowSky = false, false
cfg.gunfx, cfg.rainbowGun, cfg.pulseGun, cfg.gunHands = false, false, false, false

local FX = {
    skyHue = 0.99, skySat = 0.9, skyVal = 0.75,
    clock = 0,            -- time of day in hours (0-24)
    tint = 0,             -- screen color tint, 0-0.7
    fog = 0,              -- 0-1
    bloom = 0,            -- 0-3, 0 = off
    rainbowSpeed = 0.08,  -- hue cycles per second
    gunHue = 0.99, gunSat = 1,
    gunMode = 2,          -- 1 glow, 2 neon, 3 ghost
    gunPower = 0.7,       -- 0-1
}

-- ---------- sky ----------
local SKY_KEYS = { "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom",
    "FogColor", "FogStart", "FogEnd", "ClockTime" }
local skySaved = nil
local skyAtmo, skyAtmoOwned = nil, false
local skyTint, skyBloom = nil, nil

local function saveSky()
    if skySaved then return end
    skySaved = {}
    for _, k in ipairs(SKY_KEYS) do skySaved[k] = Lighting[k] end
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then skySaved.sky, skySaved.skyParent = sky, sky.Parent end
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmo then
        skySaved.atmo = atmo
        skySaved.atmoProps = { Density = atmo.Density, Offset = atmo.Offset, Color = atmo.Color,
            Decay = atmo.Decay, Glare = atmo.Glare, Haze = atmo.Haze }
    end
end

local function ensureAtmo()
    if skyAtmo and skyAtmo.Parent then return skyAtmo end
    local existing = skySaved and skySaved.atmo
    if existing and existing.Parent then
        skyAtmo, skyAtmoOwned = existing, false
        return skyAtmo
    end
    skyAtmo = Instance.new("Atmosphere")
    skyAtmo.Name = "ArHubAtmosphere"
    skyAtmo.Parent = Lighting
    skyAtmoOwned = true
    return skyAtmo
end

local function applySky()
    saveSky()
    local h = cfg.rainbowSky and ((os.clock() * FX.rainbowSpeed) % 1) or FX.skyHue
    local main = Color3.fromHSV(h, FX.skySat, FX.skyVal)
    local deep = Color3.fromHSV(h, math.min(1, FX.skySat + 0.1), FX.skyVal * 0.35)
    local glow = Color3.fromHSV(h, FX.skySat * 0.6, math.min(1, FX.skyVal * 1.15))

    -- the map's own skybox would show through, so it is parked while the custom sky is on
    if skySaved.sky and skySaved.sky.Parent then skySaved.sky.Parent = nil end

    local a = ensureAtmo()
    a.Color, a.Decay = main, deep
    a.Density, a.Offset, a.Glare, a.Haze = 0.42, 0.3, 0.35, 2.6

    Lighting.ColorShift_Top = glow
    Lighting.ColorShift_Bottom = deep
    Lighting.OutdoorAmbient = main:Lerp(Color3.new(0.3, 0.3, 0.3), 0.55)
    Lighting.Ambient = deep:Lerp(Color3.new(0.2, 0.2, 0.2), 0.35)
    Lighting.ClockTime = FX.clock

    if FX.fog > 0.02 then
        Lighting.FogColor = main:Lerp(deep, 0.35)
        Lighting.FogStart = 0
        Lighting.FogEnd = 100000 * (0.0025 ^ FX.fog)
    else
        Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd =
            skySaved.FogColor, skySaved.FogStart, skySaved.FogEnd
    end

    if FX.tint > 0.02 then
        if not (skyTint and skyTint.Parent) then
            skyTint = Instance.new("ColorCorrectionEffect")
            skyTint.Name = "ArHubTint"
            skyTint.Parent = Lighting
        end
        skyTint.Enabled = true
        skyTint.TintColor = Color3.new(1, 1, 1):Lerp(main:Lerp(Color3.new(1, 1, 1), 0.25), FX.tint)
        skyTint.Saturation = 0.25 * FX.tint
    elseif skyTint then
        skyTint.Enabled = false
    end
end

local function restoreSky()
    local s = skySaved
    if not s then return end
    for _, k in ipairs(SKY_KEYS) do
        pcall(function() Lighting[k] = s[k] end)
    end
    if s.sky and not s.sky.Parent then s.sky.Parent = s.skyParent or Lighting end
    if skyAtmo then
        if skyAtmoOwned then
            skyAtmo:Destroy()
        elseif s.atmoProps then
            for k, v in pairs(s.atmoProps) do
                pcall(function() skyAtmo[k] = v end)
            end
        end
        skyAtmo = nil
    end
    if skyTint then skyTint:Destroy() skyTint = nil end
    skySaved = nil
end

local function applyBloom()
    if FX.bloom > 0.02 then
        if not (skyBloom and skyBloom.Parent) then
            skyBloom = Instance.new("BloomEffect")
            skyBloom.Name = "ArHubBloom"
            skyBloom.Size = 30
            skyBloom.Threshold = 0.85
            skyBloom.Parent = Lighting
        end
        skyBloom.Enabled = true
        skyBloom.Intensity = FX.bloom
    elseif skyBloom then
        skyBloom.Enabled = false
    end
end

-- ---------- neon gun ----------
local gunHL = {}       -- [model] = Highlight
local gunLights = {}   -- [model] = PointLight
local gunParts = {}    -- parts currently recolored
local partBackup = setmetatable({}, { __mode = "k" })  -- [part] = { Material, Color, Transparency }
local nextScan = 0

local function handName(n)
    n = n:lower()
    if n:find("glove", 1, true) or n:find("sleeve", 1, true) or n:find("finger", 1, true)
        or n:find("wrist", 1, true) or n:find("skin", 1, true) then
        return true
    end
    if n:find("hand", 1, true) and not (n:find("handle", 1, true) or n:find("handguard", 1, true)) then
        return true
    end
    if n:find("arm", 1, true) and not (n:find("armor", 1, true) or n:find("armat", 1, true)) then
        return true
    end
    return false
end

local function restorePart(p)
    local b = partBackup[p]
    if b then
        if p.Parent then
            pcall(function()
                p.Material, p.Color, p.Transparency = b[1], b[2], b[3]
            end)
        end
        partBackup[p] = nil
    end
end

local function restoreGun()
    for p in pairs(partBackup) do restorePart(p) end
    for m, hl in pairs(gunHL) do hl:Destroy() gunHL[m] = nil end
    for m, l in pairs(gunLights) do l:Destroy() gunLights[m] = nil end
    gunParts = {}
end

-- viewmodels live under the camera in most FPS games; also catch a "Viewmodel" model in workspace
local function findViewmodels()
    local found = {}
    local cam = workspace.CurrentCamera
    if cam then
        for _, m in ipairs(cam:GetChildren()) do
            if m:IsA("Model") then found[#found + 1] = m end
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name:lower():find("viewmodel", 1, true) then
            found[#found + 1] = m
        end
    end
    return found
end

local function scanGun()
    local models = findViewmodels()
    local live = {}
    for _, m in ipairs(models) do live[m] = true end
    for m, hl in pairs(gunHL) do
        if not live[m] or not m.Parent then hl:Destroy() gunHL[m] = nil end
    end
    for m, l in pairs(gunLights) do
        if not live[m] or not m.Parent then l:Destroy() gunLights[m] = nil end
    end

    local parts = {}
    for _, m in ipairs(models) do
        local hl = gunHL[m]
        if not (hl and hl.Parent) then
            hl = Instance.new("Highlight")
            hl.Name = "ArHubGunFX"
            hl.Adornee = m
            hl.DepthMode = Enum.HighlightDepthMode.Occluded
            hl.Parent = espFolder
            gunHL[m] = hl
        end

        local first = nil
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                first = first or d
                if FX.gunMode ~= 1 and d.Transparency < 0.95 then
                    local skip = false
                    if not cfg.gunHands then
                        local a = d
                        while a and a ~= m do
                            if handName(a.Name) then
                                skip = true
                                break
                            end
                            a = a.Parent
                        end
                    end
                    if not skip then parts[#parts + 1] = d end
                end
            end
        end

        local light = gunLights[m]
        if first and not (light and light.Parent) then
            light = Instance.new("PointLight")
            light.Name = "ArHubGunLight"
            light.Shadows = false
            light.Parent = m.PrimaryPart or first
            gunLights[m] = light
        end
    end

    -- anything patched earlier that is no longer in the target list goes back to normal
    local want = {}
    for _, p in ipairs(parts) do want[p] = true end
    for p in pairs(partBackup) do
        if not want[p] then restorePart(p) end
    end
    gunParts = parts
end

local function paintGun(now)
    local h = cfg.rainbowGun and ((now * FX.rainbowSpeed * 3) % 1) or FX.gunHue
    local col = Color3.fromHSV(h, FX.gunSat, 1)
    local pulse = cfg.pulseGun and (0.65 + 0.35 * math.sin(now * 3.2)) or 1
    local pw = FX.gunPower
    local mode = FX.gunMode

    local fillAlpha = (mode == 1 and (0.15 + 0.6 * pw)) or (mode == 2 and (0.05 + 0.25 * pw)) or (0.1 + 0.35 * pw)
    for _, hl in pairs(gunHL) do
        hl.Enabled = true
        hl.FillColor, hl.OutlineColor = col, col
        hl.FillTransparency = 1 - fillAlpha * pulse
        hl.OutlineTransparency = 0.45 - 0.45 * pw * pulse
    end
    for _, l in pairs(gunLights) do
        l.Color = col
        l.Brightness = (0.4 + 2.6 * pw) * pulse
        l.Range = 6 + 10 * pw
    end

    local material = (mode == 3) and Enum.Material.ForceField or Enum.Material.Neon
    for _, p in ipairs(gunParts) do
        if p.Parent then
            if not partBackup[p] then partBackup[p] = { p.Material, p.Color, p.Transparency } end
            if p.Material ~= material then p.Material = material end
            if p.Color ~= col then p.Color = col end
        end
    end
end

local function fxDirty() nextScan = 0 end

local function fxShutdown()
    cfg.sky, cfg.gunfx = false, false
    pcall(restoreSky)
    pcall(restoreGun)
    if skyBloom then skyBloom:Destroy() skyBloom = nil end
end

do
    local nextSky, nextPost = 0, 0
    bind(RunService.RenderStepped, function()
        local now = os.clock()
        if cfg.sky and (cfg.rainbowSky or now >= nextSky) then
            nextSky = now + 0.4
            pcall(applySky)
        end
        if now >= nextPost then
            nextPost = now + 0.5
            pcall(applyBloom)
        end
        if cfg.gunfx then
            if now >= nextScan then
                nextScan = now + 0.3
                pcall(scanGun)
            end
            pcall(paintGun, now)
        end
    end)
end

-- ===== MENU (ArHub v2) =====
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local C = {
    bg0    = Color3.fromRGB(9, 3, 5),
    bg1    = Color3.fromRGB(21, 7, 11),
    row    = Color3.fromRGB(32, 11, 17),
    rowHi  = Color3.fromRGB(50, 16, 24),
    line   = Color3.fromRGB(70, 20, 28),
    blood  = Color3.fromRGB(198, 14, 30),
    bright = Color3.fromRGB(255, 54, 64),
    deep   = Color3.fromRGB(106, 6, 16),
    text   = Color3.fromRGB(246, 234, 234),
    dim    = Color3.fromRGB(160, 120, 126),
    off    = Color3.fromRGB(62, 32, 38),
}
local TITLE_FONT = Enum.Font.Creepster
local BODY = Enum.Font.GothamMedium
local BOLD = Enum.Font.GothamBold
local WHITE = Color3.new(1, 1, 1)
local CENTER = Enum.TextXAlignment.Center
local SINE = Enum.EasingStyle.Sine
local INOUT = Enum.EasingDirection.InOut

-- ---------- tiny builders ----------
local function tween(inst, t, props, style, dir)
    local tw = TweenService:Create(inst,
        TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function corner(inst, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0)
    c.Parent = inst
    return c
end

local function stroke(inst, color, thick, transp)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thick or 1
    s.Transparency = transp or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function tstroke(label, color, thick)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thick or 1
    s.Parent = label
    return s
end

local function grad(inst, seq, rot)
    local g = Instance.new("UIGradient")
    g.Color = seq
    g.Rotation = rot or 90
    g.Parent = inst
    return g
end

local function mkBox(parent, props)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundColor3 = C.bg1
    for k, v in pairs(props or {}) do f[k] = v end
    f.Parent = parent
    return f
end

local function mkText(parent, str, size, color, font, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.Text = str
    l.TextSize = size
    l.TextColor3 = color
    l.Font = font or BODY
    l.TextXAlignment = Enum.TextXAlignment.Left
    for k, v in pairs(props or {}) do l[k] = v end
    l.Parent = parent
    return l
end

local function mkHit(parent, props)
    local b = Instance.new("TextButton")
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = ""
    b.Size = UDim2.fromScale(1, 1)
    for k, v in pairs(props or {}) do b[k] = v end
    b.Parent = parent
    return b
end

local function isPress(i)
    return i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1
end

-- red ripple that grows from the touch point (horizontal only: robust against scaling)
local function ripple(host, xAbs)
    local aw = host.AbsoluteSize.X
    if aw <= 0 then return end
    local rel = math.clamp((xAbs - host.AbsolutePosition.X) / aw, 0, 1)
    local r = mkBox(host, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(rel, 0, 0.5, 0),
        Size = UDim2.fromOffset(0, 0), BackgroundColor3 = C.bright, BackgroundTransparency = 0.55,
        ZIndex = host.ZIndex + 1 })
    corner(r)
    local tw = tween(r, 0.55, { Size = UDim2.fromOffset(240, 240), BackgroundTransparency = 1 })
    tw.Completed:Connect(function() r:Destroy() end)
end

-- drag by a handle; a tap (no movement) calls onTap; pressScale squishes on touch
local function makeDraggable(handle, target, onTap, pressScale)
    pcall(function() handle.Active = true end)
    local dragging, moved, start, origin, dragInput = false, false, nil, nil, nil
    bind(handle.InputBegan, function(i)
        if isPress(i) then
            dragging, moved, start, origin, dragInput = true, false, i.Position, target.Position, i
            if pressScale then tween(pressScale, 0.12, { Scale = 0.9 }) end
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i == dragInput or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = i.Position - start
            if d.Magnitude > 8 then moved = true end
            if moved then
                target.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X,
                    origin.Y.Scale, origin.Y.Offset + d.Y)
            end
        end
    end)
    bind(UIS.InputEnded, function(i)
        if dragging and (i == dragInput or i.UserInputType == Enum.UserInputType.MouseButton1) then
            dragging = false
            if pressScale then tween(pressScale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back) end
            if not moved and onTap then onTap() end
        end
    end)
end

-- ---------- page widgets ----------
local function addSection(page, order, str)
    return mkText(page, str, 10, C.blood, BOLD, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 16) })
end

local function addNote(page, order, str)
    return mkText(page, str, 11, C.dim, BODY, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
end

local function addToggle(page, order, str, key, cb)
    local row = mkBox(page, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.row, ClipsDescendants = true })
    corner(row, 8)
    local rowStroke = stroke(row, C.line, 1, 0.35)

    local bar = mkBox(row, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 0), BackgroundColor3 = C.bright })
    corner(bar)

    local lbl = mkText(row, str, 13, C.dim, BODY, { Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -70, 1, 0) })

    local track = mkBox(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(40, 20), BackgroundColor3 = C.off })
    corner(track)
    local trackStroke = stroke(track, C.line, 1, 0.2)

    local knob = mkBox(track, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.dim })
    corner(knob)

    local hit = mkHit(row, { ZIndex = 5 })

    local function refresh(animate)
        local on = cfg[key]
        local t = animate and 0.24 or 0
        tween(track, t, { BackgroundColor3 = on and C.blood or C.off })
        tween(trackStroke, t, { Color = on and C.bright or C.line })
        tween(knob, t, { Position = on and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = on and WHITE or C.dim }, Enum.EasingStyle.Back)
        tween(lbl, t, { TextColor3 = on and C.text or C.dim })
        tween(bar, t, { Size = on and UDim2.fromOffset(3, 18) or UDim2.fromOffset(3, 0) })
        tween(rowStroke, t, { Color = on and C.deep or C.line })
    end
    refresh(false)

    bind(hit.MouseButton1Down, function(x) ripple(row, x) end)
    bind(hit.MouseEnter, function() tween(row, 0.15, { BackgroundColor3 = C.rowHi }) end)
    bind(hit.MouseLeave, function() tween(row, 0.25, { BackgroundColor3 = C.row }) end)
    bind(hit.MouseButton1Click, function()
        cfg[key] = not cfg[key]
        if cb then
            local ok, err = pcall(cb, cfg[key])
            if not ok then toast("Error: " .. tostring(err):sub(1, 40)) end
        end
        refresh(true)
    end)
    return row, refresh
end

local function addSlider(page, order, str, min, max, init, fmt, onChange, rainbow)
    local row = mkBox(page, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.row })
    corner(row, 8)
    stroke(row, C.line, 1, 0.35)

    mkText(row, str, 13, C.text, BODY, { Position = UDim2.fromOffset(12, 5), Size = UDim2.new(0.6, 0, 0, 18) })
    local val = mkText(row, "", 12, C.bright, BOLD, { Position = UDim2.new(0.5, 0, 0, 5),
        Size = UDim2.new(0.5, -12, 0, 18), TextXAlignment = Enum.TextXAlignment.Right })

    local track = mkBox(row, { Position = UDim2.fromOffset(12, 31), Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = C.off })
    corner(track)
    local fill = mkBox(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE })
    corner(fill)
    grad(fill, ColorSequence.new(C.deep, C.bright), 0)
    if rainbow then
        -- hue slider: the whole track shows the rainbow
        fill.BackgroundTransparency = 1
        track.BackgroundColor3 = WHITE
        local keys = {}
        for k = 0, 6 do
            keys[#keys + 1] = ColorSequenceKeypoint.new(k / 6, Color3.fromHSV((k / 6) % 1, 1, 1))
        end
        grad(track, ColorSequence.new(keys), 0)
    end
    local knob = mkBox(track, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE, ZIndex = 3 })
    corner(knob)
    stroke(knob, C.bright, 2, 0)

    local hit = mkHit(row, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), ZIndex = 5 })

    local function setRel(rel, silent)
        rel = math.clamp(rel, 0, 1)
        local v = min + (max - min) * rel
        fill.Size = UDim2.fromScale(rel, 1)
        knob.Position = UDim2.fromScale(rel, 0.5)
        if rainbow then knob.BackgroundColor3 = Color3.fromHSV(rel % 1, 1, 1) end
        val.Text = fmt(v)
        if onChange and not silent then onChange(v) end
    end
    setRel((init - min) / (max - min), true)

    local dragging, dragInput = false, nil
    local function fromX(x)
        local aw = track.AbsoluteSize.X
        if aw > 0 then setRel((x - track.AbsolutePosition.X) / aw, false) end
    end
    bind(hit.InputBegan, function(i)
        if isPress(i) then
            dragging, dragInput = true, i
            page.ScrollingEnabled = false
            fromX(i.Position.X)
            tween(knob, 0.14, { Size = UDim2.fromOffset(19, 19) }, Enum.EasingStyle.Back)
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i == dragInput or i.UserInputType == Enum.UserInputType.MouseMovement) then
            fromX(i.Position.X)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if dragging and (i == dragInput or i.UserInputType == Enum.UserInputType.MouseButton1) then
            dragging = false
            page.ScrollingEnabled = true
            tween(knob, 0.2, { Size = UDim2.fromOffset(14, 14) }, Enum.EasingStyle.Back)
        end
    end)
    -- second return: a setter so presets can move the slider without firing onChange
    return row, function(v) setRel((v - min) / (max - min), true) end
end

local function addButton(page, order, str, danger, onClick)
    local row = mkBox(page, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = WHITE, ClipsDescendants = true })
    corner(row, 8)
    if danger then
        grad(row, ColorSequence.new(Color3.fromRGB(196, 14, 30), Color3.fromRGB(96, 4, 14)), 90)
    else
        grad(row, ColorSequence.new(Color3.fromRGB(58, 18, 26), Color3.fromRGB(30, 10, 15)), 90)
    end
    local st = stroke(row, danger and C.bright or C.line, 1, danger and 0.3 or 0.15)
    local lbl = mkText(row, str, 13, C.text, BOLD, { Size = UDim2.fromScale(1, 1),
        TextXAlignment = CENTER, ZIndex = 3 })
    local hit = mkHit(row, { ZIndex = 6 })
    bind(hit.MouseButton1Down, function(x) ripple(row, x) end)
    bind(hit.MouseEnter, function() tween(st, 0.15, { Transparency = 0, Color = C.bright }) end)
    bind(hit.MouseLeave, function()
        tween(st, 0.25, { Transparency = danger and 0.3 or 0.15, Color = danger and C.bright or C.line })
    end)
    bind(hit.MouseButton1Click, function()
        local ok, err = pcall(onClick, lbl)
        if not ok then toast("Error: " .. tostring(err):sub(1, 40)) end
    end)
    return row
end

-- segmented control with a sliding pill: addChoice(page, order, "Style", {"A","B","C"}, 2, onChange)
local function addChoice(page, order, str, options, init, onChange)
    local row = mkBox(page, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.row })
    corner(row, 8)
    stroke(row, C.line, 1, 0.35)
    mkText(row, str, 13, C.text, BODY, { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 18) })
    local seg = mkBox(row, { Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 20),
        BackgroundColor3 = C.off })
    corner(seg, 6)
    local n = #options
    local pill = mkBox(seg, { Size = UDim2.new(1 / n, -4, 1, -4), Position = UDim2.new(0, 2, 0, 2),
        BackgroundColor3 = WHITE })
    corner(pill, 5)
    grad(pill, ColorSequence.new(C.bright, C.blood), 90)
    local labels = {}
    local function pick(i, animate, silent)
        tween(pill, animate and 0.28 or 0, { Position = UDim2.new((i - 1) / n, 2, 0, 2) }, Enum.EasingStyle.Back)
        for k, l in ipairs(labels) do
            tween(l, 0.2, { TextColor3 = (k == i) and WHITE or C.dim })
        end
        if onChange and not silent then onChange(i) end
    end
    for i, name in ipairs(options) do
        local b = mkHit(seg, { Position = UDim2.new((i - 1) / n, 0, 0, 0), Size = UDim2.new(1 / n, 0, 1, 0),
            Text = name, TextSize = 11, Font = BOLD, TextColor3 = C.dim, ZIndex = 3 })
        labels[i] = b
        bind(b.MouseButton1Click, function() pick(i, true, false) end)
    end
    pick(init, false, true)
    return row, function(i) pick(i, true, true) end
end

-- grid of color chips: list = { { name = "..", h = 0-1, s = 0-1, v = 0-1 }, ... }
local function addPresets(page, order, list, onPick)
    local cols = 4
    local rowsN = math.ceil(#list / cols)
    local host = mkBox(page, { LayoutOrder = order, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, rowsN * 34 + (rowsN - 1) * 6) })
    local gl = Instance.new("UIGridLayout")
    gl.CellSize = UDim2.new(1 / cols, -5, 0, 34)
    gl.CellPadding = UDim2.fromOffset(6, 6)
    gl.SortOrder = Enum.SortOrder.LayoutOrder
    gl.Parent = host
    for i, p in ipairs(list) do
        local v = math.max(p.v or 1, 0.55)
        local c1 = Color3.fromHSV(p.h, p.s, v)
        local c2 = Color3.fromHSV(p.h, math.min(1, p.s + 0.1), v * 0.45)
        local chip = mkBox(host, { LayoutOrder = i, BackgroundColor3 = WHITE, ClipsDescendants = true })
        corner(chip, 8)
        grad(chip, ColorSequence.new(c1, c2), 45)
        stroke(chip, c1, 1, 0.45)
        local nm = mkText(chip, p.name, 10, WHITE, BOLD, { Size = UDim2.fromScale(1, 1),
            TextXAlignment = CENTER, ZIndex = 3 })
        tstroke(nm, Color3.new(0, 0, 0), 1).Transparency = 0.5
        local hit = mkHit(chip, { ZIndex = 6 })
        bind(hit.MouseButton1Down, function(x) ripple(chip, x) end)
        bind(hit.MouseButton1Click, function()
            local ok, err = pcall(onPick, p, i)
            if not ok then toast("Error: " .. tostring(err):sub(1, 40)) end
        end)
    end
    return host
end

local SKY_PRESETS = {
    { name = "Blood Moon", h = 0.99, s = 0.95, v = 0.70, clock = 0,    tint = 0.35 },
    { name = "Neon Dusk",  h = 0.83, s = 0.85, v = 0.85, clock = 18.5, tint = 0.25 },
    { name = "Toxic",      h = 0.30, s = 0.90, v = 0.80, clock = 22,   tint = 0.30 },
    { name = "Void",       h = 0.72, s = 0.90, v = 0.35, clock = 0,    tint = 0.40 },
    { name = "Ice",        h = 0.54, s = 0.55, v = 0.95, clock = 12,   tint = 0.20 },
    { name = "Sunset",     h = 0.06, s = 0.90, v = 0.95, clock = 17.8, tint = 0.20 },
    { name = "Cyber",      h = 0.50, s = 0.90, v = 0.80, clock = 21,   tint = 0.30 },
    { name = "Gold",       h = 0.12, s = 0.85, v = 0.90, clock = 16,   tint = 0.18 },
}
local GUN_PRESETS = {
    { name = "Blood",  h = 0.99, s = 1.00 }, { name = "Pink",  h = 0.92, s = 0.75 },
    { name = "Cyan",   h = 0.50, s = 1.00 }, { name = "Lime",  h = 0.27, s = 1.00 },
    { name = "Gold",   h = 0.13, s = 1.00 }, { name = "Violet", h = 0.76, s = 1.00 },
    { name = "Ice",    h = 0.55, s = 0.35 }, { name = "White", h = 0.00, s = 0.00 },
}

local function degFmt(v) return math.floor(v * 360 + 0.5) .. " deg" end
local function pctFmt(v) return math.floor(v * 100 + 0.5) .. "%" end

-- fills the extra color sliders on VISUALS plus the WORLD and GUN FX pages
local function buildFxPages(pVisuals, pWorld, pGun)
    -- ESP colors
    addSection(pVisuals, 7, "C O L O R S")
    addSlider(pVisuals, 8, "Enemy Color", 0, 1, 0, degFmt,
        function(v) COL.enemy = Color3.fromHSV(v, 0.85, 1) end, true)
    addSlider(pVisuals, 9, "Team Color", 0, 1, 0.6, degFmt,
        function(v) COL.friend = Color3.fromHSV(v, 0.85, 1) end, true)

    -- ----- WORLD -----
    local skyRefresh, rainbowRefresh
    local hueSet, valSet, clockSet, tintSet, bloomSet
    local ignore

    local function skyOn()
        if not cfg.sky then
            cfg.sky = true
            if skyRefresh then skyRefresh(true) end
        end
        pcall(applySky)
    end

    addSection(pWorld, 1, "S K Y")
    ignore, skyRefresh = addToggle(pWorld, 2, "Custom Sky", "sky", function(on)
        if on then pcall(applySky) else pcall(restoreSky) end
    end)
    ignore, rainbowRefresh = addToggle(pWorld, 3, "Rainbow Sky", "rainbowSky", function(on)
        if on then skyOn() end
    end)
    addPresets(pWorld, 4, SKY_PRESETS, function(p)
        FX.skyHue, FX.skySat, FX.skyVal, FX.clock, FX.tint = p.h, p.s, p.v, p.clock, p.tint
        if cfg.rainbowSky then
            cfg.rainbowSky = false
            rainbowRefresh(true)
        end
        hueSet(p.h)
        valSet(p.v)
        clockSet(p.clock)
        tintSet(p.tint)
        skyOn()
        toast("Sky: " .. p.name)
    end)
    ignore, hueSet = addSlider(pWorld, 5, "Sky Hue", 0, 1, FX.skyHue, degFmt,
        function(v) FX.skyHue = v skyOn() end, true)
    ignore, valSet = addSlider(pWorld, 6, "Sky Brightness", 0.15, 1, FX.skyVal, pctFmt,
        function(v) FX.skyVal = v skyOn() end)
    ignore, clockSet = addSlider(pWorld, 7, "Time of Day", 0, 24, FX.clock,
        function(v) return string.format("%02d:%02d", math.floor(v) % 24, math.floor((v % 1) * 60)) end,
        function(v) FX.clock = v skyOn() end)
    ignore, tintSet = addSlider(pWorld, 8, "World Tint", 0, 0.7, FX.tint, pctFmt,
        function(v) FX.tint = v skyOn() end)
    addSlider(pWorld, 9, "Fog", 0, 1, FX.fog, pctFmt, function(v) FX.fog = v skyOn() end)
    addSection(pWorld, 10, "G L O W")
    ignore, bloomSet = addSlider(pWorld, 11, "Bloom", 0, 3, FX.bloom,
        function(v) return string.format("%.1f", v) end,
        function(v) FX.bloom = v end)
    addSlider(pWorld, 12, "Rainbow Speed", 0.02, 0.4, FX.rainbowSpeed,
        function(v) return string.format("%.2f", v) end,
        function(v) FX.rainbowSpeed = v end)

    -- ----- GUN FX -----
    local gunRefresh, rainbowGunRefresh, gunHueSet, gunSatSet

    local function bumpBloom()
        if FX.bloom < 0.4 then
            FX.bloom = 1.1
            bloomSet(1.1)
        end
    end
    local function gunOn()
        if not cfg.gunfx then
            cfg.gunfx = true
            if gunRefresh then gunRefresh(true) end
            bumpBloom()
        end
        fxDirty()
    end

    addSection(pGun, 1, "N E O N  G U N")
    ignore, gunRefresh = addToggle(pGun, 2, "Neon Gun", "gunfx", function(on)
        if on then
            bumpBloom()
            fxDirty()
            toast("Neon Gun on: equip a weapon")
        else
            pcall(restoreGun)
        end
    end)
    addChoice(pGun, 3, "Style", { "GLOW", "NEON", "GHOST" }, FX.gunMode, function(i)
        FX.gunMode = i
        fxDirty()
    end)
    addPresets(pGun, 4, GUN_PRESETS, function(p)
        FX.gunHue, FX.gunSat = p.h, p.s
        if cfg.rainbowGun then
            cfg.rainbowGun = false
            rainbowGunRefresh(true)
        end
        gunHueSet(p.h)
        gunSatSet(p.s)
        gunOn()
        toast("Gun color: " .. p.name)
    end)
    ignore, gunHueSet = addSlider(pGun, 5, "Gun Hue", 0, 1, FX.gunHue, degFmt,
        function(v) FX.gunHue = v gunOn() end, true)
    ignore, gunSatSet = addSlider(pGun, 6, "Saturation", 0, 1, FX.gunSat, pctFmt,
        function(v) FX.gunSat = v gunOn() end)
    addSlider(pGun, 7, "Glow Power", 0, 1, FX.gunPower, pctFmt, function(v) FX.gunPower = v end)
    ignore, rainbowGunRefresh = addToggle(pGun, 8, "Rainbow Gun", "rainbowGun", function(on)
        if on then gunOn() end
    end)
    addToggle(pGun, 9, "Pulse", "pulseGun")
    addToggle(pGun, 10, "Include Hands", "gunHands", function() fxDirty() end)
    addNote(pGun, 11, "Works on your first-person gun. Turn Bloom up on the WORLD tab for the full neon bleed. GLOW outlines the gun, NEON recolors its parts, GHOST makes it a force-field.")
end

-- ---------- the window ----------
local function buildUI()
    -- the aim ring gets the same blood look
    rs.Color = C.bright
    rs.Transparency = 0.45
    rs.Thickness = 1.5

    local anchor = mkBox(gui, { Name = "ArHubWindow", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 235, 0.5, 0),
        Size = UDim2.fromOffset(360, 250), Visible = false })
    local userScale = Instance.new("UIScale")
    userScale.Parent = anchor

    local pop = mkBox(anchor, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
    local popScale = Instance.new("UIScale")
    popScale.Scale = 0.86
    popScale.Parent = pop

    -- soft blood glow behind the window
    local glows = {}
    for idx, g in ipairs({ { 5, 0.88 }, { 14, 0.93 }, { 26, 0.965 } }) do
        local f = mkBox(pop, { BackgroundColor3 = C.blood, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, g[1] * 2, 1, g[1] * 2) })
        corner(f, 14 + g[1])
        glows[idx] = { f = f, t = g[2] }
    end

    local window = Instance.new("CanvasGroup")
    window.BorderSizePixel = 0
    window.BackgroundColor3 = C.bg1
    window.Size = UDim2.fromScale(1, 1)
    window.GroupTransparency = 1
    window.Parent = pop
    corner(window, 14)

    local bgFill = mkBox(window, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
    grad(bgFill, ColorSequence.new(Color3.fromRGB(34, 9, 15), Color3.fromRGB(8, 3, 5)), 90)
    local sheen = mkBox(window, { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.blood })
    do
        local sg = Instance.new("UIGradient")
        sg.Rotation = 90
        sg.Transparency = NumberSequence.new(0.78, 1)
        sg.Parent = sheen
    end

    -- animated flowing border
    local border = mkBox(pop, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
    corner(border, 14)
    local borderStroke = stroke(border, WHITE, 1.6, 1)
    local borderGrad = grad(borderStroke, ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.deep), ColorSequenceKeypoint.new(0.3, C.bright),
        ColorSequenceKeypoint.new(0.55, C.deep), ColorSequenceKeypoint.new(0.8, C.bright),
        ColorSequenceKeypoint.new(1, C.deep) }), 0)

    -- header
    local header = mkBox(window, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) })
    local logo = mkText(header, "ArHub", 32, WHITE, TITLE_FONT,
        { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(104, 44) })
    local logoStroke = tstroke(logo, C.deep, 1.6)
    grad(logo, ColorSequence.new(Color3.fromRGB(255, 104, 104), Color3.fromRGB(190, 8, 24)), 90)
    TweenService:Create(logoStroke, TweenInfo.new(1.7, SINE, INOUT, -1, true), { Color = C.bright }):Play()
    mkText(header, "BLOXSTRIKE", 9, C.dim, BOLD, { Position = UDim2.fromOffset(120, 0),
        Size = UDim2.fromOffset(80, 44) })

    local fpsLabel = mkText(header, "60 fps", 10, C.dim, BODY, { AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(60, 16),
        TextXAlignment = Enum.TextXAlignment.Right })

    local close = mkHit(header, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0, BackgroundColor3 = C.row })
    corner(close)
    for _, rot in ipairs({ 45, -45 }) do
        mkBox(close, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(12, 2), Rotation = rot, BackgroundColor3 = C.text })
    end
    bind(close.MouseEnter, function() tween(close, 0.15, { BackgroundColor3 = C.blood }) end)
    bind(close.MouseLeave, function() tween(close, 0.2, { BackgroundColor3 = C.row }) end)

    -- glowing divider
    local divider = mkBox(window, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = C.bright })
    do
        local dg = Instance.new("UIGradient")
        dg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.05), NumberSequenceKeypoint.new(1, 1) })
        dg.Parent = divider
    end

    -- tabs
    local TAB_NAMES = { "COMBAT", "VISUALS", "WEAPON", "WORLD", "GUN FX", "MISC" }
    local NT = #TAB_NAMES
    local pages, tabBtns = {}, {}
    local tabsBar = mkBox(window, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 48),
        Size = UDim2.new(1, 0, 0, 28) })
    local indicator = mkBox(tabsBar, { BackgroundColor3 = C.bright, Size = UDim2.new(1 / 6, -22, 0, 2),
        Position = UDim2.new(0, 11, 1, -2) })
    corner(indicator)
    local pageHost = mkBox(window, { BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 1, -80) })

    local current = nil
    local function selectTab(i, instant)
        if current == i then return end
        local prev = current
        current = i
        for k, p in ipairs(pages) do
            if k == i then
                p.Visible = true
                if instant then
                    p.Position = UDim2.fromScale(0, 0)
                else
                    p.Position = UDim2.fromOffset((prev and i < prev) and -26 or 26, 0)
                    tween(p, 0.32, { Position = UDim2.fromScale(0, 0) })
                end
            else
                p.Visible = false
            end
            tween(tabBtns[k], 0.2, { TextColor3 = (k == i) and C.bright or C.dim })
        end
        tween(indicator, instant and 0 or 0.32, { Position = UDim2.new((i - 1) / NT, 11, 1, -2) })
    end

    for i, name in ipairs(TAB_NAMES) do
        local b = mkHit(tabsBar, { Position = UDim2.new((i - 1) / NT, 0, 0, 0), Size = UDim2.new(1 / NT, 0, 1, -2),
            Text = name, TextSize = 10, Font = BOLD, TextColor3 = C.dim })
        tabBtns[i] = b
        bind(b.MouseButton1Click, function() selectTab(i) end)

        local p = Instance.new("ScrollingFrame")
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.Size = UDim2.fromScale(1, 1)
        p.Visible = false
        p.ScrollBarThickness = 2
        p.ScrollBarImageColor3 = C.blood
        p.CanvasSize = UDim2.new()
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.Parent = pageHost
        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 6)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Parent = p
        local pad = Instance.new("UIPadding")
        pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 10)
        pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
        pad.Parent = p
        pages[i] = p
    end

    -- blood dripping from the divider
    for idx, x in ipairs({ 0.04, 0.25, 0.5, 0.75, 0.96 }) do
        local w = (idx % 2 == 0) and 4 or 3
        local d = mkBox(window, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, 45),
            Size = UDim2.fromOffset(w, 5), BackgroundColor3 = C.blood, ZIndex = 4 })
        corner(d)
        local bulb = mkBox(d, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.fromOffset(w + 3, w + 4), BackgroundColor3 = C.bright, ZIndex = 4 })
        corner(bulb)
        TweenService:Create(d, TweenInfo.new(1.5 + idx * 0.41, SINE, INOUT, -1, true),
            { Size = UDim2.fromOffset(w, 11 + (idx * 5) % 9) }):Play()
    end

    -- ----- content -----
    local pCombat, pVisuals, pWeapon = pages[1], pages[2], pages[3]
    local pWorld, pGun, pMisc = pages[4], pages[5], pages[6]
    buildFxPages(pVisuals, pWorld, pGun)

    addSection(pCombat, 1, "A I M")
    addToggle(pCombat, 2, "Aimbot", "aimbot", function(on) ring.Visible = on end)
    addSlider(pCombat, 3, "Aim Strength", 0.15, 1, AIM.smooth,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        function(v) AIM.smooth = v end)
    addSlider(pCombat, 4, "Aim FOV", 40, 300, AIM.fov,
        function(v) return math.floor(v + 0.5) .. " px" end,
        function(v)
            AIM.fov = math.floor(v + 0.5)
            ring.Size = UDim2.fromOffset(AIM.fov * 2, AIM.fov * 2)
        end)
    addSection(pCombat, 5, "F I R E")
    addToggle(pCombat, 6, "Triggerbot", "trigger")
    addToggle(pCombat, 7, "Wall Check", "wallcheck")

    addSection(pVisuals, 1, "E S P")
    addToggle(pVisuals, 2, "Chams", "chams")
    addToggle(pVisuals, 3, "Names", "names")
    addToggle(pVisuals, 4, "Health", "health")
    addToggle(pVisuals, 5, "Teammates", "team")
    addSlider(pVisuals, 6, "ESP Players", 1, 16, MAX_ESP,
        function(v) return tostring(math.floor(v + 0.5)) end,
        function(v) MAX_ESP = math.floor(v + 0.5) end)

    addSection(pWeapon, 1, "G U N")
    addToggle(pWeapon, 2, "No Recoil", "norecoil", function(on)
        local n = setNoRecoil(on)
        if on then
            toast(n > 0 and ("No Recoil: " .. n .. " parts patched, re-equip your gun")
                or "No Recoil: nothing found yet")
        else
            toast("No Recoil: restored")
        end
    end)
    addToggle(pWeapon, 3, "No Spread", "nospread", setNoSpread)
    addNote(pWeapon, 4, "Switch to another weapon and back after turning these on, so the game picks up the new values.")

    local function doUnload()
        running = false
        RunService:UnbindFromRenderStep("BX_Aim")
        pcall(setNoRecoil, false)
        spreadOn = false
        pcall(unhookSpread)
        pcall(restoreSpread)
        pcall(fxShutdown)
        clearAll()
    end

    addSection(pMisc, 1, "M E N U")
    addSlider(pMisc, 2, "Menu Size", 0.7, 1.25, 1,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        function(v) userScale.Scale = v end)
    addButton(pMisc, 3, "COPY INFO", false, function()
        task.spawn(function()
            local ok, err = pcall(dumpInfo)
            if not ok then toast("Info failed: " .. tostring(err):sub(1, 40)) end
        end)
    end)

    -- window open / close animation
    local isOpen = false
    local function setOpen(open)
        if open == isOpen then return end
        isOpen = open
        if open then
            anchor.Visible = true
            popScale.Scale = 0.86
            window.GroupTransparency = 1
            tween(popScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
            tween(window, 0.35, { GroupTransparency = 0 })
            tween(borderStroke, 0.45, { Transparency = 0.1 })
            for _, g in ipairs(glows) do tween(g.f, 0.55, { BackgroundTransparency = g.t }) end
        else
            tween(window, 0.22, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            tween(borderStroke, 0.22, { Transparency = 1 })
            for _, g in ipairs(glows) do tween(g.f, 0.22, { BackgroundTransparency = 1 }) end
            local tw = tween(popScale, 0.22, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            tw.Completed:Connect(function()
                if not isOpen then anchor.Visible = false end
            end)
        end
    end
    bind(close.MouseButton1Click, function() setOpen(false) end)
    makeDraggable(header, anchor, nil, nil)
    selectTab(1, true)

    -- floating button
    local fab = mkBox(gui, { Name = "ArHubButton", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 43, 0.5, 0),
        Size = UDim2.fromOffset(46, 46), Visible = false })
    local fabScale = Instance.new("UIScale")
    fabScale.Parent = fab
    local pulse = mkBox(fab, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46) })
    corner(pulse)
    local pulseStroke = stroke(pulse, C.bright, 2, 0.2)
    local loop = TweenInfo.new(1.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false)
    TweenService:Create(pulse, loop, { Size = UDim2.fromOffset(82, 82) }):Play()
    TweenService:Create(pulseStroke, loop, { Transparency = 1 }):Play()
    local core = mkBox(fab, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
    corner(core)
    grad(core, ColorSequence.new(Color3.fromRGB(58, 12, 20), Color3.fromRGB(12, 4, 6)), 90)
    local coreStroke = stroke(core, WHITE, 2, 0)
    local coreGrad = grad(coreStroke, ColorSequence.new({ ColorSequenceKeypoint.new(0, C.deep),
        ColorSequenceKeypoint.new(0.5, C.bright), ColorSequenceKeypoint.new(1, C.deep) }), 0)
    local letter = mkText(fab, "A", 30, WHITE, TITLE_FONT, { Size = UDim2.fromScale(1, 1),
        TextXAlignment = CENTER, ZIndex = 3 })
    grad(letter, ColorSequence.new(Color3.fromRGB(255, 110, 110), Color3.fromRGB(190, 8, 24)), 90)
    tstroke(letter, C.deep, 1.2)
    local fabHit = mkHit(fab, { ZIndex = 6 })
    makeDraggable(fabHit, fab, function() setOpen(not isOpen) end, fabScale)

    -- fps counter + spinning border gradients
    local frames, last = 0, os.clock()
    bind(RunService.RenderStepped, function()
        frames += 1
        local now = os.clock()
        if isOpen then borderGrad.Rotation = (now * 70) % 360 end
        if fab.Visible then coreGrad.Rotation = (now * 120) % 360 end
        if now - last >= 0.5 then
            fpsLabel.Text = math.floor(frames / (now - last) + 0.5) .. " fps"
            frames, last = 0, now
        end
    end)

    -- styled notifications (replaces the plain pop-up from before)
    local toastFrame = nil
    toast = function(msg)
        if toastFrame then toastFrame:Destroy() end
        local f = mkBox(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -50),
            Size = UDim2.fromOffset(310, 34), BackgroundColor3 = C.bg1, ZIndex = 50 })
        toastFrame = f
        corner(f, 10)
        stroke(f, C.blood, 1.2, 0.2)
        local acc = mkBox(f, { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(0, 4, 1, -12),
            BackgroundColor3 = C.bright, ZIndex = 51 })
        corner(acc)
        mkText(f, msg, 12, C.text, BODY, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -30, 1, 0),
            ZIndex = 51, TextTruncate = Enum.TextTruncate.AtEnd })
        tween(f, 0.45, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Back)
        task.delay(3, function()
            if f.Parent then
                local tw = tween(f, 0.3, { Position = UDim2.new(0.5, 0, 0, -50) },
                    Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                tw.Completed:Connect(function() f:Destroy() end)
            end
        end)
    end

    -- unload (asks twice so a stray tap does not kill it)
    local armed = false
    addButton(pMisc, 4, "UNLOAD", true, function(lbl)
        if not armed then
            armed = true
            lbl.Text = "TAP AGAIN TO CONFIRM"
            task.delay(2.5, function()
                armed = false
                if lbl.Parent then lbl.Text = "UNLOAD" end
            end)
            return
        end
        doUnload()
        setOpen(false)
        tween(fabScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        task.delay(0.4, function()
            for _, c in ipairs(conns) do c:Disconnect() end
            gui:Destroy()
        end)
    end)

    return { setOpen = setOpen, fab = fab, fabScale = fabScale }
end

-- ---------- intro ----------
local introOverlay = nil
local function playIntro()
    local skipped = false
    local overlay = Instance.new("TextButton")
    introOverlay = overlay
    overlay.Name = "ArHubIntro"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BorderSizePixel = 0
    overlay.AutoButtonColor = false
    overlay.Text = ""
    overlay.ZIndex = 100
    overlay.ClipsDescendants = true
    overlay.Parent = gui
    bind(overlay.MouseButton1Click, function() skipped = true end)
    task.delay(14, function() if overlay.Parent then overlay:Destroy() end end)

    local function pause(t)
        local e = os.clock() + t
        while os.clock() < e and not skipped and running do task.wait(0.03) end
    end

    -- red fog, heavier at the top and bottom edges
    local fog = mkBox(overlay, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 0, 10),
        BackgroundTransparency = 1, ZIndex = 101 })
    do
        local fg = Instance.new("UIGradient")
        fg.Rotation = 90
        fg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(0.45, 0.93), NumberSequenceKeypoint.new(1, 0.5) })
        fg.Parent = fog
    end
    tween(fog, 1.2, { BackgroundTransparency = 0 })

    -- pulsing glow behind the logo
    for i = 1, 4 do
        local s = 120 + i * 90
        local g = mkBox(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44),
            Size = UDim2.fromOffset(s, s), BackgroundColor3 = Color3.fromRGB(150, 6, 18),
            BackgroundTransparency = 1, ZIndex = 102 })
        corner(g)
        tween(g, 1.4, { BackgroundTransparency = 0.8 + i * 0.04 })
        TweenService:Create(g, TweenInfo.new(1.7 + i * 0.25, SINE, INOUT, -1, true),
            { Size = UDim2.fromOffset(s + 44, s + 44) }):Play()
    end

    -- blood splatters popping in
    for _ = 1, 16 do
        local s = math.random(4, 16)
        local sp = mkBox(overlay, { AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.12 + math.random() * 0.76, 0.2 + math.random() * 0.6),
            Size = UDim2.fromOffset(0, 0), BackgroundColor3 = Color3.fromRGB(150, 4, 16), ZIndex = 103 })
        corner(sp)
        task.delay(0.3 + math.random() * 2, function()
            if sp.Parent then tween(sp, 0.35, { Size = UDim2.fromOffset(s, s) }, Enum.EasingStyle.Back) end
        end)
    end

    -- blood curtain with long drips running down the screen
    local curtain = mkBox(overlay, { Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = WHITE, ZIndex = 105 })
    grad(curtain, ColorSequence.new(Color3.fromRGB(200, 12, 28), Color3.fromRGB(120, 2, 10)), 90)
    tween(curtain, 0.9, { Size = UDim2.new(1, 0, 0, 30) })
    local N = 26
    for i = 1, N do
        local w = math.random(3, 9)
        local xs = (i - 0.5) / N + (math.random() - 0.5) * (0.6 / N)
        local len = 0.1 + math.random() * 0.38
        local d = mkBox(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(xs, 0, 0, 20),
            Size = UDim2.new(0, w, 0, 0), BackgroundColor3 = WHITE, ZIndex = 104 })
        grad(d, ColorSequence.new(Color3.fromRGB(205, 14, 30), Color3.fromRGB(112, 2, 10)), 90)
        corner(d)
        local bulb = mkBox(d, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1),
            Size = UDim2.fromOffset(w + 4, w + 5), BackgroundColor3 = Color3.fromRGB(112, 2, 10), ZIndex = 104 })
        corner(bulb)
        task.delay(math.random() * 1.0, function()
            if d.Parent then
                tween(d, 1.4 + math.random() * 1.6, { Size = UDim2.new(0, w, len, 0) }, Enum.EasingStyle.Quart)
            end
        end)
    end

    -- the logo, one letter at a time
    local word = "ArHub"
    local row = mkBox(overlay, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(400, 110), ZIndex = 110 })
    local rowScale = Instance.new("UIScale")
    rowScale.Parent = row
    local lay = Instance.new("UIListLayout")
    lay.FillDirection = Enum.FillDirection.Horizontal
    lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lay.VerticalAlignment = Enum.VerticalAlignment.Center
    lay.Padding = UDim.new(0, 2)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = row
    local letters = {}
    for i = 1, #word do
        local ch = word:sub(i, i)
        local w = 54
        local ok, sz = pcall(function()
            return TextService:GetTextSize(ch, 96, TITLE_FONT, Vector2.new(500, 500))
        end)
        if ok and sz then w = sz.X + 2 end
        local cell = mkBox(row, { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, 110),
            LayoutOrder = i, ZIndex = 110 })
        local l = mkText(cell, ch, 96, WHITE, TITLE_FONT, { Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromOffset(0, -50), TextTransparency = 1, TextXAlignment = CENTER, ZIndex = 111 })
        local ls = tstroke(l, Color3.fromRGB(60, 0, 6), 3)
        ls.Transparency = 1
        grad(l, ColorSequence.new(Color3.fromRGB(255, 96, 96), Color3.fromRGB(150, 6, 20)), 90)
        letters[i] = { l = l, s = ls }
    end
    for _, L in ipairs(letters) do
        if skipped then break end
        tween(L.l, 0.5, { Position = UDim2.fromOffset(0, 0), TextTransparency = 0 }, Enum.EasingStyle.Back)
        tween(L.s, 0.5, { Transparency = 0 })
        pause(0.13)
    end
    pause(0.4)
    for _, L in ipairs(letters) do
        L.l.Position = UDim2.fromOffset(0, 0)
        L.l.TextTransparency = 0
        L.s.Transparency = 0
    end

    -- glitch flicker + red flash
    if not skipped then
        local flash = mkBox(overlay, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 30, 40),
            BackgroundTransparency = 0.55, ZIndex = 130 })
        local ft = tween(flash, 0.5, { BackgroundTransparency = 1 })
        ft.Completed:Connect(function() flash:Destroy() end)
        for _ = 1, 7 do
            if skipped then break end
            for _, L in ipairs(letters) do
                L.l.Position = UDim2.fromOffset(math.random(-5, 5), math.random(-3, 3))
            end
            pause(0.045)
        end
        for _, L in ipairs(letters) do L.l.Position = UDim2.fromOffset(0, 0) end
    end

    -- subtitle + fake loading bar
    local sub = mkText(overlay, "W E L C O M E", 15, Color3.fromRGB(210, 38, 50), BOLD,
        { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.44, 66),
            Size = UDim2.fromOffset(300, 22), TextXAlignment = CENTER, TextTransparency = 1, ZIndex = 110 })
    tween(sub, 0.8, { TextTransparency = 0 })
    local barBg = mkBox(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.44, 100),
        Size = UDim2.fromOffset(230, 4), BackgroundColor3 = Color3.fromRGB(44, 8, 12), ZIndex = 110 })
    corner(barBg)
    local barFill = mkBox(barBg, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, ZIndex = 111 })
    corner(barFill)
    grad(barFill, ColorSequence.new(C.deep, C.bright), 0)
    local status = mkText(overlay, "", 11, C.dim, BODY, { AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0.44, 112), Size = UDim2.fromOffset(300, 16),
        TextXAlignment = CENTER, ZIndex = 110 })
    local hint = mkText(overlay, "tap to skip", 10, C.dim, BODY, { AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(200, 14),
        TextXAlignment = CENTER, TextTransparency = 0.5, ZIndex = 110 })
    local steps = { "calibrating", "mapping modules", "arming", "ready" }
    for i, s in ipairs(steps) do
        if skipped then break end
        status.Text = s .. "  " .. (i * 25) .. "%"
        tween(barFill, 0.4, { Size = UDim2.fromScale(i / #steps, 1) })
        pause(0.42)
    end
    pause(0.3)

    -- exit: everything fades while the logo pushes toward the camera
    local dur = skipped and 0.35 or 0.75
    local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    for _, d in ipairs(overlay:GetDescendants()) do
        local props = nil
        if d:IsA("TextLabel") then
            props = { TextTransparency = 1, BackgroundTransparency = 1 }
        elseif d:IsA("GuiObject") then
            props = { BackgroundTransparency = 1 }
        elseif d:IsA("UIStroke") then
            props = { Transparency = 1 }
        end
        if props then TweenService:Create(d, info, props):Play() end
    end
    TweenService:Create(overlay, info, { BackgroundTransparency = 1 }):Play()
    tween(rowScale, dur, { Scale = 1.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    task.wait(dur + 0.05)
    overlay:Destroy()
end

local ui = buildUI()
task.spawn(function()
    pcall(playIntro)
    if introOverlay then introOverlay:Destroy() end
    if not running then return end
    ui.fab.Visible = true
    ui.fabScale.Scale = 0
    tween(ui.fabScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
    ui.setOpen(true)
end)
