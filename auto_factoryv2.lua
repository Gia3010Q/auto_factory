--[[
    ╔═════════════════════════════════════════════════════╗
    ║    AUTO FACTORY + AUTO FRUIT - BLOX FRUITS SEA 2    ║
    ║   Viết lại từ Banana Cat Hub (deobfuscated source)  ║
    ║   Boss: Core  │  Sea: Second Sea                    ║
    ╚═════════════════════════════════════════════════════╝

    TÍNH NĂNG:
    ✅ Auto tìm & đánh boss Core (Factory Sea 2)
    ✅ Tự hop sang server ít người ngay khi chạy script
    ✅ Dùng Entrance Mansion khi ở xa để tới Factory nhanh hơn
    ✅ Tự bật Buso Haki khi chạy script và sau khi respawn
    ✅ Auto tìm Fruit rơi trong map
    ✅ Auto tele đến Fruit và nhặt
    ✅ Sau khi nhặt Fruit tự về Café, dùng Entrance Mansion nếu ở xa
    ✅ Auto Random Devil Fruit từ xa qua Cousin remote
    ✅ Tự đóng SpinnerWindow và thông báo nhận Fruit
    ✅ Auto lưu Fruit vừa nhặt vào Storage
    ✅ Discord Webhook thông báo khi nhặt và lưu Fruit
    ✅ Anti-AFK, tránh bị kick khi treo máy
    ✅ GUI đẹp có thể kéo, nút STOP, hiện trạng thái

    CÁCH DÙNG:
    1. Paste vào executor và chạy
    2. Để ít nhất 1 Fighting Style (ToolTip = Melee) trong Backpack
    3. Dán link Webhook vào CFG.WebhookURL hoặc: getgenv().WebhookURL = "..."
    4. Dừng bằng nút STOP hoặc:  getgenv().AutoFactory = false
]]

-- Chọn team trước khi khởi tạo Auto Factory.
repeat task.wait() until game:IsLoaded()

local startupEnv = getgenv()
local startupPlayer = game:GetService("Players").LocalPlayer
local currentTeam = startupPlayer and startupPlayer.Team
local currentTeamName = currentTeam and currentTeam.Name or nil

-- Team hiện tại trong server luôn được ưu tiên. getgenv() tồn tại qua các lần
-- chạy nên MyTeam cũ không được phép kéo người chơi sang team khác khi rerun.
local hasSelectedTeam = currentTeamName == "Pirates" or currentTeamName == "Marines"
if hasSelectedTeam then
    startupEnv.MyTeam = currentTeamName
    print("[AutoFactory] Đã ở đúng team, bỏ qua SetTeam: " .. currentTeamName)
else
    if startupEnv.MyTeam ~= "Pirates" and startupEnv.MyTeam ~= "Marines" then
        startupEnv.MyTeam = "Marines"
    end

    local teamSetOk, teamSetError = pcall(function()
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local remotes = replicatedStorage:WaitForChild("Remotes", 10)
        local commF = remotes and remotes:WaitForChild("CommF_", 10)
        if not commF then error("Không tìm thấy Remotes.CommF_") end
        commF:InvokeServer("SetTeam", startupEnv.MyTeam)
    end)

    if teamSetOk then
        print("[AutoFactory] Đã set team: " .. tostring(startupEnv.MyTeam))
    else
        warn("[AutoFactory] Set team thất bại: " .. tostring(teamSetError))
    end
end

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
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local StarterGui        = game:GetService("StarterGui")

local lp = Players.LocalPlayer

-- ─────────────────────────────────────────────
-- CONFIG (tự chỉnh)
-- ─────────────────────────────────────────────
local CFG = {
    -- Factory
    CoreOffsetY   = 20,     -- Offset gốc của Auto Factory
    FactorySafePosition = Vector3.new(415.930, 199.602, -409.127), -- Điểm an toàn trên nóc Factory
    AttackRange   = 30,     -- Tầm fallback M1 bằng input
    RemoteAttackRange = 80, -- Điểm an toàn cố định cần đánh remote từ xa hơn
    LoopDelay     = 0,      -- task.wait() mỗi frame, giống Auto Factory gốc
    M1HoldTime    = 0.05,   -- Thời gian giữ chuột cho mỗi đòn Melee
    UseCombatRemotes = true, -- AttackFunction gốc; lỗi thì fallback input
    AttackNoAnimation = true, -- RegisterAttack(0) + RegisterHit, không chạy animation
    RemoteAttackDelay = 0,    -- Bản gốc không có client cooldown
    MoveSpeed         = 280,  -- Tốc độ di chuyển chung tới Core và Fruit (studs/s)
    TravelForce       = 1e5,  -- Lực float nhẹ khi đang bay, giữ chuyển động mượt
    CoreHoldForce     = 9e9,  -- Cùng mức FlyGuiV3 để Core không hất nhân vật ra
    CoreSnapDistance  = 4,    -- Chỉ snap đoạn cuối rất ngắn, tránh giật từ xa
    CoreHoldTolerance = 6,    -- Core đẩy lệch quá mức này thì khóa trả về điểm đánh
    FruitSnapDistance = 8,    -- toTarget(cf, true): ngưỡng gốc
    UseFactoryEntrance = true, -- Khi ở xa, requestEntrance tới Mansion trước
    FactoryEntranceMinDistance = 3000, -- Chỉ dùng Entrance nếu cách Factory ít nhất 3000 studs
    FactoryEntranceCooldown = 2, -- Tránh spam requestEntrance nếu server không dịch chuyển
    FactoryFinishDelay = 5, -- Chờ sau khi hạ Core rồi mới tiếp tục tác vụ khác

    -- Low-player server hop (chi tiết có thể ghi đè qua getgenv().LowPlayerHopConfig)
    AutoHopLowPlayer = true, -- Tự quét và hop sang server ít người khi chạy script

    -- Fruit
    FruitEnabled  = true,   -- Bật/tắt tính năng tìm fruit
    FruitRange    = 0,      -- <= 0: không giới hạn, quét mọi Fruit trong cùng Sea
    PickupDist    = 5,       -- Khoảng cách nhặt (phải đứng gần bao nhiêu)
    ReturnToCafeAfterPickup = true, -- Nhặt Fruit ngoài map xong tự về Café
    CafePosition = Vector3.new(-382, 74, 356), -- Tọa độ Café Sea 2 từ teleport_islands.lua
    CafeArrivalDistance = 10, -- Bán kính xác nhận đã về tới Café
    UseCafeEntrance = true, -- Ở xa thì requestEntrance Mansion rồi bay nốt về Café
    CafeEntranceMinDistance = 800, -- Chỉ dùng Mansion khi cách Café ít nhất 800 studs
    AutoStore     = true,   -- Tự lưu Fruit vật phẩm đang giữ
    StoreCooldown = 3,      -- Khoảng nghỉ giữa các lần thử lưu (giây)
    StoreRetryDelay = 15,   -- Thử lại Fruit bị server từ chối/lỗi tạm thời
    AutoRandomFruit = true, -- Random Fruit từ xa, không cần tới NPC Cousin
    RandomFruitInterval = 0.5, -- Chu kỳ kiểm tra remote
    RandomCooldownCheckDelay = 30, -- Khi đang cooldown, chỉ kiểm tra lại mỗi 30 giây
    AutoCloseSpinner = true, -- Tự đóng giao diện quay sau khi CloseButton xuất hiện
    AutoHideItemNotice = true, -- Tự ẩn Item/ItemUI sau khi nhận Fruit
    AutoCloseUICheckDelay = 0.2, -- Chu kỳ kiểm tra UI

    -- Webhook Discord (Thông báo nhặt, quay & lưu trái)
    WebhookEnabled    = true,  -- Bật/tắt gửi Webhook
    WebhookURL        = "",    -- Dán link Webhook Discord vào đây (hoặc getgenv().WebhookURL = "...")
    WebhookPing       = "@everyone", -- "@everyone", "" (không ping) hoặc "<@ID_CỦA_BẠN>"
    WebhookOnPickup   = true,  -- Gửi webhook khi nhặt được trái trên map
    WebhookOnRandom   = true,  -- Gửi webhook ngay khi Remote Random thành công
    WebhookOnStore    = true,  -- Gửi webhook khi cất trái vào Storage thành công
    WebhookMinRarity  = "Legendary", -- Chỉ dùng để lọc webhook; không hiển thị Rarity trên Discord
    WebhookUsername   = "Noti Fruit",
    WebhookAvatarURL  = "https://cdn.discordapp.com/attachments/1176496808155947030/1539261907322540132/ChatGPT_Image_20_16_58_18_thg_8_2026.png?ex=6a86559c&is=6a85041c&hm=8047a959f2e577dfa08b6133d0deb7e00609931a1ce3794e28a050b9c02cc397", -- Chỉ dùng URL ảnh công khai cố định; để trống sẽ không gửi avatar
    WebhookBannerURL  = "https://cdn.discordapp.com/attachments/1176496808155947030/1539262844946747572/ChatGPT_Image_20_20_42_18_thg_8_2026.png?ex=6a86567c&is=6a8504fc&hm=614cfffbc8df63bc0abbe6a9f87bf1ad7e5160b0395ea8861566c9649b9db6bf", -- Chỉ dùng URL ảnh công khai cố định; để trống sẽ không gửi thumbnail
    WebhookTitle      = "Noti Fruit",
    WebhookFooterText = "Dev By Gia ",
    WebhookColor      = 16776960,

    -- Combat: chỉ dùng Fighting Style, không fallback vũ khí khác
    AutoEquipMelee = true,
    AutoBuso       = true,   -- Luôn giữ Buso bật, kể cả sau khi respawn
    BusoCheckDelay = 1,      -- Chu kỳ kiểm tra khi Buso đang bật
    BusoRetryDelay = 3,      -- Khoảng nghỉ trước khi thử lại nếu bật thất bại
    BusoConfirmTimeout = 1.5,-- Chờ server replicate HasBuso trước khi fallback
    UseBusoKeyFallback = true, -- Dùng phím J nếu remote không bật được Buso
    AntiAFK        = true,
    Debug          = false,
}

-- Route Sea 2 lấy từ teleport_islands.lua. Mansion cách Factory khoảng 1.3k
-- studs nên route này rút ngắn đáng kể hành trình từ các khu vực xa.
local EntranceRoutes = {
    Sea2 = {
        ["Mansion"] = Vector3.new(-286.99, 306.14, 597.82),
    },
}

-- ─────────────────────────────────────────────
-- GLOBAL SWITCH
-- ─────────────────────────────────────────────
local globalEnv = getgenv()
-- Auto Factory sở hữu Auto Buso; dừng bản standalone để tránh hai loop cùng chạy.
globalEnv.AutoHakiThread = false
globalEnv.AutoBuso = false
globalEnv.AutoBusoRunToken = {}
if type(globalEnv.AutoHakiConfig) == "table" then
    globalEnv.AutoHakiConfig.AutoBuso = false
end

-- Auto Factory cần độc quyền điều khiển HumanoidRootPart trong lúc chạy.
-- Chỉ dừng hành trình hiện tại, không Destroy Island Teleport/GUI để người dùng
-- có thể bật lại sau khi Auto Factory kết thúc.
if type(globalEnv.IslandTeleport) == "table"
    and type(globalEnv.IslandTeleport.Stop) == "function" then
    pcall(function()
        globalEnv.IslandTeleport:Stop()
    end)
end

-- Test tele dùng BodyVelocity riêng; dừng nó trước khi Auto Factory sở hữu
-- chuyển động để lực test không giữ nhân vật đứng yên lúc đang bay tới Fruit.
if type(globalEnv.CoreTeleportTest) == "table"
    and type(globalEnv.CoreTeleportTest.Stop) == "function" then
    pcall(function()
        globalEnv.CoreTeleportTest:Stop("AutoFactory đã chạy")
    end)
end

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

local function GetHttpRequest()
    return (type(http_request) == "function" and http_request)
        or (type(request) == "function" and request)
        or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
        or (type(http) == "table" and type(http.request) == "function" and http.request)
        or (type(fluxus) == "table" and type(fluxus.request) == "function" and fluxus.request)
end

-- ─────────────────────────────────────────────
-- LOW-PLAYER SERVER HOP
-- Tích hợp từ hop_low_player.lua và buộc lifecycle vào AutoFactoryRunToken để
-- chạy lại script/nhấn STOP không tích lũy controller hay heartbeat cũ.
-- ─────────────────────────────────────────────
do
local previousHopController = rawget(globalEnv, "LowPlayerHopController")
if type(previousHopController) == "table"
    and type(previousHopController.Stop) == "function" then
    pcall(function()
        previousHopController.Stop(true)
    end)
end

