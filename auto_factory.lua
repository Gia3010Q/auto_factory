--[[
    ╔═════════════════════════════════════════════════════╗
    ║    AUTO FACTORY + AUTO FRUIT - BLOX FRUITS SEA 2    ║
    ║   Viết lại từ Banana Cat Hub (deobfuscated source)  ║
    ║   Boss: Core  │  Sea: Second Sea                    ║
    ╚═════════════════════════════════════════════════════╝

    TÍNH NĂNG:
    ✅ Auto tìm & đánh boss Core (Factory Sea 2)
    ✅ Auto tìm Fruit rơi trong map
    ✅ Auto tele đến Fruit và nhặt
    ✅ Auto Random Devil Fruit theo logic Cousin/Banner gốc
    ✅ Auto lưu Fruit vừa nhặt vào Storage
    ✅ Anti-AFK, tránh bị kick khi treo máy
    ✅ GUI đẹp có thể kéo, nút STOP, hiện trạng thái

    CÁCH DÙNG:
    1. Paste vào executor và chạy
    2. Để ít nhất 1 Fighting Style (ToolTip = Melee) trong Backpack
    3. Dừng bằng nút STOP hoặc:  getgenv().AutoFactory = false
]]

-- ─────────────────────────────────────────────
-- SERVICES
-- ─────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local VIM               = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")
local CollectionService = game:GetService("CollectionService")

local lp = Players.LocalPlayer

-- ─────────────────────────────────────────────
-- CONFIG (tự chỉnh)
-- ─────────────────────────────────────────────
local CFG = {
    -- Factory
    CoreOffsetY   = 20,     -- Offset gốc của Auto Factory
    AttackRange   = 30,     -- AttackFunction gốc dùng range 30
    LoopDelay     = 0.05,   -- Delay vòng lặp (giây)
    M1HoldTime    = 0.05,   -- Thời gian giữ chuột cho mỗi đòn Melee
    UseCombatRemotes = true, -- AttackFunction gốc; lỗi thì fallback input
    RemoteAttackDelay = 0.12,
    MoveSpeed         = 300,  -- Tốc độ di chuyển tới Core (studs/s)
    CoreSnapDistance  = 150,  -- toTarget(cf): snap khi đã gần
    FruitSnapDistance = 8,    -- toTarget(cf, true): ngưỡng gốc

    -- Fruit
    FruitEnabled  = true,   -- Bật/tắt tính năng tìm fruit
    FruitRange    = 0,      -- <= 0: không giới hạn, quét mọi Fruit trong cùng Sea
    FruitMoveSpeed = 150,  -- Tốc độ di chuyển tới Fruit (studs/s)
    PickupDist    = 5,       -- Khoảng cách nhặt (phải đứng gần bao nhiêu)
    AutoStore     = true,   -- Tự lưu Fruit vật phẩm đang giữ
    StoreCooldown = 3,      -- Khoảng nghỉ giữa các lần thử lưu (giây)
    AutoRandomFruit = true, -- Random Fruit từ NPC Cousin khi đủ điều kiện
    RandomFruitInterval = 0.5, -- Chu kỳ gốc của Banana Cat Hub

    -- Combat: chỉ dùng Fighting Style, không fallback vũ khí khác
    AutoEquipMelee = true,
    AntiAFK        = true,
    Debug          = false,
}

-- ─────────────────────────────────────────────
-- GLOBAL SWITCH
-- ─────────────────────────────────────────────
local globalEnv = getgenv()
if type(globalEnv.AutoFactoryMoveCleanup) == "function" then
    pcall(globalEnv.AutoFactoryMoveCleanup)
    globalEnv.AutoFactoryMoveCleanup = nil
end
if type(globalEnv.AutoFactoryConnections) == "table" then
    for _, connection in ipairs(globalEnv.AutoFactoryConnections) do
        pcall(function() connection:Disconnect() end)
    end
end

local connections = {}
local function TrackConnection(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local runToken = {}
globalEnv.AutoFactoryConnections = connections
globalEnv.AutoFactoryRunToken = runToken -- chạy lại script sẽ dừng loop cũ
globalEnv.AutoFactory = true

-- ─────────────────────────────────────────────
-- UTILS
-- ─────────────────────────────────────────────
local function Log(msg)
    if CFG.Debug then print("[AutoFactory] " .. tostring(msg)) end
end

-- Roblox phát Idled trước khi kick vì không hoạt động. Kết nối này được đưa vào
-- AutoFactoryConnections nên chạy lại script không tạo nhiều anti-AFK song song.
local function SendAntiAFKInput()
    local camera = workspace.CurrentCamera
    local cameraCFrame = camera and camera.CFrame or CFrame.new()

    local downOk = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button2Down(Vector2.new(0, 0), cameraCFrame)
    end)
    task.wait(0.1)
    local upOk = pcall(function()
        VirtualUser:Button2Up(Vector2.new(0, 0), cameraCFrame)
    end)

    if downOk and upOk then return true end

    -- Một số executor không hỗ trợ đầy đủ VirtualUser; dùng phím làm fallback.
    local fallbackOk = pcall(function()
        VIM:SendKeyEvent(true, "LeftControl", false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, "LeftControl", false, game)
    end)
    return fallbackOk
end

if CFG.AntiAFK then
    TrackConnection(lp.Idled, function()
        if not globalEnv.AutoFactory or globalEnv.AutoFactoryRunToken ~= runToken then
            return
        end
        task.spawn(function()
            Log(SendAntiAFKInput() and "Anti-AFK input sent" or "Anti-AFK input failed")
        end)
    end)
end

local function GetChar()  return lp.Character end
local function GetHRP()
    local c = GetChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function GetHumanoid()
    local c = GetChar()
    return c and c:FindFirstChild("Humanoid")
end

local function IsMeleeTool(item)
    if not item or not item:IsA("Tool") then return false end
    local toolTip = string.lower(tostring(item.ToolTip or ""))
    return toolTip == "melee" or toolTip == "fighting style"
