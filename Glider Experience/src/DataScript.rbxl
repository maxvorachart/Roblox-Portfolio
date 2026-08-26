local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local serverModuleScriptsFolder = ServerStorage:WaitForChild("ModuleScriptsFolder")
local inventoryModule = require(serverModuleScriptsFolder:WaitForChild("InventoryModule"))
local equippedModule = require(serverModuleScriptsFolder:WaitForChild("EquippedModule"))
local dataModule = require(serverModuleScriptsFolder:WaitForChild("DataModule"))
local worldsModule = require(serverModuleScriptsFolder:WaitForChild("WorldsModule"))

local playerData = DataStoreService:GetDataStore("PlayerData53")

local rebirthsOrderedDataStore = DataStoreService:GetOrderedDataStore("RebirthsLeaderboard")
local winsOrderedDataStore = DataStoreService:GetOrderedDataStore("WinsLeaderboard")
local speedsOrderedDataStore = DataStoreService:GetOrderedDataStore("SpeedsLeaderboard")
local timesOrderedDataStore = DataStoreService:GetOrderedDataStore("TimesLeaderboard")

local savingPlayers = {}

local function saveData(dataStore, key, data)
	for i = 1, 5 do
		local success = pcall(function()
			dataStore:UpdateAsync(key, function()
				return data
			end)
		end)
		if success then return true end
		task.wait(1)
	end
	return false
end

local function loadData(key)
	for i = 1, 5 do
		local success, data = pcall(function()
			return playerData:GetAsync(key)
		end)
		if success then return true, data end
		task.wait(1)
	end
	return false, nil
end

Players.PlayerAdded:Connect(function(player)
	local userId = player.UserId

	local timeWaited = 0
	while savingPlayers[userId] and timeWaited < 10 do
		task.wait(0.2)
		timeWaited += 0.2
	end

	local leaderstats = Instance.new("Folder", player)
	leaderstats.Name = "leaderstats"

	local wins = Instance.new("IntValue", leaderstats)
	local speed = Instance.new("IntValue", leaderstats)
	local rebirths = Instance.new("IntValue", leaderstats)

	wins.Name = "Wins"
	speed.Name = "Speed"
	rebirths.Name = "Rebirths"

	local success, data = loadData(userId)

	if not success then
		player:Kick("Data failed to load. Please rejoin.")
		return
	end

	wins.Value = data and data.wins or 0
	speed.Value = data and data.speed or 1
	rebirths.Value = data and data.rebirths or 0

	local extraData = data and data.extraData
	local inventory = data and data.inventory or nil
	local equipped = data and data.equipped or nil

	inventoryModule.addPlayer(player, inventory)
	equippedModule.addPlayer(player, equipped)
	dataModule.addPlayer(player, extraData)

	local character = player.Character or player.CharacterAdded:Wait()
	local savedWorldId = dataModule.getWorld(player) or "1"
	worldsModule.teleportPlayer(player, savedWorldId)

end)

local function playerSave(player)
	local userId = player.UserId

	if savingPlayers[userId] then return end
	savingPlayers[userId] = true

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		savingPlayers[userId] = nil
		return
	end

	local wins = leaderstats:FindFirstChild("Wins")
	local speed = leaderstats:FindFirstChild("Speed")
	local rebirths = leaderstats:FindFirstChild("Rebirths")

	if not wins or not speed or not rebirths then
		savingPlayers[userId] = nil
		return
	end

	local inventory = inventoryModule.getInventory(player)
	local equipped = equippedModule.getEquipped(player)
	local extraData = dataModule.getData(player)
	if not extraData or not inventory or not equipped then
		savingPlayers[userId] = nil
		return
	end

	local data = {
		wins = wins.Value,
		speed = speed.Value,
		rebirths = rebirths.Value,
		inventory = inventory,
		equipped = equipped,
		extraData = extraData,
	}
	saveData(playerData, userId, data)--CHANGE HERE TO SAVE DATA OR NOT

	inventoryModule.removePlayer(player)
	equippedModule.removePlayer(player)
	dataModule.removePlayer(player)

	savingPlayers[userId] = nil
end

Players.PlayerRemoving:Connect(function(player)
	playerSave(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(playerSave, player)
	end

	while next(savingPlayers) do
		task.wait()
	end
end)

task.spawn(function()
	while task.wait(60) do
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			local leaderstats = player:FindFirstChild("leaderstats")

			if leaderstats then
				local wins = leaderstats:FindFirstChild("Wins")
				local speed = leaderstats:FindFirstChild("Speed")
				local rebirths = leaderstats:FindFirstChild("Rebirths")
				local timeV = dataModule.getTime(player)

				if wins then saveData(winsOrderedDataStore, userId, wins.Value) end
				if rebirths then saveData(rebirthsOrderedDataStore, userId, rebirths.Value) end
				if speed then saveData(speedsOrderedDataStore, userId, speed.Value) end
				if timeV then saveData(timesOrderedDataStore, userId, timeV) end
			end
		end
	end
end)