local lowPlayerHopDefaults = {
    ApiUrl = "https://hop.giacode.workers.dev",
    AutoStart = true,
    InitialDelayMin = 30,       -- Chờ ít nhất 30 giây trước khi hop
    InitialDelayMax = 60,       -- Chờ ngẫu nhiên tối đa 60 giây trước khi hop
    TargetMinPlayers = 2,       -- Chỉ chọn/dừng ở server từ 2 người
    TargetMaxPlayers = 5,       -- đến tối đa 5 người
    MaxPages = 30,
    MaxPlayers = 5,             -- Giữ tương thích config cũ
    StopAtPlayers = 2,
    EmptyPageLimit = 4,
    PageDelay = 0.1,
    MaxAttempts = 8,
    RetryDelay = 1.5,
    JoinTimeout = 10,
    RandomizeTies = true,
    NotifyOnScreen = true,
    Verbose = true,
}

local LowPlayerHopConfig = rawget(globalEnv, "LowPlayerHopConfig")
if type(LowPlayerHopConfig) ~= "table" then
    LowPlayerHopConfig = {}
end
for key, value in pairs(lowPlayerHopDefaults) do
    if LowPlayerHopConfig[key] == nil then
        LowPlayerHopConfig[key] = value
    end
end
globalEnv.LowPlayerHopConfig = LowPlayerHopConfig

local function IsCurrentFactoryRun()
    return globalEnv.AutoFactory
        and globalEnv.AutoFactoryRunToken == runToken
end

local function SendLowPlayerHeartbeat()
    if not IsCurrentFactoryRun()
        or not game.JobId
        or game.JobId == ""
        or LowPlayerHopConfig.ApiUrl == "" then
        return
    end

    pcall(function()
        local httpRequest = GetHttpRequest()
        if not httpRequest then return end

        httpRequest({
            Url = LowPlayerHopConfig.ApiUrl .. "/api/heartbeat",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                username = lp.Name,
                jobId = game.JobId,
                placeId = tostring(game.PlaceId),
            }),
        })
    end)
end

local function FetchOccupiedServers()
    local occupied = { [game.JobId] = true }
    if LowPlayerHopConfig.ApiUrl == "" then return occupied end

    pcall(function()
        local httpRequest = GetHttpRequest()
        if not httpRequest then return end

        local response = httpRequest({
            Url = LowPlayerHopConfig.ApiUrl .. "/api/occupied",
            Method = "GET",
        })
        local statusCode = response and tonumber(
            response.StatusCode or response.Status or response.status_code
        )
        if statusCode == 200 then
            local data = HttpService:JSONDecode(response.Body)
            for _, jobId in ipairs(data.occupied or {}) do
                occupied[tostring(jobId)] = true
            end
        end
    end)

    return occupied
end

local function ReserveLowPlayerServer(jobId)
    if LowPlayerHopConfig.ApiUrl == "" then return end

    pcall(function()
        local httpRequest = GetHttpRequest()
        if not httpRequest then return end

        httpRequest({
            Url = LowPlayerHopConfig.ApiUrl .. "/api/reserve",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ jobId = tostring(jobId) }),
        })
    end)
end

local LowPlayerHopVisited = rawget(globalEnv, "LowPlayerHopVisited")
if type(LowPlayerHopVisited) ~= "table" then
    LowPlayerHopVisited = {}
end
LowPlayerHopVisited[game.JobId] = os.time() + 999999
globalEnv.LowPlayerHopVisited = LowPlayerHopVisited

local function IsLowPlayerServerVisited(jobId, occupiedMap)
    if occupiedMap and occupiedMap[jobId] then return true end

    local expireTime = LowPlayerHopVisited[jobId]
    if not expireTime then return false end
    if os.time() > expireTime then
        LowPlayerHopVisited[jobId] = nil
        return false
    end
    return true
end

local lowPlayerHopState = {
    Running = false,
    SessionId = 0,
    Status = "Idle",
    Attempts = 0,
}
local LowPlayerHopController = {}
local lowPlayerHopRandom = Random.new()

local function GetLowPlayerTargetRange()
    local minPlayers = math.max(math.floor(
        tonumber(LowPlayerHopConfig.TargetMinPlayers) or 2
    ), 1)
    local maxPlayers = math.max(math.floor(
        tonumber(LowPlayerHopConfig.TargetMaxPlayers) or 5
    ), 1)
    if minPlayers > maxPlayers then
        minPlayers, maxPlayers = maxPlayers, minPlayers
    end
    return minPlayers, maxPlayers
end

local function GetCurrentServerPlayerCount()
    return #Players:GetPlayers()
end

local function IsTargetPlayerCount(playerCount)
    local minPlayers, maxPlayers = GetLowPlayerTargetRange()
    playerCount = tonumber(playerCount)
    return playerCount ~= nil
        and playerCount >= minPlayers
        and playerCount <= maxPlayers
end

local function GetInitialHopDelay()
    local minDelay = math.max(
        tonumber(LowPlayerHopConfig.InitialDelayMin) or 30,
        0
    )
    local maxDelay = math.max(
        tonumber(LowPlayerHopConfig.InitialDelayMax) or 60,
        0
    )
    if minDelay > maxDelay then
        minDelay, maxDelay = maxDelay, minDelay
    end
    if minDelay == maxDelay then return minDelay end
    return lowPlayerHopRandom:NextNumber(minDelay, maxDelay)
end

local function NotifyLowPlayerHop(title, message, duration)
    if not LowPlayerHopConfig.NotifyOnScreen then return end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Hop Low Player",
            Text = message or "",
            Duration = duration or 3,
        })
    end)
end

local function SetLowPlayerHopStatus(message, showToast)
    lowPlayerHopState.Status = message
    if LowPlayerHopConfig.Verbose then
        print("[LowPlayerHop] " .. tostring(message))
    end
    if showToast then
        NotifyLowPlayerHop("Server Hop", message, 3)
    end
end

local function StopHopAtTargetServer(playerCount)
    local minPlayers, maxPlayers = GetLowPlayerTargetRange()
    SetLowPlayerHopStatus(string.format(
        "Server hiện có %d người (đạt %d-%d), dừng hop.",
        playerCount,
        minPlayers,
        maxPlayers
    ), true)
end

local function IsLowPlayerHopActive(sessionId)
    return IsCurrentFactoryRun()
        and lowPlayerHopState.Running
        and lowPlayerHopState.SessionId == sessionId
end

local function GetServerBrowser()
    local serverBrowser = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if serverBrowser and serverBrowser:IsA("RemoteFunction") then
        return serverBrowser
    end

    serverBrowser = ReplicatedStorage:WaitForChild("__ServerBrowser", 5)
    if serverBrowser and serverBrowser:IsA("RemoteFunction") then
        return serverBrowser
    end
    return nil
end

