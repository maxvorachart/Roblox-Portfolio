local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local serverModuleScriptsFolder = ServerStorage:WaitForChild("ModuleScriptsFolder")
local worldsModule = require(serverModuleScriptsFolder:WaitForChild("WorldsModule"))
local robuxModule = require(serverModuleScriptsFolder:WaitForChild("RobuxModule"))
local dataModule = require(serverModuleScriptsFolder:WaitForChild("DataModule"))
local FunnelTracker = require(serverModuleScriptsFolder:WaitForChild("FunnelTrackerModule"))
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEventsFolder")
local spawnCapsuleEvent = remoteEventsFolder:WaitForChild("SpawnCapsuleEvent")
local collectCapsuleEvent = remoteEventsFolder:WaitForChild("CollectCapsuleEvent")
local removeCapsuleEvent = remoteEventsFolder:WaitForChild("RemoveCapsuleEvent")
local requestAutoCollectEvent = remoteEventsFolder:WaitForChild("RequestAutoCollectEvent")
local autoCollectUpdateEvent = remoteEventsFolder:WaitForChild("AutoCollectUpdateEvent")
local baseplatesFolder = workspace:WaitForChild("BaseplatesFolder")
local vipBaseplate = baseplatesFolder:WaitForChild("VIPBaseplate")
local playerSpawnedCapsule = {}
local autoCollectPlayers = {}
local playerTargetCapsule = {}
local playerLastPos = {}
local playerStuckCount = {}
local playerLastWorld = {}
local capsuleIndexId = 0
local collectionRadius = 5
local offset = 20
local autoCollectId = 1855733291
local vipPassId = 1856047353

local function getCapsuleType(worldId)
	local chances = worldsModule.getCapsuleChances(worldId)
	if not chances then return nil end

	local r = math.random()
	local totalChance = 0
	for _, info in pairs(chances) do
		totalChance += info.chance
	end

	local threshold = r * totalChance
	local cumulative = 0
	for typeName, info in pairs(chances) do
		cumulative += info.chance
		if threshold <= cumulative then
			return typeName
		end
	end
end

local function getRandomPos(baseplate)
	if not baseplate or not baseplate:IsA("BasePart") then return Vector3.new(0, 5, 0) end
	local size = baseplate.Size
	local limitX = (size.X / 2) - offset
	local limitZ = (size.Z / 2) - offset
	if limitX < 0 then limitX = 0 end
	if limitZ < 0 then limitZ = 0 end
	local x = math.random(-limitX, limitX)
	local z = math.random(-limitZ, limitZ)
	return (baseplate.CFrame * CFrame.new(x, (size.Y/2) + 2, z)).Position
end

local function collectCapsule(player, capsuleId)
	local userId = player.UserId
	local spawnedCapsules = playerSpawnedCapsule[userId]
	if not spawnedCapsules or not spawnedCapsules[capsuleId] then return end

	local capsuleData = spawnedCapsules[capsuleId]
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end

	local distance = (capsuleData.position - character.HumanoidRootPart.Position).Magnitude
	if distance > collectionRadius + 10 then return end

	local chances = worldsModule.getCapsuleChances(capsuleData.worldId)
	local typeInfo = chances and chances[capsuleData.capsuleType]

	if typeInfo then
		dataModule.addXp(player, typeInfo.value)
	end

	spawnedCapsules[capsuleId] = nil
	if playerTargetCapsule[userId] == capsuleId then
		playerTargetCapsule[userId] = nil
	end
	removeCapsuleEvent:FireClient(player, capsuleId)

	FunnelTracker.AdvanceFunnel(player, 3)
end

requestAutoCollectEvent.OnServerEvent:Connect(function(player, value)
	local userId = player.UserId
	if typeof(value) ~= "boolean" then return end
	local hasGamePass = robuxModule.hasGamePass(player, autoCollectId)
	if not hasGamePass then return end

	autoCollectPlayers[userId] = value
	if not value then
		playerTargetCapsule[userId] = nil
		playerStuckCount[userId] = 0
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if value then
		player.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
		player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

		FunnelTracker.AdvanceFunnel(player, 4)
	else
		player.DevComputerMovementMode = Enum.DevComputerMovementMode.UserChoice
		player.DevTouchMovementMode = Enum.DevTouchMovementMode.UserChoice
	end

	autoCollectUpdateEvent:FireClient(player, value)
end)

collectCapsuleEvent.OnServerEvent:Connect(function(player, capsuleId)
	if typeof(capsuleId) ~= "number" then return end
	collectCapsule(player, capsuleId)
end)

Players.PlayerAdded:Connect(function(player)
	playerSpawnedCapsule[player.UserId] = {}
	playerLastWorld[player.UserId] = nil
	playerStuckCount[player.UserId] = 0

	FunnelTracker.AdvanceFunnel(player, 1)
end)

