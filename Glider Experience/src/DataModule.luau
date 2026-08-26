local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverModuleScriptsFolder = ServerStorage:WaitForChild("ModuleScriptsFolder")
local replicatedModuleScriptsFolder = ReplicatedStorage:WaitForChild("ModuleScriptsFolder")
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEventsFolder")

local leaderstatsModule = require(serverModuleScriptsFolder:WaitForChild("LeaderstatsModule"))
local rebirthsModule = require(replicatedModuleScriptsFolder:WaitForChild("RebirthsModule"))

local extraDataUpdate = remoteEventsFolder:WaitForChild("ExtraDataUpdateEvent")
local soundEvent = remoteEventsFolder:WaitForChild("SoundEvent")

local playersData = {}

local module = {}

function module.getXpRequirement(speed)
	return 10 * 1.05 ^ speed
end

function module.addPlayer(player, data)
	local userId = player.UserId
	playersData[userId] = data or {
		["xp"] = 0,
		["xpMultiplier"] = 1,
		["time"] = 0,
		["isNew"] = true,
		["daysStreak"] = 0,
		["lastClaimed"] = 0,
		["groupRewardClaimed"] = false,
		["worldId"] = "1",
		["leaveReward"] = false,
	}

	task.spawn(function()		
		while task.wait(1) do
			local pData = playersData[userId]
			if not pData then break end

			pData.time += 1
		end
	end)
end

function module.claimLeaveReward(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	playerData.leaveReward = true
end

function module.hasLeaveReward(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	return playerData.leaveReward
end

function module.getWorld(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	return playerData.worldId
end

function module.setWorld(player, value)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	playerData.worldId = value
end

function module.getXpMultiplier(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return playerData.xpMultiplier
end

function module.addXp(player, amount)
	local userId = player.UserId
	local playerData = playersData[userId]

	if not playerData then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local speed = leaderstats:FindFirstChild("Speed")
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if not speed or not rebirths then return end

	local xpMult = module.getXpMultiplier(player)
	local rebirthMult = rebirthsModule.getSpeedBonus(rebirths.Value)
	playerData.xp += amount * xpMult + amount * rebirthMult
	
	local sound = amount <= 1 and "XPSound1" or "XPSound2"
	soundEvent:FireClient(player, sound, false, true)

	local xpRequirement = module.getXpRequirement(speed.Value)

	while playerData.xp >= xpRequirement do
		speed.Value += 1
		soundEvent:FireClient(player, "SpeedLevelUpSound", false, true)
		playerData.xp -= xpRequirement
		xpRequirement = module.getXpRequirement(speed.Value)
	end

	extraDataUpdate:FireClient(player, module.getExtraData(player))
end

function module.setXp(player, amount)
	local userId = player.UserId
	local playerData = playersData[userId]

	if not playerData then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local speed = leaderstats:FindFirstChild("Speed")
	if not speed then return end

	playerData.xp = amount

	local xpRequirement = module.getXpRequirement(speed.Value)

	while playerData.xp >= xpRequirement do
		speed.Value += 1
		playerData.xp -= xpRequirement
		xpRequirement = module.getXpRequirement(speed.Value)
	end

	extraDataUpdate:FireClient(player, module.getExtraData(player))
end

function module.updateXpMultiplier(player, multiplier)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	playerData.xpMultiplier = multiplier
end

function module.getGroupRewardClaimed(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	return playerData.groupRewardClaimed
end

function module.claimedGroupReward(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	playerData.groupRewardClaimed = true
end

function module.getXp(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return playerData.xp
end

function module.getExtraData(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return {xp = playerData.xp, xpRequirement = module.getXpRequirement(leaderstatsModule.getSpeed(player)), xpMultiplier = playerData.xpMultiplier}
end

function module.getTime(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return playerData.time
end

function module.getIsNew(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return playerData.isNew
end

function module.setIsNew(player, value)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	playerData.isNew = value
end

function module.getDaysStreak(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return playerData.daysStreak
end

function module.setDaysStreak(player, value)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	playerData.daysStreak = value
end

function module.addDaysStreak(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	playerData.daysStreak += 1
end

function module.setLastClaimed(player, value)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	playerData.lastClaimed = value
end

function module.getLastClaimed(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end

	return playerData.lastClaimed
end

function module.getData(player)
	local userId = player.UserId
	local playerData = playersData[userId]
	if not playerData then return end
	return playerData
end

function module.removePlayer(player)
	local userId = player.UserId
	playersData[userId] = nil
end

return module