local function ChooseLowPlayerCandidate(candidates)
    if #candidates == 0 then return nil end
    if LowPlayerHopConfig.RandomizeTies and #candidates > 1 then
        return candidates[lowPlayerHopRandom:NextInteger(1, #candidates)]
    end
    return candidates[1]
end

local function FindLowPlayerViaServerBrowser(serverBrowser, sessionId, occupiedMap)
    local bestCount = math.huge
    local bestCandidates = {}
    local consecutiveEmpty = 0
    local targetMinPlayers, targetMaxPlayers = GetLowPlayerTargetRange()

    for page = 1, LowPlayerHopConfig.MaxPages do
        if not IsLowPlayerHopActive(sessionId) then return nil end

        local ok, servers = pcall(function()
            return serverBrowser:InvokeServer(page)
        end)
        if not ok or type(servers) ~= "table" or next(servers) == nil then
            consecutiveEmpty = consecutiveEmpty + 1
        else
            consecutiveEmpty = 0
            for jobId, info in pairs(servers) do
                local playerCount = type(info) == "table" and tonumber(info.Count) or nil
                if type(jobId) == "string"
                    and playerCount
                    and not IsLowPlayerServerVisited(jobId, occupiedMap) then
                    local candidate = {
                        JobId = jobId,
                        Players = playerCount,
                        Page = page,
                    }
                    if playerCount >= targetMinPlayers
                        and playerCount <= targetMaxPlayers then
                        if playerCount < bestCount then
                            bestCount = playerCount
                            bestCandidates = { candidate }
                        elseif playerCount == bestCount then
                            table.insert(bestCandidates, candidate)
                        end
                    end
                end
            end
        end

        if bestCount <= LowPlayerHopConfig.StopAtPlayers
            or consecutiveEmpty >= LowPlayerHopConfig.EmptyPageLimit then
            break
        end
        if LowPlayerHopConfig.PageDelay > 0 then
            task.wait(LowPlayerHopConfig.PageDelay)
        end
    end

    if #bestCandidates > 0 then
        return ChooseLowPlayerCandidate(bestCandidates)
    end
    return nil
end

local function FindLowPlayerViaRobloxApi(sessionId, occupiedMap)
    local httpRequest = GetHttpRequest()
    if not httpRequest then return nil end

    local cursor = ""
    local bestCount = math.huge
    local bestCandidates = {}
    local targetMinPlayers, targetMaxPlayers = GetLowPlayerTargetRange()

    for _ = 1, 4 do
        if not IsLowPlayerHopActive(sessionId) then return nil end

        local url = string.format(
            "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s",
            tostring(game.PlaceId),
            cursor ~= "" and ("&cursor=" .. cursor) or ""
        )
        local ok, response = pcall(function()
            return httpRequest({ Url = url, Method = "GET" })
        end)
        local statusCode = ok and response and tonumber(
            response.StatusCode or response.Status or response.status_code
        )
        if statusCode ~= 200 then break end

        local decoded, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)
        if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then
            break
        end

        for _, server in ipairs(data.data) do
            local jobId = tostring(server.id or "")
            local playerCount = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 12
            if jobId ~= ""
                and not IsLowPlayerServerVisited(jobId, occupiedMap)
                and playerCount < maxPlayers
                and playerCount >= targetMinPlayers
                and playerCount <= targetMaxPlayers then
                local candidate = {
                    JobId = jobId,
                    Players = playerCount,
                    Page = "API",
                }
                if playerCount < bestCount then
                    bestCount = playerCount
                    bestCandidates = { candidate }
                elseif playerCount == bestCount then
                    table.insert(bestCandidates, candidate)
                end
            end
        end

        if bestCount <= LowPlayerHopConfig.StopAtPlayers then break end
        cursor = data.nextPageCursor or ""
        if cursor == "" then break end
        task.wait(0.2)
    end

    return ChooseLowPlayerCandidate(bestCandidates)
end

local function RequestLowPlayerTeleport(serverBrowser, candidate)
    ReserveLowPlayerServer(candidate.JobId)
    LowPlayerHopVisited[candidate.JobId] = os.time() + 90
    SetLowPlayerHopStatus(string.format(
        "Đang vào server %d người (Né các acc khác)...",
        candidate.Players
    ), true)

    local success = false
    if serverBrowser then
        pcall(function()
            serverBrowser:InvokeServer("teleport", tostring(candidate.JobId))
            success = true
        end)
    end
    if not success then
        pcall(function()
            TeleportService:TeleportToPlaceInstance(
                game.PlaceId,
                tostring(candidate.JobId),
                lp
            )
            success = true
        end)
    end
    return success
end

local function RunLowPlayerHop(sessionId)
    local serverBrowser = GetServerBrowser()

    for attempt = 1, LowPlayerHopConfig.MaxAttempts do
        if not IsLowPlayerHopActive(sessionId) then return false end
        local currentPlayerCount = GetCurrentServerPlayerCount()
        if IsTargetPlayerCount(currentPlayerCount) then
            StopHopAtTargetServer(currentPlayerCount)
            return true
        end
        lowPlayerHopState.Attempts = attempt
        SetLowPlayerHopStatus(string.format(
            "Đang quét server (Lần %d/%d)...",
            attempt,
            LowPlayerHopConfig.MaxAttempts
        ), true)

        local occupiedMap = FetchOccupiedServers()
        local candidate = nil
        if serverBrowser then
            candidate = FindLowPlayerViaServerBrowser(
                serverBrowser,
                sessionId,
                occupiedMap
            )
        end
        if not candidate then
            candidate = FindLowPlayerViaRobloxApi(sessionId, occupiedMap)
        end
        if not IsLowPlayerHopActive(sessionId) then return false end

        if candidate and RequestLowPlayerTeleport(serverBrowser, candidate) then
            local deadline = os.clock() + LowPlayerHopConfig.JoinTimeout
            while IsLowPlayerHopActive(sessionId) and os.clock() < deadline do
                task.wait(0.25)
            end
            if IsLowPlayerHopActive(sessionId) then
                SetLowPlayerHopStatus("Đang thử server khác...", false)
            end
        end

        if attempt < LowPlayerHopConfig.MaxAttempts
            and LowPlayerHopConfig.RetryDelay > 0 then
            task.wait(LowPlayerHopConfig.RetryDelay)
        end
    end

    if IsLowPlayerHopActive(sessionId) then
        SetLowPlayerHopStatus("Hết lượt quét server.", true)
    end
    return false
end

function LowPlayerHopController.Start()
    if lowPlayerHopState.Running or not IsCurrentFactoryRun() then
        return false
    end

    local currentPlayerCount = GetCurrentServerPlayerCount()
    if IsTargetPlayerCount(currentPlayerCount) then
        StopHopAtTargetServer(currentPlayerCount)
        return false
    end

    lowPlayerHopState.Running = true
    lowPlayerHopState.Attempts = 0
    lowPlayerHopState.SessionId = lowPlayerHopState.SessionId + 1
    local sessionId = lowPlayerHopState.SessionId

    task.spawn(function()
        local ok, err = pcall(function()
            local initialDelay = GetInitialHopDelay()
            if initialDelay > 0 then
                SetLowPlayerHopStatus(string.format(
                    "Chờ %d giây trước khi hop...",
                    math.ceil(initialDelay)
                ), true)

                local deadline = os.clock() + initialDelay
                while IsLowPlayerHopActive(sessionId) and os.clock() < deadline do
                    local playerCount = GetCurrentServerPlayerCount()
                    if IsTargetPlayerCount(playerCount) then
                        StopHopAtTargetServer(playerCount)
                        return
                    end
                    task.wait(math.min(1, math.max(deadline - os.clock(), 0.05)))
                end
            end

            if not IsLowPlayerHopActive(sessionId) then return end
            local playerCount = GetCurrentServerPlayerCount()
            if IsTargetPlayerCount(playerCount) then
                StopHopAtTargetServer(playerCount)
                return
            end
            RunLowPlayerHop(sessionId)
        end)
        if not ok and LowPlayerHopConfig.Verbose then
            warn("[LowPlayerHop] " .. tostring(err))
        end
        if lowPlayerHopState.SessionId == sessionId then
            lowPlayerHopState.Running = false
        end
    end)
    return true
end

function LowPlayerHopController.Stop(silent)
    lowPlayerHopState.Running = false
    lowPlayerHopState.SessionId = lowPlayerHopState.SessionId + 1
    if not silent then
        SetLowPlayerHopStatus("Đã dừng.", true)
    end
    return true
end

function LowPlayerHopController.GetState()
    return {
        Running = lowPlayerHopState.Running,
        SessionId = lowPlayerHopState.SessionId,
        Status = lowPlayerHopState.Status,
        Attempts = lowPlayerHopState.Attempts,
    }
end

globalEnv.LowPlayerHopController = LowPlayerHopController

-- Báo server hiện tại lên Worker và duy trì heartbeat cho multi-account.
task.spawn(function()
    task.wait(2)
    SendLowPlayerHeartbeat()
end)
task.spawn(function()
    while IsCurrentFactoryRun() do
        task.wait(90)
        if not IsCurrentFactoryRun() then break end
        SendLowPlayerHeartbeat()
    end
end)

if CFG.AutoHopLowPlayer and LowPlayerHopConfig.AutoStart then
    LowPlayerHopController.Start()
end
end

local function GetConfiguredWebhookURL()
    local envUrl = tostring((globalEnv and globalEnv.WebhookURL) or "")
        :gsub("^%s+", ""):gsub("%s+$", "")
    if envUrl ~= "" then return envUrl end

    return tostring(CFG.WebhookURL or "")
        :gsub("^%s+", ""):gsub("%s+$", "")
end

-- ─────────────────────────────────────────────
-- CƠ CHẾ ĐỌC RARITY TRỰC TIẾP TỪ GAME
-- ─────────────────────────────────────────────
local GameFruitInfo = nil

pcall(function()
    local fruitInfoModule = ReplicatedStorage:WaitForChild("FruitInfo", 5)
    if fruitInfoModule then
        local data = require(fruitInfoModule)
        if type(data) == "table" and type(data.List) == "table" then
            GameFruitInfo = data
        end
    end
end)

-- Bảng dự phòng các trái cấp cao (Mythical = 5, Legendary = 4)
local HIGH_TIER_FRUITS = {
    -- 🔴 Mythical (Cấp 5 - Đỏ Ruby)
    kitsune = 5, dragon = 5, leopard = 5, ["t-rex"] = 5, trex = 5,
    mammoth = 5, dough = 5, shadow = 5, venom = 5, control = 5,
    spirit = 5, gravity = 5,

    -- 🟣 Legendary (Cấp 4 - Tím Huyền Bí)
    portal = 4, blizzard = 4, rumble = 4, buddha = 4, sound = 4,
    phoenix = 4, spider = 4, string = 4, love = 4, pain = 4, paw = 4, quake = 4,
}

local RARITY_DETAILS = {
    common    = { rarity = "Common",    level = 1, badge = "⚪ Common",    color = 9807270 },
    uncommon  = { rarity = "Uncommon",  level = 2, badge = "🟢 Uncommon",  color = 65332 },
    rare      = { rarity = "Rare",      level = 3, badge = "🔵 Rare",      color = 3447003 },
    legendary = { rarity = "Legendary", level = 4, badge = "🟣 Legendary", color = 10696174 },
    mythical  = { rarity = "Mythical",  level = 5, badge = "🔴 Mythical",  color = 16711765 },
}

local function ReadFruitRarityEntry(entry)
    if type(entry) ~= "table" then return nil end
    local rarity = entry.Rarity
    local rarityName
    if type(rarity) == "table" then
        rarityName = rarity.Name
    elseif type(rarity) == "string" then
        rarityName = rarity
    end
    if type(rarityName) ~= "string" then return nil end
    return RARITY_DETAILS[string.lower(rarityName)]
end

local function GetFruitRarity(fruitName)
    local rawName = tostring(fruitName or "")
    local clean = rawName:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local baseName = rawName:gsub("%s+[Ff][Rr][Uu][Ii][Tt]$", "")

    -- FruitInfo.List được game lập chỉ mục bằng storage name, thường có dạng
    -- "Magma-Magma" trong khi Tool hiển thị là "Magma Fruit".
    local fruitList = GameFruitInfo and GameFruitInfo.List
    if type(fruitList) == "table" then
        local storageName = baseName .. "-" .. baseName
        -- Script gốc (deobfuscated.lua dòng 12452) dùng storageName làm key chính.
        -- Ưu tiên storageName trước để tránh match nhầm khi rawName/baseName trùng
        -- key khác trong FruitInfo.List.
        local matched = fruitList[storageName]
            or fruitList[rawName]
            or fruitList[baseName]

        local rarityInfo = ReadFruitRarityEntry(matched)
        if rarityInfo then return rarityInfo end

        -- Fallback không phân biệt hoa/thường cho server có key khác casing.
        local wanted = string.lower(storageName)
        for key, entry in pairs(fruitList) do
            if type(key) == "string" and string.lower(key) == wanted then
                rarityInfo = ReadFruitRarityEntry(entry)
                if rarityInfo then return rarityInfo end
                break
            end
        end
    end

    -- 2. Tra cứu từ khóa dự phòng thông minh
    for name, tier in pairs(HIGH_TIER_FRUITS) do
        if string.find(clean, name, 1, true) then
            if tier == 5 then
                return { rarity = "Mythical", level = 5, badge = "🔴 Mythical", color = 16711765 }
            else
                return { rarity = "Legendary", level = 4, badge = "🟣 Legendary", color = 10696174 }
            end
        end
    end

    return { rarity = "Unknown", level = 0, badge = "⚪ Unknown", color = 16776960 }
end

local function SendFruitWebhook(eventType, fruitName)
    if not CFG.WebhookEnabled then return end
    local webhookUrl = GetConfiguredWebhookURL()

    if webhookUrl == "" or not string.find(webhookUrl, "http", 1, true) then
        return
    end

    if eventType == "Picked" and not CFG.WebhookOnPickup then return end
    if eventType == "Random" and not CFG.WebhookOnRandom then return end
    if eventType == "Stored" and not CFG.WebhookOnStore then return end

    local cleanFruitName = tostring(fruitName or "Unknown Fruit")
    local rarityInfo = GetFruitRarity(cleanFruitName)

    -- BỘ LỌC CẤP BẬC: Mặc định chỉ thông báo các trái Mythical và Legendary
    local minRarity = tostring(
        (globalEnv and globalEnv.WebhookMinRarity)
        or CFG.WebhookMinRarity
        or "Legendary"
    ):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if minRarity ~= "legendary" and minRarity ~= "mythical" and minRarity ~= "all" then
        Log("WebhookMinRarity không hợp lệ, dùng mặc định Legendary: " .. minRarity)
        minRarity = "legendary"
    end

    if minRarity == "legendary" then
        if rarityInfo.level < 4 then
            Log(string.format("Webhook: Bỏ qua trái '%s' (%s) vì dưới mức Legendary/Mythical", cleanFruitName, rarityInfo.rarity))
            return
        end
    elseif minRarity == "mythical" then
        if rarityInfo.level < 5 then
            Log(string.format("Webhook: Bỏ qua trái '%s' (%s) vì dưới mức Mythical", cleanFruitName, rarityInfo.rarity))
            return
        end
    end

    task.spawn(function()
        local httpRequest = GetHttpRequest()
        if not httpRequest then
            Log("Webhook: Executor không hỗ trợ hàm HTTP Request")
            return
        end

        local fieldTitles = {
            Picked = "Picked Fruit",
            Random = "Random Fruit",
            Stored = "Stored Fruit",
        }
        local fieldTitle = fieldTitles[eventType] or "Fruit"
        local playerName = lp and lp.Name or "Unknown"
        local timeString = os.date("%Y-%m-%d %H:%M:%S")
        local isoTimestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

        local embedFields = {
            {
                name = fieldTitle,
                value = "```\n" .. cleanFruitName .. "\n```",
                inline = false,
            },
            {
                name = "Username",
                value = "||" .. playerName .. "||",
                inline = true,
            },
            {
                name = "Time",
                value = timeString,
                inline = true,
            },
            {
                name = "PlaceId",
                value = tostring(game.PlaceId),
                inline = true,
            },
        }

        local embed = {
            title = tostring(CFG.WebhookTitle or "Banana Hub Notification"),
            description = "**Main Status**\nUsername : ||" .. playerName .. "||",
            color = tonumber(CFG.WebhookColor) or 16776960,
            footer = {
                text = tostring(CFG.WebhookFooterText or "Dev By Gia "),
            },
            fields = embedFields,
            timestamp = isoTimestamp,
        }

        local bannerUrl = tostring(CFG.WebhookBannerURL or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if bannerUrl ~= "" then
            embed.thumbnail = { url = bannerUrl }
        end

        local payload = {
            content = tostring(CFG.WebhookPing or ""),
            username = tostring(CFG.WebhookUsername or "Binini Hub"),
            embeds = { embed },
        }
        local avatarUrl = tostring(CFG.WebhookAvatarURL or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if avatarUrl ~= "" then
            payload.avatar_url = avatarUrl
        end

        local encodeOk, jsonBody = pcall(function()
            return HttpService:JSONEncode(payload)
        end)
        if not encodeOk or not jsonBody then
            Log("Webhook JSONEncode error: " .. tostring(jsonBody))
            return
        end

        local postOk, response = pcall(function()
            return httpRequest({
                Url = webhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                },
                Body = jsonBody,
            })
        end)

        local statusCode = type(response) == "table" and tonumber(
            response.StatusCode or response.Status or response.status_code
        ) or nil
        local requestSucceeded = postOk
            and (type(response) ~= "table" or response.Success ~= false)
            and (statusCode == nil or (statusCode >= 200 and statusCode < 300))

        if requestSucceeded then
            Log("Webhook [" .. eventType .. "] đã gửi thành công: " .. cleanFruitName)
        else
            local responseDetail = response
            if type(response) == "table" then
                responseDetail = response.Body or response.Message or statusCode or "Unknown response"
            end
            Log("Webhook [" .. eventType .. "] gửi thất bại: " .. tostring(responseDetail))
        end
    end)
end

-- Tích hợp từ bản standalone đã được kiểm thử thực tế. Controller được nạp
-- riêng để việc chờ module UI không chặn Factory/Buso/Random Fruit khởi động.
local SpinnerController = nil
task.spawn(function()
    if not CFG.AutoCloseSpinner then return end

    local success, result = pcall(function()
        local controllers = ReplicatedStorage:WaitForChild("Controllers", 10)
        local ui = controllers and controllers:WaitForChild("UI", 10)
        local spinnerModule = ui and ui:WaitForChild("Spinner", 10)
        if not spinnerModule then error("Không tìm thấy Controllers.UI.Spinner") end
        return require(spinnerModule)
    end)
    if success and type(result) == "table"
        and globalEnv.AutoFactory
        and globalEnv.AutoFactoryRunToken == runToken then
        SpinnerController = result
        Log("Auto Close: Spinner controller ready")
    else
        Log("Auto Close: không load được Spinner controller: " .. tostring(result))
    end
end)

-- Dùng một loop cho cả hai GUI và buộc vào runToken. Khi bấm STOP hoặc chạy
-- lại script, loop cũ tự thoát nên không tích lũy task quét PlayerGui.
task.spawn(function()
    local checkDelay = math.max(
        tonumber(CFG.AutoCloseUICheckDelay) or 0.2,
        0.05
    )

    while globalEnv.AutoFactory and globalEnv.AutoFactoryRunToken == runToken do
        task.wait(checkDelay)
        if not globalEnv.AutoFactory
            or globalEnv.AutoFactoryRunToken ~= runToken then
            break
        end

        pcall(function()
            local currentPlayerGui = lp:FindFirstChild("PlayerGui")
            if not currentPlayerGui then return end

            if CFG.AutoCloseSpinner then
                local spinnerWindow = currentPlayerGui:FindFirstChild("SpinnerWindow")
                if spinnerWindow and spinnerWindow.Enabled then
                    local aboveSpinner = spinnerWindow:FindFirstChild("AboveSpinner")
                    local navigation = aboveSpinner
                        and aboveSpinner:FindFirstChild("Navigation")
                    local closeButton = navigation
                        and navigation:FindFirstChild("CloseButton")

                    if closeButton and closeButton.Visible then
                        if SpinnerController
                            and type(SpinnerController.Close) == "function" then
                            SpinnerController:Close()
                        else
                            spinnerWindow.Enabled = false
                        end
                        Log("Auto Close: đã đóng SpinnerWindow")
                    end
                end
            end

            if CFG.AutoHideItemNotice then
                local itemNotice = currentPlayerGui:FindFirstChild("Item")
                    or currentPlayerGui:FindFirstChild("ItemUI")
                if itemNotice and itemNotice.Enabled then
                    itemNotice.Enabled = false
                    Log("Auto Close: đã ẩn ItemUI")
                end
            end
        end)
    end
end)

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
        VIM:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
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

-- Auto Buso chạy riêng để InvokeServer/thời gian xác nhận không chặn vòng combat.
-- Loop tự nhận character mới sau respawn nên không cần CharacterAdded connection.
local function HasBuso(character)
    return character and character:FindFirstChild("HasBuso") ~= nil
end

local function WaitForBuso(character, timeout)
    local deadline = tick() + math.max(tonumber(timeout) or 0, 0)
    repeat
        if HasBuso(character) then return true end
        if not globalEnv.AutoFactory
            or globalEnv.AutoFactoryRunToken ~= runToken
            or character ~= lp.Character
            or not character.Parent then
            return false
        end
        task.wait(0.1)
    until tick() >= deadline
    return HasBuso(character)
end

local function PressBusoKey()
    local ok, err = pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.J, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.J, false, game)
    end)
    if not ok then
        pcall(function()
            VIM:SendKeyEvent(false, Enum.KeyCode.J, false, game)
        end)
        return false, err
    end
    return true