Players.PlayerRemoving:Connect(function(player)
	playerSpawnedCapsule[player.UserId] = nil
	playerLastWorld[player.UserId] = nil
	autoCollectPlayers[player.UserId] = nil
	playerTargetCapsule[player.UserId] = nil
	playerLastPos[player.UserId] = nil
	playerStuckCount[player.UserId] = nil
end)

while true do
	task.wait(0.2)

	for userId, spawnedCapsules in pairs(playerSpawnedCapsule) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then continue end

		local currentWorldId = worldsModule.getPlayerWorld(player)
		local storedLastWorld = playerLastWorld[userId]

		if currentWorldId ~= storedLastWorld then
			for id, _ in pairs(spawnedCapsules) do
				removeCapsuleEvent:FireClient(player, id)
			end
			table.clear(spawnedCapsules)
			playerTargetCapsule[userId] = nil
			playerLastWorld[userId] = currentWorldId
			playerStuckCount[userId] = 0
		end

		local currentBaseplate = worldsModule.getBaseplate(player)
		if not currentBaseplate then continue end

		local isVip = robuxModule.hasGamePass(player, vipPassId)
		local currentMax = worldsModule.getAmount(currentWorldId)
		local vipMax = worldsModule.getAmount("5")

		local currentWorldCount = 0
		local vipWorldCount = 0

		for _, capData in pairs(spawnedCapsules) do
			if capData.worldId == "5" then
				vipWorldCount += 1
			elseif capData.worldId == currentWorldId then
				currentWorldCount += 1
			end
		end

		if currentWorldCount < currentMax then
			local capsuleType = getCapsuleType(currentWorldId)
			if capsuleType then
				capsuleIndexId += 1
				local capsuleData = {
					position = getRandomPos(currentBaseplate),
					capsuleType = capsuleType,
					worldId = currentWorldId 
				}
				spawnedCapsules[capsuleIndexId] = capsuleData
				spawnCapsuleEvent:FireClient(player, capsuleIndexId, capsuleData)

				FunnelTracker.AdvanceFunnel(player, 2)
			end
		end

		if isVip and currentWorldId ~= "5" then
			if vipWorldCount < vipMax then
				local capsuleType = getCapsuleType("5")
				if capsuleType then
					capsuleIndexId += 1
					local capsuleData = {
						position = getRandomPos(vipBaseplate),
						capsuleType = capsuleType,
						worldId = "5"
					}
					spawnedCapsules[capsuleIndexId] = capsuleData
					spawnCapsuleEvent:FireClient(player, capsuleIndexId, capsuleData)
				end
			end
		end

		if autoCollectPlayers[userId] and not player:GetAttribute("IsGliding") then
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")

			if humanoid and rootPart and humanoid.Health > 0 then

				local currentTargetId = playerTargetCapsule[userId]

				if currentTargetId and not spawnedCapsules[currentTargetId] then
					currentTargetId = nil
					playerTargetCapsule[userId] = nil
				end

				if not currentTargetId then
					local closestDist = math.huge
					local bestId = nil

					for id, capData in pairs(spawnedCapsules) do
						local dist = (capData.position - rootPart.Position).Magnitude
						if dist < closestDist then
							closestDist = dist
							bestId = id
						end
					end

					if bestId then
						playerTargetCapsule[userId] = bestId
						currentTargetId = bestId
					end
				end

				local currentPos = rootPart.Position
				local lastPos = playerLastPos[userId] or currentPos
				local movedDist = Vector2.new(currentPos.X - lastPos.X, currentPos.Z - lastPos.Z).Magnitude

				playerLastPos[userId] = currentPos

				local targetPos = currentTargetId and spawnedCapsules[currentTargetId].position

				if targetPos then
					local distToTarget = (targetPos - currentPos).Magnitude

					if distToTarget > 150 then
						rootPart.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
						playerStuckCount[userId] = 0
					else
						if movedDist < 0.8 then
							playerStuckCount[userId] = (playerStuckCount[userId] or 0) + 1
						else
							playerStuckCount[userId] = 0
						end

						local stuckTicks = playerStuckCount[userId] or 0

						if stuckTicks > 15 then
							spawnedCapsules[currentTargetId] = nil
							removeCapsuleEvent:FireClient(player, currentTargetId)
							playerTargetCapsule[userId] = nil
							playerStuckCount[userId] = 0
						elseif stuckTicks > 7 then
							humanoid.Jump = true
							local dir = (targetPos - currentPos).Unit
							local side = dir:Cross(Vector3.new(0, 1, 0))
							if math.random() > 0.5 then side = -side end
							humanoid:MoveTo(currentPos + (side * 8))
						elseif stuckTicks > 2 then
							humanoid.Jump = true
							humanoid:MoveTo(targetPos)
						else
							humanoid:MoveTo(targetPos)
						end
					end
				end
			end
		end
	end
end