end

local function IsFruitTool(item)
    if not item or not item:IsA("Tool") then return false end
    local itemName = string.lower(item.Name)
    -- Không dùng ToolTip "Blox Fruit": đó có thể là Fruit power đã ăn,
    -- không phải vật phẩm Fruit có thể cất vào Storage.
    return string.find(itemName, "fruit", 1, true) ~= nil
end

local function FindMeleeIn(container)
    if not container then return nil end
    for _, item in ipairs(container:GetChildren()) do
        if IsMeleeTool(item) then
            return item
        end
    end
    return nil
end

-- Chỉ trả về Fighting Style đã equip. Không có fallback Sword/Gun/Fruit.
local function EquipMelee()
    local char = GetChar()
    local humanoid = GetHumanoid()
    local backpack = lp:FindFirstChild("Backpack")
    if not char or not humanoid or humanoid.Health <= 0 then
        return nil, "Character chưa sẵn sàng"
    end

    local equippedMelee = FindMeleeIn(char)
    if equippedMelee then return equippedMelee end

    local backpackMelee = FindMeleeIn(backpack)
    if not backpackMelee then
        return nil, "Không có Fighting Style (Melee)"
    end
    if not CFG.AutoEquipMelee then
        return nil, "Melee chưa được equip"
    end
    if humanoid.Sit then
        humanoid.Sit = false
        task.wait()
        if humanoid.Sit then
            return nil, "Không thể equip Melee khi đang ngồi"
        end
    end

    local ok, err = pcall(function()
        humanoid:EquipTool(backpackMelee)
    end)
    if not ok then
        Log("Equip Melee error: " .. tostring(err))
        return nil, "Equip Melee thất bại"
    end
    if backpackMelee.Parent ~= char then
        return nil, "Đang equip Melee..."
    end

    Log("Equipped Melee: " .. backpackMelee.Name)
    return backpackMelee
end

-- Khôi phục từ AttackFunction gốc (deobfuscated.lua 33587-33604, 33957-33978):
-- RE/RegisterAttack:FireServer(0), sau đó RegisterHit:FireServer(hitPart, hits).
local registerAttackRemote = nil
local registerHitRemote = nil
local lastCombatResolve = 0
local lastRemoteAttack = 0

local function ResolveCombatRemotes()
    if registerAttackRemote and registerHitRemote then
        return registerAttackRemote, registerHitRemote
    end
    if (tick() - lastCombatResolve) < 2 then return nil, nil end
    lastCombatResolve = tick()

    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local netModule = modules and modules:FindFirstChild("Net")
    if not netModule then return nil, nil end

    local attackRemote = netModule:FindFirstChild("RE/RegisterAttack")
    if not attackRemote then return nil, nil end

    local ok, netApi = pcall(require, netModule)
    if not ok or type(netApi) ~= "table" or type(netApi.RemoteEvent) ~= "function" then
        return nil, nil
    end

    local hitOk, hitRemote = pcall(function()
        return netApi:RemoteEvent("RegisterHit", true)
    end)
    if not hitOk or not hitRemote then return nil, nil end

    registerAttackRemote = attackRemote
    registerHitRemote = hitRemote
    return registerAttackRemote, registerHitRemote
end

local function TrySourceMeleeAttack(core)
    if not CFG.UseCombatRemotes then return false, "Combat remotes đã tắt" end

    local now = tick()
    if (now - lastRemoteAttack) < CFG.RemoteAttackDelay then
        return true, "Remote"
    end

    local attackRemote, hitRemote = ResolveCombatRemotes()
    if not attackRemote or not hitRemote then
        return false, "Không tìm thấy combat remotes"
    end

    local hitPart = core and core:FindFirstChild("HumanoidRootPart")
    if not hitPart then return false, "Core thiếu hit part" end

    local ok, err = pcall(function()
        attackRemote:FireServer(0)
        hitRemote:FireServer(hitPart, {})
    end)
    if not ok then
        registerAttackRemote = nil
        registerHitRemote = nil
        Log("Source melee remote error: " .. tostring(err))
        return false, tostring(err)
    end

    lastRemoteAttack = now
    return true, "Remote"
end

-- Kiểm tra mob còn sống (từ IsMobAlive gốc dòng 34760-34774)
local function IsMobAlive(mob)
    if not mob then return false end
    if not mob.Parent then return false end
    local root = mob:FindFirstChild("HumanoidRootPart")
    local humanoid = mob:FindFirstChild("Humanoid")
    return root ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function StopRootVelocity(hrp)
    if not hrp then return end
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- Cơ chế di chuyển thay thế lấy từ teleport_islands.lua: tiến từng Heartbeat,
-- khóa velocity và noclip trong suốt hành trình để tránh bị kéo lùi.
local moveState = {
    active = false,
    target = nil,
    purpose = nil,
    snapDistance = 0,
    speed = 0,
    collisionState = {},
    floatForce = nil,
}

local function MarkTeleporting()
    pcall(function()
        if not CollectionService:HasTag(lp, "Teleporting") then
            CollectionService:AddTag(lp, "Teleporting")
        end
    end)
    task.delay(1.5, function()
        pcall(function()
            CollectionService:RemoveTag(lp, "Teleporting")
        end)
    end)
end

local function EnsureMoveFloat(hrp)
    if not hrp then return end
    if moveState.floatForce and moveState.floatForce.Parent == hrp then return end
    if moveState.floatForce then
        pcall(function() moveState.floatForce:Destroy() end)
        moveState.floatForce = nil
    end

    -- Dọn lực mồ côi nếu phiên trước bị executor dừng đột ngột.
    local staleForce = hrp:FindFirstChild("AutoFactoryFloatForce")
    if staleForce then pcall(function() staleForce:Destroy() end) end

    local force = Instance.new("BodyVelocity")
    force.Name = "AutoFactoryFloatForce"
    force.Velocity = Vector3.zero
    force.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    force.P = 1e4
    force.Parent = hrp
    moveState.floatForce = force