end

local function EnsureBusoEnabled()
    local character = GetChar()
    local humanoid = GetHumanoid()
    local root = GetHRP()
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        globalEnv.AutoFactoryBusoEnabled = false
        return false, "CharacterNotReady"
    end
    if HasBuso(character) then
        globalEnv.AutoFactoryBusoEnabled = true
        return true, "AlreadyEnabled"
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    local remoteOk, remoteError = false, "Không tìm thấy CommF_"
    if commF then
        remoteOk, remoteError = pcall(function()
            return commF:InvokeServer("Buso")
        end)
    end

    if WaitForBuso(character, CFG.BusoConfirmTimeout) then
        globalEnv.AutoFactoryBusoEnabled = true
        Log("Auto Buso: enabled by remote")
        return true, "Remote"
    end

    if CFG.UseBusoKeyFallback
        and globalEnv.AutoFactory
        and globalEnv.AutoFactoryRunToken == runToken then
        local keyOk, keyError = PressBusoKey()
        if keyOk and WaitForBuso(character, 0.75) then
            globalEnv.AutoFactoryBusoEnabled = true
            Log("Auto Buso: enabled by J fallback")
            return true, "KeyFallback"
        end
        if not keyOk then remoteError = keyError end
    end

    globalEnv.AutoFactoryBusoEnabled = false
    return false, remoteOk and "HasBusoNotConfirmed" or tostring(remoteError)
end

task.spawn(function()
    while globalEnv.AutoFactory and globalEnv.AutoFactoryRunToken == runToken do
        if CFG.AutoBuso then
            local ok, enabled, status = pcall(EnsureBusoEnabled)
            if not ok then
                Log("Auto Buso error: " .. tostring(enabled))
                enabled = false
            elseif not enabled then
                Log("Auto Buso retry: " .. tostring(status))
            end
            local delay = enabled and CFG.BusoCheckDelay or CFG.BusoRetryDelay
            task.wait(math.max(tonumber(delay) or 1, 0.1))
        else
            globalEnv.AutoFactoryBusoEnabled = false
            task.wait(1)
        end
    end
    globalEnv.AutoFactoryBusoEnabled = false
end)

local function IsMeleeTool(item)
    if not item or not item:IsA("Tool") then return false end
    local toolTip = string.lower(tostring(item.ToolTip or ""))
    return toolTip == "melee" or toolTip == "fighting style"
end

local function IsFruitTool(item)
    if not item or not item:IsA("Tool") then return false end
    local itemName = string.lower(item.Name)
    if string.find(itemName, "fruit", 1, true) == nil then return false end
    -- Đảm bảo đây là vật phẩm Fruit nhặt được (có Handle part), tránh nhầm với kĩ năng trái đã ăn
    local handle = item:FindFirstChild("Handle")
    return handle ~= nil and handle:IsA("BasePart")
end

local function NormalizeFruitDisplayName(value)
    if type(value) ~= "string" then return nil end
    local name = value:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or string.lower(name) == "fruit" then return nil end

    -- OriginalName thường lặp lại tên hai lần, ví dụ:
    -- "Magma-Magma", "T-Rex-T-Rex" hoặc "Dragon (West)-Dragon (West)".
    -- Thử tất cả dấu '-' để xử lý đúng cả tên có dấu '-' bên trong.
    for separator = 1, #name do
        if string.sub(name, separator, separator) == "-" then
            local first = string.sub(name, 1, separator - 1)
            local second = string.sub(name, separator + 1)
            if first ~= "" and string.lower(first) == string.lower(second) then
                return first .. " Fruit"
            end
        end
    end
    return name
end

local function GetFruitOriginalName(item)
    if not item then return nil end

    local origOk, origValue = pcall(function()
        return item:GetAttribute("OriginalName")
    end)
    if origOk and type(origValue) == "string" and origValue ~= "" then
        return origValue
    end

    local originalNameValue = item:FindFirstChild("OriginalName")
    if originalNameValue and originalNameValue:IsA("StringValue")
        and originalNameValue.Value ~= "" then
        return originalNameValue.Value
    end

    return nil
end

local function ResolveFruitDisplayName(item)
    if not item then return nil end

    -- Tool.Name là tên hiển thị thực tế mà bản cũ dùng đúng. OriginalName chỉ
    -- là khóa Storage nên chỉ dùng làm fallback nếu Tool vẫn mang tên "Fruit".
    local directName = NormalizeFruitDisplayName(item.Name)
    if directName then return directName end

    return NormalizeFruitDisplayName(GetFruitOriginalName(item))
end

local function WaitForResolvedFruitDisplayName(item, timeout)
    local deadline = tick() + math.max(tonumber(timeout) or 0.8, 0)
    local metadataFallback = nil
    repeat
        local directName = item and NormalizeFruitDisplayName(item.Name) or nil
        if directName then return directName end
        metadataFallback = item
            and NormalizeFruitDisplayName(GetFruitOriginalName(item))
            or metadataFallback
        if not item or not item.Parent
            or not globalEnv.AutoFactory
            or globalEnv.AutoFactoryRunToken ~= runToken then
            break
        end
        task.wait(0.05)
    until tick() >= deadline

    return metadataFallback
end

local function SnapshotOwnedFruitTools()
    local snapshot = {}
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if IsFruitTool(item) then
                snapshot[item] = true
            end
        end
    end
    scan(lp:FindFirstChild("Backpack"))
    scan(GetChar())
    return snapshot
end

local function WaitForNewOwnedFruit(snapshot, timeout)
    local deadline = tick() + math.max(tonumber(timeout) or 3, 0.5)
    repeat
        local function findIn(container)
            if not container then return nil end
            for _, item in ipairs(container:GetChildren()) do
                if not snapshot[item] and IsFruitTool(item) then
                    return item
                end
            end
            return nil
        end

        local fruit = findIn(lp:FindFirstChild("Backpack")) or findIn(GetChar())
        if fruit then return fruit end
        if not globalEnv.AutoFactory or globalEnv.AutoFactoryRunToken ~= runToken then
            return nil
        end
        task.wait(0.1)
    until tick() >= deadline
    return nil
end

local worldFruitPickupInProgress = false
local randomPurchaseInProgress = false
local storeInProgress = false
local cafeReturnPending = false
local cafeReturnFruitName = nil

local function QueueCafeReturn(fruitName)
    if not CFG.ReturnToCafeAfterPickup then return end
    cafeReturnPending = true
    cafeReturnFruitName = type(fruitName) == "string" and fruitName or nil
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
    if not CFG.AttackNoAnimation then return false, "Attack No Animation đã tắt" end

    local now = tick()
    local attackDelay = math.max(tonumber(CFG.RemoteAttackDelay) or 0, 0)
    if attackDelay > 0 and (now - lastRemoteAttack) < attackDelay then
        return true, "Remote"
    end

    local attackRemote, hitRemote = ResolveCombatRemotes()
    if not attackRemote or not hitRemote then
        return false, "Không tìm thấy combat remotes"
    end

    local hitPart = core and core:FindFirstChild("HumanoidRootPart")
    if not hitPart then return false, "Core thiếu hit part" end

    local ok, err = pcall(function()
        -- AttackFunction gốc khi Attack No Animation bật:
        -- RegisterAttack(0), lấy hit chính ra khỏi danh sách AOE rồi gửi phần
        -- hit phụ còn lại. Core là mục tiêu duy nhất nên danh sách phụ rỗng.
        local secondaryHitParts = {}
        attackRemote:FireServer(0)
        hitRemote:FireServer(hitPart, secondaryHitParts)
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
    coreHoldForce = nil,
    previousPlatformStand = nil,
    platformHumanoid = nil,
    addedTeleportTag = false,
    entranceCooldown = 0,
}

local function MarkTeleporting()
    pcall(function()
        if not CollectionService:HasTag(lp, "Teleporting") then
            CollectionService:AddTag(lp, "Teleporting")
            moveState.addedTeleportTag = true
        end
    end)
end

-- Lực bay gốc dùng chung cho Core và Fruit. Không cập nhật thuộc tính lực ở
-- mỗi Heartbeat để giữ nguyên đường bay Fruit đã chạy mượt trước đó.
local function EnsureMoveFloat(hrp)
    if not hrp then return end
    if moveState.coreHoldForce then
        pcall(function() moveState.coreHoldForce:Destroy() end)
        moveState.coreHoldForce = nil
    end

    -- Dọn lực giữ mồ côi nếu executor từng dừng/rerun giữa CoreHold.
    for _, forceName in ipairs({
        "AutoFactoryCoreHoldForce",
        "CoreTeleportTestForce",
    }) do
        local staleForce = hrp:FindFirstChild(forceName)
        if staleForce then pcall(function() staleForce:Destroy() end) end
    end

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
    local forceValue = math.max(tonumber(CFG.TravelForce) or 1e5, 0)
    force.MaxForce = Vector3.new(forceValue, forceValue, forceValue)
    force.P = 1e4
    force.Parent = hrp
    moveState.floatForce = force
end

-- Lực giữ mạnh chỉ tồn tại khi đã đến Core; hoàn toàn tách khỏi lực bay Fruit.
local function EnsureCoreHoldForce(hrp)
    if not hrp then return end
    if moveState.floatForce then
        pcall(function() moveState.floatForce:Destroy() end)
        moveState.floatForce = nil
    end
    if moveState.coreHoldForce and moveState.coreHoldForce.Parent == hrp then return end
    if moveState.coreHoldForce then
        pcall(function() moveState.coreHoldForce:Destroy() end)
        moveState.coreHoldForce = nil
    end

    local staleForce = hrp:FindFirstChild("AutoFactoryCoreHoldForce")
    if staleForce then pcall(function() staleForce:Destroy() end) end

    local forceValue = math.max(tonumber(CFG.CoreHoldForce) or 9e9, 0)
    local force = Instance.new("BodyVelocity")
    force.Name = "AutoFactoryCoreHoldForce"
    force.Velocity = Vector3.zero
    force.MaxForce = Vector3.new(forceValue, forceValue, forceValue)
    force.P = 1e4
    force.Parent = hrp
    moveState.coreHoldForce = force
end

local function RestoreMoveCharacter(keepFloatForce, keepNoclip)
    globalEnv.noclip = keepNoclip == true

    local force = moveState.floatForce
    if not keepFloatForce then
        moveState.floatForce = nil
        if force then pcall(function() force:Destroy() end) end
    end

    local coreHoldForce = moveState.coreHoldForce
    moveState.coreHoldForce = nil
    if coreHoldForce then pcall(function() coreHoldForce:Destroy() end) end

    local hrp = GetHRP()
    if hrp then
        StopRootVelocity(hrp)
    end
    local platformHumanoid = moveState.platformHumanoid
    if platformHumanoid and platformHumanoid.Parent
        and moveState.previousPlatformStand ~= nil then
        platformHumanoid.PlatformStand = moveState.previousPlatformStand
    end
    moveState.previousPlatformStand = nil
    moveState.platformHumanoid = nil

    if moveState.addedTeleportTag then
        pcall(function() CollectionService:RemoveTag(lp, "Teleporting") end)
        moveState.addedTeleportTag = false
    end

    if not keepNoclip then
        for part, oldCanCollide in pairs(moveState.collisionState) do
            if part and part.Parent then
                pcall(function() part.CanCollide = oldCanCollide end)
            end
        end
        table.clear(moveState.collisionState)
    end
end

local function CancelMove(restoreCharacter)
    moveState.active = false
    moveState.target = nil
    moveState.purpose = nil
    moveState.snapDistance = 0
    moveState.speed = 0
    if restoreCharacter then RestoreMoveCharacter() end
end

-- Dùng requestEntrance tới Mansion rồi tiếp tục bay bằng ToTarget.
-- Factory và Café dùng chung route/cooldown để không spam CommF_.
local function TryMansionEntrance(targetPosition, enabled, minDistanceValue, destinationName)
    if not enabled or typeof(targetPosition) ~= "Vector3" then
        return false, "EntranceDisabled"
    end

    local hrp = GetHRP()
    local humanoid = GetHumanoid()
    if not hrp or not humanoid or humanoid.Health <= 0 then
        return false, "CharacterNotReady"
    end

    local minDistance = math.max(
        tonumber(minDistanceValue) or 0,
        0
    )
    local directDistance = (hrp.Position - targetPosition).Magnitude
    if directDistance < minDistance then
        return false, "EntranceNotNeeded"
    end
    if tick() < (moveState.entranceCooldown or 0) then
        return false, "EntranceCooldown"
    end

    local entrance = EntranceRoutes.Sea2 and EntranceRoutes.Sea2["Mansion"]
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not entrance or not commF then
        return false, "EntranceUnavailable"
    end

    moveState.entranceCooldown = tick() + math.max(
        tonumber(CFG.FactoryEntranceCooldown) or 2,
        0.5
    )

    CancelMove(true)
    MarkTeleporting()
    local oldPosition = hrp.Position
    local requestOk, requestError = pcall(function()
        commF:InvokeServer("requestEntrance", entrance)
    end)
    if not requestOk then
        RestoreMoveCharacter()
        Log("Mansion Entrance lỗi: " .. tostring(requestError))
        return false, "EntranceRemoteError"
    end

    task.wait(0.2)
    local newRoot = GetHRP()
    local moved = newRoot
        and (newRoot.Position - oldPosition).Magnitude > 100
    if newRoot then StopRootVelocity(newRoot) end
    RestoreMoveCharacter()

    if moved then
        Log("Đã dùng Entrance Mansion để tới gần "
            .. tostring(destinationName or "mục tiêu"))
        return true, "EntranceMansion"
    end
    return false, "EntranceRejected"
end

local function TryFactoryEntrance(targetPosition)
    return TryMansionEntrance(
        targetPosition,
        CFG.UseFactoryEntrance,
        CFG.FactoryEntranceMinDistance,
        "Factory"
    )
end

local function TryCafeEntrance(targetPosition)
    return TryMansionEntrance(
        targetPosition,
        CFG.UseCafeEntrance,
        CFG.CafeEntranceMinDistance,
        "Café"
    )
end

-- Giữ nhân vật ổn định khi đã vào tầm Core. BodyVelocity triệt vận tốc/rơi;
-- Heartbeat chỉ khóa trả về mục tiêu khi hitbox của Core đẩy lệch quá tolerance.
local function BeginCoreHold(targetCF)
    if typeof(targetCF) ~= "CFrame" then
        return false, "Điểm giữ Core không hợp lệ"
    end

    local hrp = GetHRP()
    local humanoid = GetHumanoid()
    if not hrp or not humanoid or humanoid.Health <= 0 then
        return false, "Character chưa sẵn sàng"
    end

    if moveState.purpose ~= "CoreHold"
        or not moveState.coreHoldForce
        or moveState.coreHoldForce.Parent ~= hrp then
        CancelMove(false)
        moveState.purpose = "CoreHold"
        RestoreMoveCharacter(false, true)
        EnsureCoreHoldForce(hrp)
        moveState.purpose = "CoreHold"
    end

    -- Khác với giữ vận tốc bằng 0, phải nhớ chính xác điểm đánh để Heartbeat
    -- kéo trả ngay khi lực/hitbox của Core hất nhân vật ra ngoài.
    moveState.target = targetCF
    globalEnv.noclip = true
    if moveState.previousPlatformStand == nil then
        moveState.previousPlatformStand = humanoid.PlatformStand
        moveState.platformHumanoid = humanoid
    end
    humanoid.PlatformStand = true
    EnsureCoreHoldForce(hrp)
    moveState.coreHoldForce.Velocity = Vector3.zero
    StopRootVelocity(hrp)
    return true
end

local function LeaveSeat(hrp, humanoid)
    CancelMove(true)
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait()
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
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
        local arrivedAtCore = purpose == "Core"
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
        if arrivedAtCore then
            RestoreMoveCharacter(false, true)
            moveState.purpose = "CoreHold"
            moveState.target = cf
            EnsureCoreHoldForce(hrp)
            if moveState.previousPlatformStand == nil then
                moveState.previousPlatformStand = humanoid.PlatformStand
                moveState.platformHumanoid = humanoid
            end
            humanoid.PlatformStand = true
            MarkTeleporting()
        else
            RestoreMoveCharacter()
        end
        return true, "Snap"
    end

    local moveSpeed = math.max(tonumber(CFG.MoveSpeed) or 300, 1)

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
    if moveState.previousPlatformStand == nil then
        moveState.previousPlatformStand = humanoid.PlatformStand
        moveState.platformHumanoid = humanoid
    end
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
    local holdingCore = moveState.purpose == "CoreHold"
    if not moveState.active and not holdingCore then return end
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

    if holdingCore then
        local holdTolerance = math.max(
            tonumber(CFG.CoreHoldTolerance) or 6,
            1
        )
        local drift = (hrp.Position - targetCF.Position).Magnitude

        globalEnv.noclip = true
        if moveState.previousPlatformStand == nil then
            moveState.previousPlatformStand = humanoid.PlatformStand
            moveState.platformHumanoid = humanoid
        end
        humanoid.PlatformStand = true
        EnsureCoreHoldForce(hrp)
        moveState.coreHoldForce.Velocity = Vector3.zero

        -- Core có lực/hitbox đẩy người chơi ra. CoreHold cũ chỉ triệt velocity
        -- tại vị trí đã bị đẩy nên nhân vật vẫn bay xa. Chỉ snap lại khi lệch
        -- quá tolerance để giữ chắc mà không ghi CFrame liên tục lúc đang yên.
        if drift > holdTolerance then
            MarkTeleporting()
            hrp.CFrame = targetCF
        end
        StopRootVelocity(hrp)
        return
    end

    local currentPos = hrp.Position
    local targetPos = targetCF.Position
    local offset = targetPos - currentPos
    local remaining = offset.Magnitude

    if remaining <= moveState.snapDistance then
        local arrivedAtCore = moveState.purpose == "Core"
        hrp.CFrame = targetCF
        StopRootVelocity(hrp)
        CancelMove(false)
        if arrivedAtCore then
            RestoreMoveCharacter(false, true)
            moveState.purpose = "CoreHold"
            moveState.target = targetCF
            EnsureCoreHoldForce(hrp)
            if moveState.previousPlatformStand == nil then
                moveState.previousPlatformStand = humanoid.PlatformStand
                moveState.platformHumanoid = humanoid
            end
            humanoid.PlatformStand = true
            MarkTeleporting()
        else
            RestoreMoveCharacter()
        end
        return
    end

    -- Heartbeat truyền dt trực tiếp; giới hạn dt để một frame lag không tạo bước nhảy quá lớn.
    local frameTime = math.min(math.max(tonumber(dt) or (1 / 60), 0), 0.1)
    local step = math.min(moveState.speed * frameTime, remaining)
    local newPos = currentPos + offset.Unit * step
    local targetRotation = targetCF.Rotation

    globalEnv.noclip = true
    humanoid.PlatformStand = true
    EnsureMoveFloat(hrp)
    hrp.CFrame = CFrame.new(newPos) * targetRotation
    StopRootVelocity(hrp)
end)