end

local function RestoreMoveCharacter()
    globalEnv.noclip = false

    local force = moveState.floatForce
    moveState.floatForce = nil
    if force then pcall(function() force:Destroy() end) end

    local hrp = GetHRP()
    local humanoid = GetHumanoid()
    if hrp then
        StopRootVelocity(hrp)
    end
    if humanoid then humanoid.PlatformStand = false end

    for part, oldCanCollide in pairs(moveState.collisionState) do
        if part and part.Parent then
            pcall(function() part.CanCollide = oldCanCollide end)
        end
    end
    table.clear(moveState.collisionState)
end

local function CancelMove(restoreCharacter)
    moveState.active = false
    moveState.target = nil
    moveState.purpose = nil
    moveState.snapDistance = 0
    moveState.speed = 0
    if restoreCharacter then RestoreMoveCharacter() end
end

local function LeaveSeat(hrp, humanoid)
    CancelMove(true)
    pcall(function()
        VIM:SendKeyEvent(true, "Space", false, game)
        task.wait()
        VIM:SendKeyEvent(false, "Space", false, game)
    end)
    humanoid.Sit = false
    humanoid.Jump = true
    task.wait(0.1)
    if hrp.Parent then hrp.CFrame = hrp.CFrame * CFrame.new(0, 10, 0) end
end

local function ToTarget(cf, shortSnap, purpose)
    if typeof(cf) ~= "CFrame" then
        return false, "ToTarget cần CFrame"
    end

    local char = GetChar()
    local humanoid = GetHumanoid()
    local hrp = GetHRP()
    if not char or not humanoid or humanoid.Health <= 0 or not hrp then
        return false, "Character chưa sẵn sàng"
    end

    if humanoid.Sit then
        LeaveSeat(hrp, humanoid)
        return false, "Đang thoát trạng thái ngồi"
    end

    local distanceOk, distanceOrError = pcall(function()
        return (hrp.Position - cf.Position).Magnitude
    end)
    if not distanceOk then
        return false, "Đọc khoảng cách lỗi: " .. tostring(distanceOrError)
    end
    local distance = distanceOrError
    local snapDistance = shortSnap and CFG.FruitSnapDistance or CFG.CoreSnapDistance

    if distance <= snapDistance then
        CancelMove(false)
        local ok, err = pcall(function()
            MarkTeleporting()
            StopRootVelocity(hrp)
            hrp.CFrame = cf
            StopRootVelocity(hrp)
        end)
        if not ok then
            RestoreMoveCharacter()
            return false, "Snap CFrame lỗi: " .. tostring(err)
        end
        RestoreMoveCharacter()
        return true, "Snap"
    end

    local configuredSpeed = purpose == "Fruit" and CFG.FruitMoveSpeed or CFG.MoveSpeed
    local moveSpeed = math.max(tonumber(configuredSpeed) or CFG.MoveSpeed, 1)

    -- Core có thể đổi vị trí liên tục. Cập nhật đích của hành trình hiện tại thay
    -- vì khởi động lại chuyển động ở mỗi vòng lặp.
    if moveState.active and moveState.purpose == purpose then
        moveState.target = cf
        moveState.snapDistance = snapDistance
        moveState.speed = moveSpeed
        return true, "Move"
    end

    CancelMove(false)
    globalEnv.noclip = true
    EnsureMoveFloat(hrp)
    humanoid.PlatformStand = true
    MarkTeleporting()
    StopRootVelocity(hrp)
    moveState.active = true
    moveState.target = cf
    moveState.purpose = purpose
    moveState.snapDistance = snapDistance
    moveState.speed = moveSpeed
    return true, "Move"
end

TrackConnection(RunService.Heartbeat, function(dt)
    if not moveState.active then return end
    if not globalEnv.AutoFactory or globalEnv.AutoFactoryRunToken ~= runToken then
        CancelMove(true)
        return
    end

    local hrp = GetHRP()
    local humanoid = GetHumanoid()
    local targetCF = moveState.target
    if not hrp or not humanoid or humanoid.Health <= 0 or not targetCF then
        CancelMove(true)
        return
    end

    local currentPos = hrp.Position
    local targetPos = targetCF.Position
    local offset = targetPos - currentPos
    local remaining = offset.Magnitude

    if remaining <= moveState.snapDistance then
        hrp.CFrame = targetCF
        StopRootVelocity(hrp)
        CancelMove(true)
        return
    end

    -- Heartbeat truyền dt trực tiếp; giới hạn dt để một frame lag không tạo bước nhảy quá lớn.
    local frameTime = math.min(math.max(tonumber(dt) or (1 / 60), 0), 0.1)
    local step = math.min(moveState.speed * frameTime, remaining)
    local newPos = currentPos + offset.Unit * step
    local targetRotation = targetCF - targetPos

    globalEnv.noclip = true
    humanoid.PlatformStand = true
    EnsureMoveFloat(hrp)
    hrp.CFrame = CFrame.new(newPos) * targetRotation
    StopRootVelocity(hrp)
end)

TrackConnection(RunService.Stepped, function()
    if not moveState.active then return end
    local char = GetChar()
    if not char then return end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if moveState.collisionState[part] == nil then
                moveState.collisionState[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end)

TrackConnection(lp.CharacterAdded, function()
    CancelMove(true)
end)

local moveCleanup = function()
    CancelMove(true)
end
globalEnv.AutoFactoryMoveCleanup = moveCleanup

-- Tắt collision mob để xuyên qua (từ sizepart gốc dòng 34511-34551)
local function SizePart(mob)
    if not mob then return end
    if not mob.Parent then return end
    local hrp = GetHRP()
    if not hrp then return end
    local mobRoot = mob:FindFirstChild("HumanoidRootPart")
    if not mobRoot then return end
    if (hrp.Position - mobRoot.Position).Magnitude > 50 then return end
    for _, p in ipairs(mob:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            pcall(function() p.CanCollide = false end)
        end
    end
end

-- Khoảng cách từ nhân vật đến 1 vị trí
local function DistTo(pos)
    local hrp = GetHRP()
    if not hrp then return math.huge end
    return (hrp.Position - pos).Magnitude
end

-- ─────────────────────────────────────────────
-- TÌM BOSS CORE
-- Từ CheckNameBoss gốc dòng 34617-34682
-- ─────────────────────────────────────────────
local function FindCore()
    -- Ưu tiên workspace.Enemies (vị trí chuẩn của mob BLF)
    local enemies = workspace:FindFirstChild("Enemies")
    if enemies then
        for _, m in ipairs(enemies:GetChildren()) do
            local ok, alive = pcall(IsMobAlive, m)
            if m:IsA("Model") and m.Name == "Core" and ok and alive then
                return m
            end
        end
    end
    -- Fallback toàn workspace
    for _, obj in ipairs(workspace:GetChildren()) do
        local ok, alive = pcall(IsMobAlive, obj)
        if obj:IsA("Model") and obj.Name == "Core" and ok and alive then
            return obj
        end
    end
    return nil
end

-- ─────────────────────────────────────────────
-- ATTACK CORE
-- Chỉ equip và M1 bằng Fighting Style (ToolTip = "Melee")
-- ─────────────────────────────────────────────
local function AttackCore(core)
    if not IsMobAlive(core) then return nil, "Core không còn sống" end
    local char = GetChar()
    if not char then return nil, "Character chưa sẵn sàng" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, "Thiếu HumanoidRootPart" end
    local coreRoot = core:FindFirstChild("HumanoidRootPart")
    if not coreRoot then return nil, "Core thiếu HumanoidRootPart" end

    -- Kiểm tra tầm
    if DistTo(coreRoot.Position) > CFG.AttackRange then
        return nil, "Core ngoài tầm M1"
    end

    local melee, equipError = EquipMelee()
    if not melee then
        Log(equipError)
        return nil, equipError
    end

    -- AttackFunction gốc không đánh khi Character.Stun.Value ~= 0.
    local stun = char:FindFirstChild("Stun")
    if stun and stun:IsA("ValueBase") and stun.Value ~= 0 then
        return nil, "Đang bị Stun"
    end

    local remoteOk, attackMode = TrySourceMeleeAttack(core)
    if remoteOk then
        Log("Melee M1 via source combat remotes: " .. melee.Name)
        return melee.Name, nil, attackMode
    end

    -- Fallback khi game cập nhật/đổi module Net hoặc executor không require được module.
    local attackOk, attackErr = pcall(function()
        VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(CFG.M1HoldTime)
        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
    if not attackOk then
        -- Tránh kẹt trạng thái giữ chuột nếu executor lỗi giữa hai event.
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
        Log("Melee M1 error: " .. tostring(attackErr))
        return nil, "Gửi Melee M1 thất bại"
    end

    Log("Melee M1 via input fallback: " .. melee.Name .. " | " .. tostring(attackMode))
    return melee.Name, nil, "Input"
end

-- ─────────────────────────────────────────────
-- TÌM FRUIT TRONG MAP
-- Từ GetPathFruit gốc dòng 4020-4052
-- + tìm theo cả Handle (fruit chưa nhặt trong workspace)
-- ─────────────────────────────────────────────
local function FindFruitInWorld()
    local hrp = GetHRP()
    if not hrp then return nil end

    local configuredRange = tonumber(CFG.FruitRange) or 0
    local bestFruit = nil
    local bestDist = configuredRange > 0 and configuredRange or math.huge

    local function considerFruit(obj)
        if not obj or obj.Parent ~= workspace then return end

        local isFruit = IsFruitTool(obj)
            or (obj:IsA("Model")
                and string.find(string.lower(obj.Name), "fruit", 1, true) ~= nil)
        if not isFruit then return end

        local handle = obj:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then return end

        local dist = (hrp.Position - handle.Position).Magnitude
        if dist <= bestDist then
            bestDist = dist
            bestFruit = obj
        end
    end

    -- GetPathFruit gốc chỉ duyệt các child trực tiếp của Workspace.
    for _, obj in ipairs(workspace:GetChildren()) do
        local ok, err = pcall(considerFruit, obj)
        if not ok then Log("Scan Fruit error: " .. tostring(err)) end
    end

    return bestFruit, bestDist
end

-- ─────────────────────────────────────────────
-- NHẶT FRUIT
-- Từ gốc dòng 5565-5588:
--   - Nếu đã gần fruit (<=5 studs) → nhảy Space (trigger touch pickup)
--   - Nếu còn xa → tele đến Handle.CFrame bằng cơ chế Heartbeat
-- ─────────────────────────────────────────────
local function PickupFruit(fruit)
    if not fruit then return false, "Fruit không tồn tại" end
    local handle = fruit:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return false, "Fruit thiếu Handle" end
    if not handle.Parent then return false, "Fruit đã biến mất" end

    local hrp = GetHRP()
    if not hrp then return false, "Character chưa sẵn sàng" end

    local dist = (hrp.Position - handle.Position).Magnitude

    if dist <= CFG.PickupDist then
        -- Đủ gần → nhảy để trigger pickup (theo gốc dùng VirtualInputManager Space)
        local inputOk, inputError = pcall(function()
            VIM:SendKeyEvent(true, "Space", false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, "Space", false, game)
        end)
        if not inputOk then
            pcall(function() VIM:SendKeyEvent(false, "Space", false, game) end)
            return false, "Input nhặt Fruit lỗi: " .. tostring(inputError)
        end
        task.wait(0.3)

        local char = GetChar()
        local backpack = lp:FindFirstChild("Backpack")
        local picked = not fruit.Parent
            or (char and fruit:IsDescendantOf(char))
            or (backpack and fruit:IsDescendantOf(backpack))
        Log(picked and "Pickup fruit thành công" or "Đã bấm Space nhưng chưa nhặt được fruit")
        return picked, picked and "Picked" or "Chưa nhặt được"
    else
        -- Source gốc gọi toTarget(fruit.Handle.CFrame, true).
        local moved, moveStatus = ToTarget(handle.CFrame, true, "Fruit")
        if not moved then
            Log("Move to Fruit failed: " .. tostring(moveStatus))
            return false, moveStatus
        end
        Log(string.format("Moving to fruit: %s (%.0f studs)", fruit.Name, dist))
        return false, moveStatus -- chưa nhặt, cần loop lại
    end
end

-- ─────────────────────────────────────────────
-- ĐẾM FRUIT VẬT PHẨM ĐANG GIỮ
-- Đếm số fruit đang trong Backpack + Character
-- ─────────────────────────────────────────────
local ignoredStoreItems = setmetatable({}, { __mode = "k" })
local fullFruitStorage = {}

local function IsStoreIgnored(item)
    return ignoredStoreItems[item] == true
        or (item and item:FindFirstChild("Ignored") ~= nil)
end

local function CountFruitInBackpack()
    local count, ignored = 0, 0
    local char  = GetChar()
    local bp    = lp:FindFirstChild("Backpack")

    local function checkContainer(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            local ok, isFruit = pcall(IsFruitTool, item)
            if ok and isFruit then
                if IsStoreIgnored(item) then
                    ignored = ignored + 1
                else
                    count = count + 1
                end
            end
        end
    end

    checkContainer(bp)
    if char then checkContainer(char) end
    return count, ignored
end

-- ─────────────────────────────────────────────
-- LƯU FRUIT VÀO STORAGE
-- Source gốc dùng: CommF_:InvokeServer("StoreFruit", originalName, tool)
-- ─────────────────────────────────────────────
local lastStoreTime = 0

local function IsInPlayerInventory(item)
    if not item or not item.Parent then return false end
    local char = GetChar()
    local backpack = lp:FindFirstChild("Backpack")
    return (char and item:IsDescendantOf(char))
        or (backpack and item:IsDescendantOf(backpack))
end

local function GetFruitStorageName(item)
    local originalName = item:GetAttribute("OriginalName")
    if type(originalName) == "string" and originalName ~= "" then
        return originalName
    end

    local baseName = string.gsub(item.Name, " Fruit", "")
    return baseName .. "-" .. baseName
end

local function MarkFruitStoreIgnored(item, storageName)
    ignoredStoreItems[item] = true
    fullFruitStorage[storageName] = true

    -- Source gốc cũng gắn "Ignored" sau khi đã thử lưu để Tool đó
    -- không bị gửi StoreFruit lặp lại ở các vòng sau.
    if item and item.Parent and not item:FindFirstChild("Ignored") then
        pcall(function()
            local ignored = Instance.new("IntValue")
            ignored.Name = "Ignored"
            ignored.Parent = item
        end)
    end
end

local function StoreFruitInBackpack()
    -- Cooldown để không spam
    if (tick() - lastStoreTime) < CFG.StoreCooldown then
        return 0, 0, 0, "cooldown"
    end

    local char = GetChar()
    local bp   = lp:FindFirstChild("Backpack")

    local commF = ReplicatedStorage:FindFirstChild("Remotes")
    if commF then commF = commF:FindFirstChild("CommF_") end
    if not commF then
        Log("StoreFruit: CommF_ not found!")
        return 0, 0, 0, "Không tìm thấy CommF_"
    end

    local stored = 0
    local attempted = 0
    local skipped = 0
    lastStoreTime = tick()

    local function storeFrom(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            local checkOk, isFruit = pcall(IsFruitTool, item)
            if checkOk and isFruit then
                local metadataOk, itemName, storageName = pcall(function()
                    return item.Name, GetFruitStorageName(item)
                end)
                if not metadataOk then
                    Log("Đọc metadata Fruit lỗi: " .. tostring(itemName))
                    continue
                end

                -- Khi server đã từ chối một loại Fruit vì kho loại đó đầy,
                -- bỏ qua toàn bộ Tool cùng loại cho tới khi chạy lại script.
                if fullFruitStorage[storageName] or IsStoreIgnored(item) then
                    MarkFruitStoreIgnored(item, storageName)
                    skipped = skipped + 1
                    Log("Skip StoreFruit (storage full): " .. itemName)
                    continue
                end

                attempted = attempted + 1
                local ok, result = pcall(function()
                    return commF:InvokeServer("StoreFruit", storageName, item)
                end)

                -- Cho game một khoảng ngắn để chuyển Tool ra khỏi Backpack.
                for _ = 1, 5 do
                    if not IsInPlayerInventory(item) then break end
                    task.wait(0.1)
                end

                if ok and not IsInPlayerInventory(item) then
                    stored = stored + 1
                    Log("Stored: " .. itemName)
                elseif ok then
                    -- InvokeServer chạy thành công nhưng Tool vẫn còn: server đã
                    -- từ chối lưu (trường hợp thường gặp là đủ số lượng loại Fruit).
                    MarkFruitStoreIgnored(item, storageName)
                    skipped = skipped + 1
                    Log("Storage full/rejected, skip from now: "
                        .. itemName .. " | " .. tostring(result))
                else
                    -- Lỗi gọi Remote có thể chỉ là tạm thời nên chưa đánh dấu full.
                    Log("StoreFruit failed: " .. itemName .. " | " .. tostring(result))
                end
            end
        end
    end

    storeFrom(bp)
    if char then storeFrom(char) end

    Log(string.format("Stored %d/%d fruit(s), skipped %d", stored, attempted, skipped))
    return stored, attempted, skipped
end

-- ─────────────────────────────────────────────
-- RANDOM DEVIL FRUIT (Cousin)
-- Từ source gốc dòng 12294-12368 và vòng gọi dòng 40796-40833:
--   BannerClient -> BoxName -> Cousin/Check -> CheckTime -> Cousin/Buy
-- ─────────────────────────────────────────────
local bannerClient = nil
local spinnerController = nil

local function GetCommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_") or nil
end

local function LoadBannerClient()
    if bannerClient then return bannerClient end
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local module = controllers and controllers:FindFirstChild("BannerClient")
    if not module then return nil, "Không tìm thấy BannerClient" end

    local ok, result = pcall(require, module)
    if not ok or type(result) ~= "table" then
        return nil, "Load BannerClient lỗi: " .. tostring(result)
    end
    bannerClient = result
    return bannerClient
end

local function GetRandomFruitBoxName()
    local controller, loadError = LoadBannerClient()
    if not controller then return nil, loadError end
    if type(controller.TryGetBannerItemIfActiveAsync) ~= "function" then
        return nil, "BannerClient thiếu TryGetBannerItemIfActiveAsync"
    end

    local ok, item = pcall(function()
        -- Source gốc gọi bằng dấu chấm, không truyền self.
        return controller.TryGetBannerItemIfActiveAsync()
    end)
    if not ok then return nil, "Đọc banner lỗi: " .. tostring(item) end

    -- Source gốc dùng DLCBoxData khi banner hiện tại không có BoxName.
    if item and type(item.BoxName) == "string" and item.BoxName ~= "" then
        return item.BoxName, item
    end
    return "DLCBoxData", item
end

local function LoadSpinnerController()
    if spinnerController then return spinnerController end
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local ui = controllers and controllers:FindFirstChild("UI")
    local module = ui and ui:FindFirstChild("Spinner")
    if not module then return nil, "Không tìm thấy Spinner controller" end

    local ok, result = pcall(require, module)
    if not ok or type(result) ~= "table" then
        return nil, "Load Spinner lỗi: " .. tostring(result)
    end
    spinnerController = result
    return spinnerController
end

local function CloseRandomFruitSpinner(spinnerWindow)
    if not spinnerWindow or not spinnerWindow.Enabled then return true end

    local closeButton = spinnerWindow:FindFirstChild("CloseButton", true)
    if closeButton and closeButton:IsA("GuiObject") and not closeButton.Visible then
        return false, "Spinner đang quay"
    end

    local controller, loadError = LoadSpinnerController()
    if not controller then return false, loadError end
    if type(controller.Close) ~= "function" then
        return false, "Spinner controller thiếu Close"
    end

    local ok, closeError = pcall(function() controller:Close() end)
    if not ok then return false, "Đóng Spinner lỗi: " .. tostring(closeError) end
    return true
end

local function RandomFruit()
    local playerGui = lp:FindFirstChild("PlayerGui")
    local spinnerWindow = playerGui and playerGui:FindFirstChild("SpinnerWindow")

    -- Source gốc đợi SpinnerWindow tồn tại; khi vòng quay mở thì đóng nó trước.
    if not spinnerWindow then return false, "SpinnerNotReady" end
    if spinnerWindow.Enabled then
        local closed, closeStatus = CloseRandomFruitSpinner(spinnerWindow)
        return false, closed and "SpinnerClosed" or closeStatus
    end

    local commF = GetCommF()
    if not commF then return false, "Không tìm thấy CommF_" end

    local boxName, boxError = GetRandomFruitBoxName()
    if not boxName then return false, boxError end

    local checkOk, money, level, price = pcall(function()
        return commF:InvokeServer("Cousin", "Check", boxName)
    end)
    if not checkOk then return false, "Cousin Check lỗi: " .. tostring(money) end

    level = tonumber(level) or 0
    if level < 50 then return false, "Level" end

    money = tonumber(money) or 0
    price = tonumber(price) or math.huge
    if money < price then return false, "Money", price - money end

    local timeOk, canBuy = pcall(function()
        return commF:InvokeServer("Cousin", "CheckTime", boxName)
    end)
    if not timeOk then return false, "Cousin CheckTime lỗi: " .. tostring(canBuy) end
    if canBuy ~= true then return false, "Cooldown" end

    local buyOk, resultCode, reward = pcall(function()
        return commF:InvokeServer("Cousin", boxName)
    end)
    if not buyOk then return false, "Cousin Buy lỗi: " .. tostring(resultCode) end
    if resultCode ~= 1 then return false, "BuyRejected", resultCode end

    Log("Random Fruit thành công: " .. tostring(reward or boxName))
    return true, "Bought", reward or boxName
end

-- ─────────────────────────────────────────────
-- GUI
-- ─────────────────────────────────────────────
-- Xóa GUI cũ
local playerGui = lp:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("AutoFactoryGUI")
if oldGui then pcall(function() oldGui:Destroy() end) end

local sg = Instance.new("ScreenGui")
sg.Name            = "AutoFactoryGUI"
sg.ResetOnSpawn    = false
sg.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
sg.Parent          = playerGui

-- Frame chính
local frame = Instance.new("Frame")
frame.Name              = "Main"
frame.Size              = UDim2.new(0, 310, 0, 165)
frame.Position          = UDim2.new(0.5, -155, 0, 8)
frame.BackgroundColor3  = Color3.fromRGB(10, 10, 18)
frame.BorderSizePixel   = 0
frame.Parent            = sg
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

-- Border glow
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Color = Color3.fromRGB(255, 175, 0)
stroke.Transparency = 0.25
stroke.Parent = frame

-- Header bar
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 36)
header.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
header.BorderSizePixel  = 0
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
-- Ghim góc dưới header
local headerFix = Instance.new("Frame")
headerFix.Size            = UDim2.new(1, 0, 0, 12)
headerFix.Position        = UDim2.new(0, 0, 1, -12)
headerFix.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
headerFix.BorderSizePixel  = 0
headerFix.Parent           = header

-- Tiêu đề
local title = Instance.new("TextLabel")
title.Size               = UDim2.new(1, -80, 1, 0)
title.Position           = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text               = "🏭  Auto Factory + Fruit  |  Sea 2"
title.TextColor3         = Color3.fromRGB(255, 200, 50)
title.Font               = Enum.Font.GothamBold
title.TextScaled         = true
title.TextXAlignment     = Enum.TextXAlignment.Left
title.Parent             = header

-- Nút STOP
local stopBtn = Instance.new("TextButton")
stopBtn.Size              = UDim2.new(0, 60, 0, 24)
stopBtn.Position          = UDim2.new(1, -68, 0.5, -12)
stopBtn.BackgroundColor3  = Color3.fromRGB(190, 40, 40)
stopBtn.Text              = "⏹ STOP"
stopBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
stopBtn.Font              = Enum.Font.GothamBold
stopBtn.TextScaled        = true
stopBtn.BorderSizePixel   = 0
stopBtn.Parent            = header
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)

TrackConnection(stopBtn.MouseEnter, function()
    stopBtn.BackgroundColor3 = Color3.fromRGB(220,55,55)
end)
TrackConnection(stopBtn.MouseLeave, function()
    stopBtn.BackgroundColor3 = Color3.fromRGB(190,40,40)
end)
TrackConnection(stopBtn.MouseButton1Click, function()
    globalEnv.AutoFactory = false
end)

-- Labels trạng thái (5 dòng)
local function MakeLabel(yOffset, color)
    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(1, -20, 0, 22)
    lbl.Position           = UDim2.new(0, 10, 0, yOffset)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3         = color or Color3.fromRGB(200, 200, 200)
    lbl.Font               = Enum.Font.Gotham
    lbl.TextScaled         = true
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Parent             = frame
    return lbl
end

local lblMode   = MakeLabel(42,  Color3.fromRGB(100, 220, 255))
local lblBoss   = MakeLabel(65,  Color3.fromRGB(255, 130, 130))
local lblFruit  = MakeLabel(88,  Color3.fromRGB(130, 255, 150))
local lblStore  = MakeLabel(111, Color3.fromRGB(200, 200, 100))
local lblRandom = MakeLabel(134, Color3.fromRGB(220, 150, 255))

lblMode.Text  = "⚙️ Khởi động..."
lblBoss.Text  = "🔍 Boss: Chờ..."
lblFruit.Text = "🍎 Fruit: Chờ..."
lblStore.Text = "📦 Storage: Sẵn sàng"
lblRandom.Text = CFG.AutoRandomFruit and "🎲 Random Fruit: Khởi động..."
    or "🎲 Random Fruit: Đã tắt"

-- Drag GUI
local dragging, dragStart, startPos = false, nil, nil
TrackConnection(header.InputBegan, function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = inp.Position
        startPos  = frame.Position
    end
end)
TrackConnection(UserInputService.InputChanged, function(inp)
    if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
        local d = inp.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)
TrackConnection(UserInputService.InputEnded, function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- Random Fruit chạy riêng để InvokeServer/Spinner không làm chậm vòng ưu tiên Core.
task.spawn(function()
    while globalEnv.AutoFactory
        and globalEnv.AutoFactoryRunToken == runToken
        and sg.Parent do
        task.wait(math.max(tonumber(CFG.RandomFruitInterval) or 0.5, 0.2))

        if CFG.AutoRandomFruit then
            local callOk, bought, status, detail = pcall(RandomFruit)
            if not callOk then
                lblRandom.Text = "⚠️ Random lỗi: " .. tostring(bought)
            elseif bought then
                lblRandom.Text = "✅ Random: " .. tostring(detail or "Đã mua Fruit")
            elseif status == "Level" then
                lblRandom.Text = "🎲 Random: Cần cấp 50"
            elseif status == "Money" then
                lblRandom.Text = string.format("🎲 Random: Thiếu %.0f Beli", tonumber(detail) or 0)
            elseif status == "Cooldown" then
                lblRandom.Text = "🎲 Random: Đang chờ cooldown"
            elseif status == "SpinnerClosed" then
                lblRandom.Text = "🎲 Random: Đã đóng vòng quay"
            elseif status == "SpinnerNotReady" then
                lblRandom.Text = "🎲 Random: Chờ SpinnerWindow"
            elseif status == "BuyRejected" then
                lblRandom.Text = "⚠️ Random bị từ chối: " .. tostring(detail)
            else
                lblRandom.Text = "⚠️ Random: " .. tostring(status or "Không thực hiện được")
            end
        else
            lblRandom.Text = "🎲 Random Fruit: Đã tắt"
        end
    end
end)

-- ─────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────
print("[AutoFactory] Đã bắt đầu! Core Melee-only; Fruit tele 150; Auto Random Fruit.")

task.spawn(function()
    local ok, runError = xpcall(function()
        local waitTick  = 0
        local fruitMode = false

        while globalEnv.AutoFactory
            and globalEnv.AutoFactoryRunToken == runToken
            and sg.Parent do
            task.wait(CFG.LoopDelay)

        local char = GetChar()
        local humanoid = GetHumanoid()
        if not char or not humanoid or humanoid.Health <= 0 then
            lblMode.Text = "⚠️ Chờ character..."
            task.wait(1)
            continue
        end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            lblMode.Text = "⚠️ Chờ HumanoidRootPart..."
            task.wait(0.5)
            continue
        end

        -- ══════════════════════════════════════
        -- PHẦN 1: ATTACK CORE (ưu tiên tuyệt đối)
        -- ══════════════════════════════════════
        local core = FindCore()
        if core and IsMobAlive(core) then
            waitTick = 0
            fruitMode = false

            local bossHRP = core:FindFirstChild("HumanoidRootPart")
            local bossHumanoid = core:FindFirstChild("Humanoid")
            if not bossHRP or not bossHumanoid or bossHumanoid.Health <= 0 then
                continue
            end

            local moved, moveStatus = ToTarget(
                bossHRP.CFrame * CFrame.new(0, CFG.CoreOffsetY, 0),
                false,
                "Core"
            )
            if not moved then
                lblMode.Text = "⚠️ " .. tostring(moveStatus or "Không thể tới Core")
                continue
            end
            SizePart(core)

            local hp    = math.floor(bossHumanoid.Health)
            local maxHp = math.floor(bossHumanoid.MaxHealth)
            local pct   = math.floor(hp / math.max(maxHp, 1) * 100)
            local dist  = math.floor(DistTo(bossHRP.Position))

            lblBoss.Text = string.format(
                "💀 Core: %d/%d HP (%d%%) | %dm",
                hp, maxHp, pct, dist
            )

            if dist > CFG.AttackRange then
                lblMode.Text = string.format("✈️ Đang tới Core | %dm", dist)
                continue
            end

            -- Không có fallback: thiếu Melee thì dừng attack và báo đúng lý do.
            local meleeName, attackError, attackMode = AttackCore(core)
            if meleeName then
                lblMode.Text = string.format("⚔️ Melee/%s | %s", attackMode, meleeName)
            else
                lblMode.Text = "⚠️ " .. tostring(attackError or "Không thể đánh bằng Melee")
            end

            -- Không nhặt/lưu Fruit trong lúc Core còn sống.
            continue
        end

        -- ══════════════════════════════════════
        -- PHẦN 2: LƯU + TÌM FRUIT (chỉ khi không có Core)
        -- ══════════════════════════════════════
        if moveState.purpose == "Core" then CancelMove(true) end
        waitTick = waitTick + 1
        local dots = string.rep(".", (waitTick % 3) + 1)
        lblMode.Text = "🔍 Tìm Core" .. dots
        lblBoss.Text = "💀 Boss: Chờ spawn..."

        -- Thử lưu cả Fruit còn sót trong Backpack từ lần trước.
        if CFG.AutoStore then
            local count, ignored = CountFruitInBackpack()
            if count > 0 then
                local stored, attempted, skipped, storeError = StoreFruitInBackpack()
                if storeError == "cooldown" then
                    lblStore.Text = string.format("📦 Chờ lưu: %d fruit(s)", count)
                elseif skipped > 0 and stored > 0 then
                    lblStore.Text = string.format("✅ Lưu %d | ⏭️ Bỏ qua %d (đầy)", stored, skipped)
                elseif skipped > 0 then
                    lblStore.Text = string.format("⏭️ Bỏ qua %d Fruit (kho đầy)", skipped)
                elseif attempted > 0 and stored == attempted then
                    lblStore.Text = string.format("✅ Đã lưu %d fruit(s)", stored)
                elseif attempted > 0 then
                    lblStore.Text = string.format("⚠️ Đã lưu %d/%d fruit(s)", stored, attempted)
                else
                    lblStore.Text = "⚠️ " .. tostring(storeError or "Không lưu được Fruit")
                end
            elseif ignored > 0 then
                lblStore.Text = string.format("⏭️ Bỏ qua %d Fruit (kho đầy)", ignored)
            else
                lblStore.Text = "📦 Storage: Sẵn sàng"
            end
        else
            lblStore.Text = "📦 Auto Store: Đã tắt"
        end

        if CFG.FruitEnabled then
            local fruit, fruitDist = FindFruitInWorld()
            if fruit then
                fruitMode = true
                local fruitName = fruit.Name
                lblMode.Text  = "🍎 Đang nhặt Fruit..."
                lblFruit.Text = string.format("🍎 %s (%.0fm)", fruitName, fruitDist)

                local picked, pickupStatus = PickupFruit(fruit)
                if picked then
                    lblFruit.Text = "✅ Đã nhặt: " .. fruitName
                elseif pickupStatus == "Move" or pickupStatus == "Snap"
                    or pickupStatus == "Chưa nhặt được" then
                    lblFruit.Text = "🍎 Đang tiếp cận: " .. fruitName
                else
                    lblFruit.Text = "⚠️ " .. tostring(pickupStatus or "Không nhặt được Fruit")
                end

                -- Lặp ngay để phát hiện Core vừa spawn và chuyển sang combat.
                continue
            end

            if fruitMode then
                fruitMode = false
                lblFruit.Text = "🍎 Fruit: Không thấy"
            else
                lblFruit.Text = "🍎 Fruit: Chờ spawn..."
            end
        else
            fruitMode = false
            lblFruit.Text = "🍎 Auto Fruit: Đã tắt"
        end

            task.wait(0.8)
        end
    end, function(err)
        return tostring(err)
    end)

    CancelMove(true)
    if globalEnv.AutoFactoryMoveCleanup == moveCleanup then
        globalEnv.AutoFactoryMoveCleanup = nil
    end
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    if globalEnv.AutoFactoryConnections == connections then
        globalEnv.AutoFactoryConnections = nil
    end

    -- Loop cũ bị thay thế không được chạm vào GUI của lần chạy mới.
    if globalEnv.AutoFactoryRunToken == runToken and sg.Parent then
        if ok then
            lblMode.Text  = "✅ Đã dừng!"
            lblBoss.Text  = ""
            lblFruit.Text = ""
            lblStore.Text = ""
            lblRandom.Text = ""
            print("[AutoFactory] Đã dừng.")
            task.wait(2.5)
        else
            lblMode.Text  = "❌ Script gặp lỗi"
            lblBoss.Text  = tostring(runError)
            lblFruit.Text = ""
            lblStore.Text = ""
            lblRandom.Text = ""
            warn("[AutoFactory] " .. tostring(runError))
            task.wait(6)
        end
        if sg.Parent then pcall(function() sg:Destroy() end) end
    end
end)