TrackConnection(RunService.Stepped, function()
    if not moveState.active and moveState.purpose ~= "CoreHold" then return end
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

    local melee, equipError = EquipMelee()
    if not melee then
        Log(equipError)
        return nil, equipError
    end

    local coreDistance = DistTo(coreRoot.Position)

    -- AttackFunction gốc không đánh khi Character.Stun.Value ~= 0.
    local stun = char:FindFirstChild("Stun")
    if stun and stun:IsA("ValueBase") and stun.Value ~= 0 then
        return nil, "Đang bị Stun"
    end

    local remoteRange = math.max(
        tonumber(CFG.RemoteAttackRange) or 80,
        tonumber(CFG.AttackRange) or 30
    )
    local remoteOk, attackMode = false, "Core ngoài tầm remote"
    if coreDistance <= remoteRange then
        remoteOk, attackMode = TrySourceMeleeAttack(core)
        if remoteOk then
            Log("Melee M1 via source combat remotes: " .. melee.Name)
            return melee.Name, nil, attackMode
        end
    end

    -- Input M1 vẫn cần đứng gần. Chốt này đặt sau remote/equip để điểm an toàn
    -- cố định không chặn hoàn toàn việc chuyển sang Melee như trước.
    local inputRange = math.max(tonumber(CFG.AttackRange) or 30, 1)
    if coreDistance > inputRange then
        return nil, string.format(
            "Remote lỗi và Core ngoài tầm M1 (%.0fm)",
            coreDistance
        )
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
local function TriggerFruitPickup(handle, hrp)
    if not handle or not handle.Parent or not hrp or not hrp.Parent then
        return false, "Fruit/Character không còn sẵn sàng"
    end

    -- Main loop có thể vào PickupDist trước Heartbeat cuối cùng. Phải
    -- thả PlatformStand, BodyVelocity và noclip trước khi kích hoạt touch.
    CancelMove(true)

    local humanoid = GetHumanoid()
    if not humanoid or humanoid.Health <= 0 then
        return false, "Humanoid chưa sẵn sàng"
    end

    pcall(function()
        humanoid.Sit = false
        humanoid.PlatformStand = false

        -- Một số spawn bị chôn lệch trong terrain. Đặt root hơi phía
        -- trên Handle để chân nhân vật cắt qua Fruit thay vì bị đẩy ngang.
        local pickupHeight = math.max((handle.Size.Y * 0.5) + 1.5, 2.5)
        hrp.CFrame = CFrame.new(
            handle.Position + Vector3.new(0, pickupHeight, 0)
        ) * hrp.CFrame.Rotation
        StopRootVelocity(hrp)
    end)

    -- Kích hoạt TouchInterest trực tiếp nếu executor hỗ trợ, không
    -- phụ thuộc terrain hoặc nút nhảy trên mobile.
    pcall(function()
        if type(firetouchinterest) == "function" then
            firetouchinterest(hrp, handle, 0)
            task.wait(0.05)
            firetouchinterest(hrp, handle, 1)
        end
    end)

    -- Fallback cho executor không hỗ trợ firetouchinterest.
    local inputOk, inputError = pcall(function()
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    if not inputOk then
        pcall(function()
            VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
        return false, "Kích hoạt nhặt Fruit lỗi: " .. tostring(inputError)
    end

    return true
end

local function PickupFruit(fruit)
    if not fruit then return false, "Fruit không tồn tại" end
    local handle = fruit:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return false, "Fruit thiếu Handle" end
    if not handle.Parent then return false, "Fruit đã biến mất" end

    local hrp = GetHRP()
    if not hrp then return false, "Character chưa sẵn sàng" end

    local dist = (hrp.Position - handle.Position).Magnitude

    if dist <= CFG.PickupDist then
        -- Không cho Tool đang random/lưu bị nhận nhầm là Fruit vừa nhặt ngoài map.
        if randomPurchaseInProgress or storeInProgress then
            return false, "Fruit đang được xử lý"
        end
        worldFruitPickupInProgress = true
        local fruitSnapshot = SnapshotOwnedFruitTools()

        local triggered, triggerError = TriggerFruitPickup(handle, hrp)
        if not triggered then
            worldFruitPickupInProgress = false
            return false, triggerError
        end

        local newOwnedFruit = WaitForNewOwnedFruit(fruitSnapshot, 2)
        -- Object ngoài map biến mất có thể do người khác nhặt/despawn.
        -- Chỉ xác nhận khi chính inventory của người chơi có Tool Fruit mới.
        local picked = newOwnedFruit ~= nil
        -- Chờ ngắn nếu Tool mới chỉ mang tên chung "Fruit"; ưu tiên tên hiển
        -- thị trực tiếp để không lặp lại lỗi lấy nhầm khóa Storage làm tên trái.
        local pickedFruitName = picked
            and WaitForResolvedFruitDisplayName(newOwnedFruit, 0.8) or nil
        worldFruitPickupInProgress = false
        Log(picked and "Pickup fruit thành công" or "Đã bấm Space nhưng chưa nhặt được fruit")
        return picked, picked and "Picked" or "Chưa nhặt được", pickedFruitName
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
local storeRetryAt = setmetatable({}, { __mode = "k" })
local storeRejectedItems = setmetatable({}, { __mode = "k" })
local STORE_REJECTED_ATTRIBUTE = "AutoFactoryStoreRejected"

local function IsStoreRejected(item)
    if not item then return false end
    if storeRejectedItems[item] then return true end

    local ok, rejected = pcall(function()
        return item:GetAttribute(STORE_REJECTED_ATTRIBUTE) == true
    end)
    return ok and rejected
end

local function RejectFruitStore(item)
    if not item then return end
    storeRejectedItems[item] = true
    storeRetryAt[item] = nil
    pcall(function()
        item:SetAttribute(STORE_REJECTED_ATTRIBUTE, true)
    end)
end

local function IsStoreDeferred(item)
    return item ~= nil and (storeRetryAt[item] or 0) > tick()
end

local function DeferFruitStore(item)
    if not item then return end
    storeRetryAt[item] = tick() + math.max(tonumber(CFG.StoreRetryDelay) or 15, 1)
end

local function CountFruitInBackpack()
    local count, deferred, rejected = 0, 0, 0
    local char  = GetChar()
    local bp    = lp:FindFirstChild("Backpack")

    local function checkContainer(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            local ok, isFruit = pcall(IsFruitTool, item)
            if ok and isFruit then
                if IsStoreRejected(item) then
                    rejected = rejected + 1
                elseif IsStoreDeferred(item) then
                    deferred = deferred + 1
                else
                    count = count + 1
                end
            end
        end
    end

    checkContainer(bp)
    if char then checkContainer(char) end
    return count, deferred, rejected
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
    local originalName = GetFruitOriginalName(item)
    if originalName then
        return originalName
    end

    local displayName = NormalizeFruitDisplayName(item.Name)
    if not displayName then return nil end
    local baseName = string.gsub(displayName, "%s+[Ff][Rr][Uu][Ii][Tt]$", "")
    if baseName == "" then return nil end
    return baseName .. "-" .. baseName
end

local function StoreFruitInBackpack(bypassCooldown)
    -- Chặn các lượt quét chồng nhau để không gửi StoreFruit hai lần cho cùng Tool.
    if storeInProgress then
        return 0, 0, 0, "busy", 0
    end

    -- Cooldown để không spam
    local cooldown = math.max(tonumber(CFG.StoreCooldown) or 3, 0)
    if not bypassCooldown and (tick() - lastStoreTime) < cooldown then
        return 0, 0, 0, "cooldown", 0
    end

    local char = GetChar()
    local bp   = lp:FindFirstChild("Backpack")

    local commF = ReplicatedStorage:FindFirstChild("Remotes")
    if commF then commF = commF:FindFirstChild("CommF_") end
    if not commF then
        Log("StoreFruit: CommF_ not found!")
        return 0, 0, 0, "Không tìm thấy CommF_", 0
    end

    local stored = 0
    local attempted = 0
    local deferred = 0
    local rejected = 0
    storeInProgress = true
    lastStoreTime = tick()

    local function storeFrom(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            local checkOk, isFruit = pcall(IsFruitTool, item)
            if checkOk and isFruit then
                local metadataOk, itemName, storageName = pcall(function()
                    local resolvedStorageName = GetFruitStorageName(item)
                    local resolvedDisplayName = ResolveFruitDisplayName(item)
                    return resolvedDisplayName or tostring(item.Name), resolvedStorageName
                end)
                if not metadataOk then
                    Log("Đọc metadata Fruit lỗi: " .. tostring(itemName))
                    continue
                end
                if not storageName then
                    DeferFruitStore(item)
                    deferred = deferred + 1
                    Log("Defer StoreFruit: chưa có OriginalName cho " .. itemName)
                    continue
                end

                if IsStoreRejected(item) then
                    rejected = rejected + 1
                    Log("Skip StoreFruit (server đã từ chối): " .. itemName)
                    continue
                elseif IsStoreDeferred(item) then
                    deferred = deferred + 1
                    Log("Defer StoreFruit (đang chờ retry): " .. itemName)
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
                    SendFruitWebhook("Stored", itemName)
                elseif ok then
                    -- Remote đã xử lý nhưng Tool vẫn còn: kho đầy/đủ giới hạn
                    -- hoặc server từ chối. Ghi nhớ để không spam lại Fruit này.
                    RejectFruitStore(item)
                    rejected = rejected + 1
                    Log("StoreFruit rejected, skip permanently: "
                        .. itemName .. " | " .. tostring(result))
                else
                    -- Lỗi gọi remote có thể chỉ là lỗi executor/mạng tạm thời.
                    DeferFruitStore(item)
                    deferred = deferred + 1
                    Log("StoreFruit failed: " .. itemName .. " | " .. tostring(result))
                end
            end
        end
    end

    local runOk, runError = xpcall(function()
        storeFrom(bp)
        if char then storeFrom(char) end
    end, function(err)
        return tostring(err)
    end)
    storeInProgress = false

    if not runOk then
        Log("StoreFruit loop lỗi: " .. tostring(runError))
        return stored, attempted, deferred, runError, rejected
    end

    Log(string.format(
        "Stored %d/%d fruit(s), deferred %d, rejected %d",
        stored, attempted, deferred, rejected
    ))
    return stored, attempted, deferred, nil, rejected
end

-- ─────────────────────────────────────────────
-- REMOTE RANDOM DEVIL FRUIT
-- Cơ chế lấy trực tiếp từ remote_random_fruit.lua:
--   BannerClient -> BoxName -> Cousin/Check -> CheckTime -> Cousin/BoxName
-- Không teleport và không phụ thuộc NPC/Spinner GUI.
-- ─────────────────────────────────────────────
local bannerClient = nil
local function GetCommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CommF_") or nil
end

local function GetActiveRandomFruitBoxName()
    if not bannerClient then
        local controllers = ReplicatedStorage:FindFirstChild("Controllers")
        local module = controllers and controllers:FindFirstChild("BannerClient")
        if module then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table" then
                bannerClient = result
            else
                Log("Load BannerClient lỗi: " .. tostring(result))
            end
        end
    end

    if bannerClient
        and type(bannerClient.TryGetBannerItemIfActiveAsync) == "function" then
        local ok, data = pcall(bannerClient.TryGetBannerItemIfActiveAsync)
        if ok and type(data) == "table"
            and type(data.BoxName) == "string" and data.BoxName ~= "" then
            return data.BoxName
        end
        if not ok then Log("Đọc banner lỗi: " .. tostring(data)) end
    end

    return "DLCBoxData"
end

-- Remote Cousin có thể trả thông báo lỗi/cooldown dưới dạng chuỗi. Trong Lua,
-- chuỗi luôn là truthy nên không được dùng `if result then` để kết luận đã mua.
local function ClassifyRandomFruitResponse(value)
    if value == nil or value == false then return "Empty" end
    if type(value) ~= "string" then return "Bought" end

    local message = string.lower(value)
    if string.find(message, "must wait", 1, true)
        or string.find(message, "buy another random fruit", 1, true)
        or string.find(message, "cooldown", 1, true)
        or string.find(message, "come back later", 1, true) then
        return "Cooldown"
    end

    if string.find(message, "not enough", 1, true)
        or string.find(message, "need more", 1, true)
        or string.find(message, "low level", 1, true)
        or string.find(message, "cannot buy", 1, true)
        or string.find(message, "can't buy", 1, true)
        or string.find(message, "failed", 1, true)
        or string.find(message, "error", 1, true) then
        return "BuyRejected"
    end

    return "Bought"
end

local function RandomFruit()
    local commF = GetCommF()
    if not commF then return false, "RemoteError", "Không tìm thấy CommF_" end

    local boxName = GetActiveRandomFruitBoxName()
    Log("Remote Random kiểm tra Box: " .. boxName)

    -- Logic Random Fruit cũ: chỉ chặn khi server trả rõ level thấp/cooldown false.
    local currentSpins, playerLevel, maxSpins = nil, nil, nil
    pcall(function()
        currentSpins, playerLevel, maxSpins = commF:InvokeServer(
            "Cousin", "Check", boxName
        )
    end)

    if playerLevel and playerLevel < 50 then
        return false, "Low Level", playerLevel
    end

    local timeOk, isReady = pcall(function()
        return commF:InvokeServer("Cousin", "CheckTime", boxName)
    end)
    if not timeOk then
        return false, "RemoteError", tostring(isReady)
    end
    if isReady == false or ClassifyRandomFruitResponse(isReady) == "Cooldown" then
        return false, "Cooldown", isReady
    end

    if worldFruitPickupInProgress or storeInProgress then
        return false, "Busy", "Đang nhặt/lưu Fruit"
    end

    randomPurchaseInProgress = true
    local fruitSnapshot = SnapshotOwnedFruitTools()

    local transactionOk, outcome = xpcall(function()
        local result = commF:InvokeServer("Cousin", boxName)
        local responseStatus = ClassifyRandomFruitResponse(result)

        if responseStatus == "Cooldown" then
            return { status = "Cooldown", detail = result }
        elseif responseStatus == "BuyRejected" then
            return { status = "BuyRejected", detail = result }
        end

        -- Fallback cũ dành cho server/executor không nhận boxName.
        if result == nil or result == false then
            result = commF:InvokeServer("Cousin")
            responseStatus = ClassifyRandomFruitResponse(result)
            if responseStatus == "Cooldown" then
                return { status = "Cooldown", detail = result }
            elseif responseStatus == "BuyRejected" then
                return { status = "BuyRejected", detail = result }
            end
        end

        -- Chỉ xác nhận thành công khi thật sự có một Tool Fruit mới xuất hiện.
        local newFruit = WaitForNewOwnedFruit(fruitSnapshot, 3)
        if not newFruit then
            return { status = "BuyUnconfirmed", detail = result }
        end

        return {
            status = "Bought",
            fruit = newFruit,
            fruitName = WaitForResolvedFruitDisplayName(newFruit, 0.8),
            detail = result,
        }
    end, function(err)
        return tostring(err)
    end)

    randomPurchaseInProgress = false

    if not transactionOk then
        return false, "RemoteError", tostring(outcome)
    end
    if outcome.status ~= "Bought" then
        return false, outcome.status, outcome.detail
    end

    if outcome.fruitName then
        Log("Remote Random Fruit xác nhận nhận được: " .. outcome.fruitName)
        SendFruitWebhook("Random", outcome.fruitName)
    else
        Log("Bỏ qua webhook Random vì không xác định được tên Fruit")
    end
    StoreFruitInBackpack(true)
    return true, "Bought", outcome.fruitName
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

local function AddCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
    return corner
end

local function AddStroke(instance, color, thickness, transparency)
    local border = Instance.new("UIStroke")
    border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    border.Color = color
    border.Thickness = thickness or 1
    border.Transparency = transparency or 0
    border.Parent = instance
    return border
end

local function MakeText(parent, name, position, size, text, color, font, textSize, alignment)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Position = position
    label.Size = size
    label.BackgroundTransparency = 1
    label.Text = text or ""
    label.TextColor3 = color or Color3.fromRGB(235, 240, 248)
    label.Font = font or Enum.Font.Gotham
    label.TextSize = textSize or 13
    label.TextXAlignment = alignment or Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = parent
    return label
end

-- Panel mới theo mockup đã duyệt.
local expandedSize = UDim2.fromOffset(420, 346)
local minimizedSize = UDim2.fromOffset(420, 48)
local frame = Instance.new("Frame")
frame.Name = "Main"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Size = expandedSize
frame.Position = UDim2.new(0.5, 0, 0, 10)
frame.BackgroundColor3 = Color3.fromRGB(8, 12, 20)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = sg
AddCorner(frame, 14)
AddStroke(frame, Color3.fromRGB(56, 215, 255), 1.6, 0.08)

-- Tự co để panel không tràn màn hình mobile.
local uiScale = Instance.new("UIScale")
uiScale.Parent = frame
local function UpdateGuiScale()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    uiScale.Scale = math.min(
        1,
        math.max((viewport.X - 20) / expandedSize.X.Offset, 0.65),
        math.max((viewport.Y - 20) / expandedSize.Y.Offset, 0.65)
    )
end
UpdateGuiScale()
if workspace.CurrentCamera then
    TrackConnection(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), UpdateGuiScale)
end

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = Color3.fromRGB(10, 15, 24)
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame

MakeText(
    header, "FactoryIcon", UDim2.fromOffset(10, 4), UDim2.fromOffset(34, 36),
    "🏭", Color3.fromRGB(56, 215, 255), Enum.Font.GothamBold, 23,
    Enum.TextXAlignment.Center
)
local title = MakeText(
    header, "Title", UDim2.fromOffset(47, 11), UDim2.fromOffset(135, 26),
    "AUTO FACTORY", Color3.fromRGB(245, 247, 250), Enum.Font.GothamBold, 17
)
local lblMode = MakeText(
    header, "Mode", UDim2.fromOffset(48, 26), UDim2.fromOffset(142, 17),
    "Khởi động...", Color3.fromRGB(56, 215, 255), Enum.Font.Gotham, 9
)
lblMode.Visible = false

local seaBadge = Instance.new("Frame")
seaBadge.Size = UDim2.fromOffset(112, 28)
seaBadge.Position = UDim2.fromOffset(184, 10)
seaBadge.BackgroundColor3 = Color3.fromRGB(14, 21, 31)
seaBadge.BorderSizePixel = 0
seaBadge.Parent = header
AddCorner(seaBadge, 14)
AddStroke(seaBadge, Color3.fromRGB(57, 72, 90), 1, 0.15)
MakeText(
    seaBadge, "SeaStatus", UDim2.fromOffset(7, 0), UDim2.new(1, -14, 1, 0),
    "●  SEA 2 • ONLINE", Color3.fromRGB(73, 230, 139), Enum.Font.GothamBold, 11,
    Enum.TextXAlignment.Center
)

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name = "Minimize"
minimizeBtn.Size = UDim2.fromOffset(32, 32)
minimizeBtn.Position = UDim2.fromOffset(302, 8)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(23, 30, 42)
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = Color3.fromRGB(230, 235, 242)
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 18
minimizeBtn.Parent = header
AddCorner(minimizeBtn, 8)
AddStroke(minimizeBtn, Color3.fromRGB(55, 66, 82), 1, 0.2)

local stopBtn = Instance.new("TextButton")
stopBtn.Name = "Stop"
stopBtn.Size = UDim2.fromOffset(76, 32)
stopBtn.Position = UDim2.fromOffset(338, 8)
stopBtn.BackgroundColor3 = Color3.fromRGB(213, 52, 57)
stopBtn.BorderSizePixel = 0
stopBtn.Text = "■  STOP"
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 12
stopBtn.Parent = header
AddCorner(stopBtn, 8)
AddStroke(stopBtn, Color3.fromRGB(255, 90, 96), 1, 0.05)

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.fromOffset(0, 48)
body.Size = UDim2.new(1, 0, 1, -48)
body.BackgroundTransparency = 1
body.Parent = frame

-- Account card
local accountCard = Instance.new("Frame")
accountCard.Name = "AccountCard"
accountCard.Position = UDim2.fromOffset(8, 8)
accountCard.Size = UDim2.new(1, -16, 0, 62)
accountCard.BackgroundColor3 = Color3.fromRGB(12, 18, 28)
accountCard.BorderSizePixel = 0
accountCard.Parent = body
AddCorner(accountCard, 10)
AddStroke(accountCard, Color3.fromRGB(44, 56, 72), 1, 0.2)
MakeText(
    accountCard, "UserIcon", UDim2.fromOffset(10, 7), UDim2.fromOffset(44, 48),
    "👤", Color3.fromRGB(56, 215, 255), Enum.Font.GothamBold, 27,
    Enum.TextXAlignment.Center
)
MakeText(
    accountCard, "AccountLabel", UDim2.fromOffset(62, 8), UDim2.fromOffset(170, 17),
    "ACCOUNT", Color3.fromRGB(56, 215, 255), Enum.Font.GothamBold, 10
)
MakeText(
    accountCard, "Username", UDim2.fromOffset(62, 24), UDim2.new(1, -190, 0, 29),
    tostring(lp.Name), Color3.fromRGB(242, 245, 249), Enum.Font.GothamBold, 16
)
MakeText(
    accountCard, "Running", UDim2.new(1, -118, 0, 0), UDim2.fromOffset(106, 62),
    "●  RUNNING", Color3.fromRGB(73, 230, 139), Enum.Font.GothamBold, 11,
    Enum.TextXAlignment.Right
)

local function MakeStatusRow(y, icon, labelText, accentColor)
    local row = Instance.new("Frame")
    row.Position = UDim2.fromOffset(10, y)
    row.Size = UDim2.new(1, -20, 0, 40)
    row.BackgroundColor3 = Color3.fromRGB(14, 20, 30)
    row.BorderSizePixel = 0
    row.Parent = body
    AddCorner(row, 8)
    AddStroke(row, Color3.fromRGB(41, 52, 66), 1, 0.2)

    local iconBox = Instance.new("Frame")
    iconBox.Size = UDim2.fromOffset(42, 40)
    iconBox.BackgroundColor3 = Color3.fromRGB(18, 26, 38)
    iconBox.BorderSizePixel = 0
    iconBox.Parent = row
    AddCorner(iconBox, 8)
    MakeText(
        iconBox, "Icon", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
        icon, accentColor, Enum.Font.GothamBold, 20, Enum.TextXAlignment.Center
    )

    MakeText(
        row, "Label", UDim2.fromOffset(54, 0), UDim2.fromOffset(135, 40),
        labelText, Color3.fromRGB(238, 241, 246), Enum.Font.GothamBold, 13
    )
    local value = MakeText(
        row, "Value", UDim2.fromOffset(190, 0), UDim2.new(1, -204, 1, 0),
        "", accentColor, Enum.Font.GothamBold, 12, Enum.TextXAlignment.Right
    )

    local accent = Instance.new("Frame")
    accent.Size = UDim2.fromOffset(3, 30)
    accent.Position = UDim2.new(1, -5, 0.5, -15)
    accent.BackgroundColor3 = accentColor
    accent.BorderSizePixel = 0
    accent.Parent = row
    AddCorner(accent, 2)
    return value
end

local lblBoss = MakeStatusRow(76, "⚙", "CORE", Color3.fromRGB(56, 215, 255))
local lblFruit = MakeStatusRow(122, "◉", "FRUIT SCANNER", Color3.fromRGB(73, 230, 139))
local lblRandom = MakeStatusRow(168, "🎲", "RANDOM FRUIT", Color3.fromRGB(197, 124, 255))
local lblStore = MakeStatusRow(214, "◆", "STORAGE", Color3.fromRGB(255, 191, 60))

local footer = Instance.new("Frame")
footer.Position = UDim2.fromOffset(0, 258)
footer.Size = UDim2.new(1, 0, 0, 38)
footer.BackgroundTransparency = 1
footer.Parent = body

local function MakeChip(x, width, textValue, color)
    local chip = Instance.new("Frame")
    chip.Position = UDim2.fromOffset(x, 4)
    chip.Size = UDim2.fromOffset(width, 30)
    chip.BackgroundColor3 = Color3.fromRGB(11, 17, 26)
    chip.BorderSizePixel = 0
    chip.Parent = footer
    AddCorner(chip, 15)
    AddStroke(chip, color, 1, 0.05)
    MakeText(
        chip, "Text", UDim2.fromOffset(8, 0), UDim2.new(1, -16, 1, 0),
        textValue, Color3.fromRGB(235, 239, 245), Enum.Font.GothamBold, 11,
        Enum.TextXAlignment.Center
    )
    return chip
end

MakeChip(
    42, 156,
    CFG.AutoBuso and "⚡  AUTO BUSO   ON" or "⚡  AUTO BUSO   OFF",
    Color3.fromRGB(255, 191, 60)
)
local webhookUrlForUi = GetConfiguredWebhookURL()
local webhookOnForUi = CFG.WebhookEnabled
    and string.find(webhookUrlForUi, "http", 1, true) ~= nil
MakeChip(
    222, 156,
    webhookOnForUi and "⌘  WEBHOOK   ON" or "⌘  WEBHOOK   OFF",
    Color3.fromRGB(56, 215, 255)
)

lblBoss.Text = "Đang chờ spawn"
lblFruit.Text = "Đang quét bản đồ"
lblStore.Text = "Sẵn sàng"
lblRandom.Text = CFG.AutoRandomFruit and "Khởi động..." or "Đã tắt"

local minimized = false
TrackConnection(minimizeBtn.Activated, function()
    minimized = not minimized
    body.Visible = not minimized
    frame.Size = minimized and minimizedSize or expandedSize
    minimizeBtn.Text = minimized and "+" or "−"
end)

TrackConnection(stopBtn.MouseEnter, function()
    stopBtn.BackgroundColor3 = Color3.fromRGB(235, 66, 72)
end)
TrackConnection(stopBtn.MouseLeave, function()
    stopBtn.BackgroundColor3 = Color3.fromRGB(213, 52, 57)
end)
TrackConnection(stopBtn.Activated, function()
    globalEnv.AutoFactory = false
end)

-- Drag GUI bằng chuột lẫn touch (Delta/mobile).
local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
TrackConnection(header.InputBegan, function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragInput = inp.UserInputType == Enum.UserInputType.Touch and inp or nil
        dragStart = inp.Position
        startPos  = frame.Position
    end
end)
TrackConnection(header.InputChanged, function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then
        dragInput = inp
    end
end)
TrackConnection(UserInputService.InputChanged, function(inp)
    if dragging and inp == dragInput then
        local d = inp.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)
TrackConnection(UserInputService.InputEnded, function(inp)
    if inp == dragInput or inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        dragInput = nil
    end
end)

-- Auto Store chạy độc lập để InvokeServer/task.wait không chặn việc phát hiện Core.
-- Khi Core đang sống, lượt lưu mới sẽ chờ để giữ đúng thứ tự ưu tiên combat.
task.spawn(function()
    while globalEnv.AutoFactory
        and globalEnv.AutoFactoryRunToken == runToken
        and sg.Parent do
        task.wait(0.5)
        if not globalEnv.AutoFactory
            or globalEnv.AutoFactoryRunToken ~= runToken
            or not sg.Parent then
            break
        end

        if not CFG.AutoStore then
            lblStore.Text = "Đã tắt"
            continue
        end

        if randomPurchaseInProgress or worldFruitPickupInProgress then
            lblStore.Text = "Chờ xác nhận Fruit mới..."
            continue
        end

        local core = FindCore()
        if core and IsMobAlive(core) then
            lblStore.Text = "Tạm dừng • đang đánh Core"
            continue
        end

        local count, deferred, rejected = CountFruitInBackpack()
        if count <= 0 then
            if deferred > 0 and rejected > 0 then
                lblStore.Text = string.format(
                    "⏳ Retry %d | ⏭️ Bỏ qua %d", deferred, rejected
                )
            elseif deferred > 0 then
                lblStore.Text = string.format("⏳ Chờ retry %d Fruit", deferred)
            elseif rejected > 0 then
                lblStore.Text = string.format("⏭️ Bỏ qua %d Fruit không thể lưu", rejected)
            else
                lblStore.Text = "Sẵn sàng"
            end
            continue
        end

        local stored, attempted, retrying, storeError, rejectedNow = StoreFruitInBackpack()
        if storeError == "cooldown" or storeError == "busy" then
            lblStore.Text = string.format("Chờ lưu: %d Fruit", count)
        elseif stored > 0 and rejectedNow > 0 then
            lblStore.Text = string.format("✅ Lưu %d | ⏭️ Bỏ qua %d", stored, rejectedNow)
        elseif rejectedNow > 0 then
            lblStore.Text = string.format("⏭️ Bỏ qua %d Fruit không thể lưu", rejectedNow)
        elseif stored > 0 and retrying > 0 then
            lblStore.Text = string.format("✅ Lưu %d | ⏳ Retry %d", stored, retrying)
        elseif retrying > 0 then
            lblStore.Text = string.format("⏳ Chờ retry %d Fruit", retrying)
        elseif attempted > 0 and stored == attempted then
            lblStore.Text = string.format("✅ Đã lưu %d Fruit", stored)
        elseif attempted > 0 then
            lblStore.Text = string.format("⚠️ Đã lưu %d/%d Fruit", stored, attempted)
        else
            lblStore.Text = "⚠️ " .. tostring(storeError or "Không lưu được Fruit")
        end
    end
end)

-- Remote Random Fruit chạy riêng để InvokeServer không làm chậm vòng ưu tiên Core.
task.spawn(function()
    local retryAt = 0
    while globalEnv.AutoFactory
        and globalEnv.AutoFactoryRunToken == runToken
        and sg.Parent do
        task.wait(math.max(tonumber(CFG.RandomFruitInterval) or 0.5, 0.2))
        if not globalEnv.AutoFactory
            or globalEnv.AutoFactoryRunToken ~= runToken
            or not sg.Parent then
            break
        end

        if CFG.AutoRandomFruit then
            if tick() < retryAt then continue end
            local callOk, bought, status, detail = pcall(RandomFruit)
            if not callOk then
                lblRandom.Text = "Lỗi: " .. tostring(bought)
                retryAt = tick() + 3
            elseif bought then
                lblRandom.Text = "Thành công"
                retryAt = 0
            elseif status == "Low Level" then
                lblRandom.Text = "Cần cấp 50"
                retryAt = tick() + 30
            elseif status == "Cooldown" then
                lblRandom.Text = "Đang chờ cooldown"
                retryAt = tick() + math.max(
                    tonumber(CFG.RandomCooldownCheckDelay) or 30,
                    1
                )
            elseif status == "BuyRejected" then
                lblRandom.Text = "Server từ chối"
                retryAt = tick() + 5
            elseif status == "BuyUnconfirmed" then
                lblRandom.Text = "Không thấy Fruit mới"
                retryAt = tick() + 5
            elseif status == "RemoteError" then
                lblRandom.Text = tostring(detail)
                retryAt = tick() + 3
            else
                lblRandom.Text = tostring(status or "Không thực hiện được")
                retryAt = tick() + 3
            end
        else
            retryAt = 0
            lblRandom.Text = "Đã tắt"
        end
    end
end)

-- ─────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────
print(string.format(
    "[AutoFactory] Đã bắt đầu! Core Melee-only; tốc độ di chuyển %d; Auto Buso; Auto Random Fruit.",
    math.max(tonumber(CFG.MoveSpeed) or 300, 1)
))

task.spawn(function()
    local ok, runError = xpcall(function()
        local waitTick  = 0
        local fruitMode = false
        local coreWasAlive = false
        local factoryDelayUntil = 0

        while globalEnv.AutoFactory
            and globalEnv.AutoFactoryRunToken == runToken
            and sg.Parent do
            task.wait(CFG.LoopDelay)
            if not globalEnv.AutoFactory
                or globalEnv.AutoFactoryRunToken ~= runToken
                or not sg.Parent then
                break
            end

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
            coreWasAlive = true
            factoryDelayUntil = 0

            local bossHRP = core:FindFirstChild("HumanoidRootPart")
            local bossHumanoid = core:FindFirstChild("Humanoid")
            if not bossHRP or not bossHumanoid or bossHumanoid.Health <= 0 then
                continue
            end

            local hp    = math.floor(bossHumanoid.Health)
            local maxHp = math.floor(bossHumanoid.MaxHealth)
            local pct   = math.floor(hp / math.max(maxHp, 1) * 100)
            local exactDist = DistTo(bossHRP.Position)
            local dist  = math.floor(exactDist)

            lblBoss.Text = string.format(
                "%d/%d HP • %d%% • %dm",
                hp, maxHp, pct, dist
            )

            -- Ưu tiên điểm vừa lưu trong phiên; nếu không có thì dùng điểm an
            -- toàn đã hard-code. Core + 20Y chỉ còn là fallback cuối.
            local coreOffsetY = tonumber(CFG.CoreOffsetY) or 20
            local savedSafePosition = globalEnv.FactorySafePosition
            local configuredSafePosition = CFG.FactorySafePosition
            local coreTargetPosition
            if typeof(savedSafePosition) == "Vector3" then
                coreTargetPosition = savedSafePosition
            elseif typeof(configuredSafePosition) == "Vector3" then
                coreTargetPosition = configuredSafePosition
            else
                coreTargetPosition = bossHRP.Position + Vector3.new(0, coreOffsetY, 0)
            end

            -- Ưu tiên route nhanh khi đang ở rất xa. Sau Entrance, vòng kế
            -- tiếp sẽ dùng cùng ToTarget/MoveSpeed để bay nốt tới điểm Factory.
            local entranceUsed = TryFactoryEntrance(coreTargetPosition)
            if entranceUsed then
                lblMode.Text = "🌀 Entrance Mansion → Factory"
                continue
            end

            local coreTargetRotation = hrp.CFrame.Rotation
            if moveState.purpose == "Core" and moveState.target then
                coreTargetRotation = moveState.target.Rotation
            end
            local coreTargetCF = CFrame.new(coreTargetPosition) * coreTargetRotation
            local targetDistance = (hrp.Position - coreTargetPosition).Magnitude
            local coreSnapDistance = math.max(tonumber(CFG.CoreSnapDistance) or 4, 1)
            local holdTolerance = math.max(
                tonumber(CFG.CoreHoldTolerance) or 6,
                coreSnapDistance
            )
            local repositionDistance = moveState.purpose == "CoreHold"
                and holdTolerance or coreSnapDistance

            if targetDistance > repositionDistance then
                local moved, moveStatus = ToTarget(
                    coreTargetCF,
                    false,
                    "Core"
                )
                if not moved then
                    lblMode.Text = "⚠️ " .. tostring(moveStatus or "Không thể tới Core")
                    continue
                end
                SizePart(core)
                lblMode.Text = string.format("✈️ Đang tới Core | %dm", dist)
                continue
            end

            -- Đã vào tầm đánh: CoreHold triệt vận tốc và chỉ khóa trả về điểm
            -- đánh khi hitbox Core đẩy lệch quá tolerance.
            local holding, holdError = BeginCoreHold(coreTargetCF)
            if not holding then
                lblMode.Text = "⚠️ " .. tostring(holdError or "Không thể giữ vị trí đánh")
                continue
            end
            SizePart(core)

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
        -- PHẦN 2: TÌM FRUIT (chỉ khi không có Core)
        -- Auto Store chạy ở task riêng để không giữ vòng quét Core.
        -- ══════════════════════════════════════
        if moveState.purpose == "Core" or moveState.purpose == "CoreHold" then
            CancelMove(true)
        end

        -- Chỉ bắt đầu delay khi Core vừa chuyển từ còn sống sang biến mất/chết.
        -- Vòng lặp vẫn kiểm tra Core trước nhánh này nên boss mới luôn được ưu tiên.
        if coreWasAlive then
            coreWasAlive = false
            factoryDelayUntil = tick() + math.max(
                tonumber(CFG.FactoryFinishDelay) or 5,
                0
            )
        end

        local factoryDelayRemaining = factoryDelayUntil - tick()
        if factoryDelayRemaining > 0 then
            lblBoss.Text = string.format(
                "Hoàn tất • chờ %ds",
                math.max(math.ceil(factoryDelayRemaining), 1)
            )
            lblFruit.Text = "Tạm chờ sau Factory"
            task.wait(0.1)
            continue
        elseif factoryDelayUntil > 0 then
            factoryDelayUntil = 0
        end

        -- Sau khi nhặt Fruit ngoài map, ưu tiên mang về Café. Core vẫn
        -- được xử lý trước nhánh này và có thể tạm ngắt hành trình.
        if cafeReturnPending then
            local cafePosition = CFG.CafePosition
            if typeof(cafePosition) ~= "Vector3" then
                cafeReturnPending = false
                cafeReturnFruitName = nil
                if moveState.purpose == "Cafe" then CancelMove(true) end
                lblMode.Text = "Café: Tọa độ không hợp lệ"
                Log("CafePosition không phải Vector3")
                continue
            end

            local cafeDistance = (hrp.Position - cafePosition).Magnitude
            local cafeArrivalDistance = math.max(
                tonumber(CFG.CafeArrivalDistance) or 10,
                1
            )

            if cafeDistance <= cafeArrivalDistance then
                if moveState.purpose == "Cafe" then CancelMove(true) end
                local returnedFruitName = cafeReturnFruitName
                cafeReturnPending = false
                cafeReturnFruitName = nil
                lblMode.Text = "Đã về Café"
                lblFruit.Text = returnedFruitName
                    and ("Về Café: " .. returnedFruitName)
                    or "Đã mang Fruit về Café"
                task.wait(0.5)
                continue
            end

            -- Không gọi requestEntrance cùng lúc remote Random/Store đang chạy.
            if randomPurchaseInProgress or storeInProgress then
                lblMode.Text = "Chờ xử lý Fruit trước khi về Café"
                continue
            end

            local entranceUsed = TryCafeEntrance(cafePosition)
            if entranceUsed then
                lblMode.Text = "Entrance Mansion → Café"
                lblFruit.Text = string.format("Về Café • %.0fm", cafeDistance)
                continue
            end

            local cafeRotation = hrp.CFrame.Rotation
            if moveState.purpose == "Cafe" and moveState.target then
                cafeRotation = moveState.target.Rotation
            end
            local cafeTargetCF = CFrame.new(cafePosition) * cafeRotation
            local moved, moveStatus = ToTarget(cafeTargetCF, true, "Cafe")
            if moved then
                lblMode.Text = "Đang về Café"
                lblFruit.Text = string.format("Về Café • %.0fm", cafeDistance)
            else
                lblMode.Text = "Không thể về Café: "
                    .. tostring(moveStatus or "Lỗi di chuyển")
            end
            continue
        elseif moveState.purpose == "Cafe" then
            CancelMove(true)
        end

        waitTick = waitTick + 1
        local dots = string.rep(".", (waitTick % 3) + 1)
        lblMode.Text = "Tìm Core" .. dots
        lblBoss.Text = "Đang chờ spawn"

        if CFG.FruitEnabled then
            local fruit, fruitDist = FindFruitInWorld()
            if fruit then
                fruitMode = true
                local fruitName = ResolveFruitDisplayName(fruit) or fruit.Name
                lblMode.Text  = "Đang nhặt Fruit..."
                lblFruit.Text = string.format("%s • %.0fm", fruitName, fruitDist)

                local picked, pickupStatus, pickedFruitName = PickupFruit(fruit)
                if picked then
                    local confirmedName = pickedFruitName
                    if confirmedName then
                        lblFruit.Text = "Đã nhặt: " .. confirmedName
                        SendFruitWebhook("Picked", confirmedName)
                    else
                        lblFruit.Text = "Đã nhặt Fruit (chưa xác định tên)"
                        Log("Bỏ qua webhook Picked vì chưa xác định được tên Fruit")
                    end
                    QueueCafeReturn(confirmedName)
                elseif pickupStatus == "Move" or pickupStatus == "Snap"
                    or pickupStatus == "Chưa nhặt được" then
                    lblFruit.Text = "Tiếp cận: " .. fruitName
                else
                    lblFruit.Text = tostring(pickupStatus or "Không nhặt được Fruit")
                end

                -- Lặp ngay để phát hiện Core vừa spawn và chuyển sang combat.
                continue
            end

            -- Fruit có thể despawn trong lúc đang bay. Nếu không hủy, Heartbeat
            -- vẫn kéo nhân vật tới CFrame cũ dù FindFruitInWorld đã trả nil.
            if moveState.purpose == "Fruit" then CancelMove(true) end
            if fruitMode then
                fruitMode = false
                lblFruit.Text = "Không thấy"
            else
                lblFruit.Text = "Đang quét bản đồ"
            end
        else
            if moveState.purpose == "Fruit" then CancelMove(true) end
            fruitMode = false
            lblFruit.Text = "Đã tắt"
        end

        task.wait(0.8)
        end
    end, function(err)
        return tostring(err)
    end)

    -- Nếu đây vẫn là run hiện tại, dừng tất cả task nền kể cả khi main bị lỗi
    -- hoặc GUI bị xóa. Cleanup của run cũ không được tắt một run mới.
    if globalEnv.AutoFactoryRunToken == runToken then
        globalEnv.AutoFactory = false
        globalEnv.AutoFactoryBusoEnabled = false
    end

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
