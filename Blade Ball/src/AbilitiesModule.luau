local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playersModule = require(ServerStorage:WaitForChild("PlayersModule"))
local effectsModule = require(ServerStorage:WaitForChild("EffectsModule"))
local inputsModule = require(ServerStorage:WaitForChild("InputsModule"))
local soundsModule = require(ServerStorage:WaitForChild("SoundsModule"))

local cooldownEvent = ReplicatedStorage:WaitForChild("CooldownEvent")

local slashesOfFuryEvent = ReplicatedStorage:WaitForChild("SlashesOfFuryEvent")

local abilitiesInfo = {
	["Deflect"] = {
		cooldown = 1,
		charge = 1,
	},
	["OP"] = {
		cooldown = 1,
		charge = 10,
	},
	["Rapture"] = {
		cooldown = 8,
		charge = 2,
	},
	["TitanBlade"] = {
		cooldown = 10,
		charge = 1,
	},
	["Dribble"] = {
		cooldown = 4,
		charge = 3,
	},
	["Singularity"] = { 
		cooldown = 10,
		charge = 1,
	},
	["DeathSlash"] = {
		cooldown = 8,
		charge = 1,
	},
	["SlashesOfFury"] = {
		cooldown = 10,
		charge = 1,
	},
	["Infinity"] = {
		cooldown = 15,
		charge = 1,
	},
	["SlashOfDuality"] = {
		cooldown = 12,
		charge = 1,
	},
}

local playersCooldowns = {}
local slashesActivePlayers = {}
local infinityActivePlayers = {}
local module = {}

local function window(player, duration, range, targetedOnly)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local id = playersModule.setStat(player, "invincible", true)

	local ballsModule = require(ServerStorage:WaitForChild("BallsModule"))

	local start = tick()
	while start + duration > tick() do
		task.wait()
		local nearestBall = ballsModule.getNearestBall(player)
		if not nearestBall then continue end

		local distance = (nearestBall.ball.Position - hrp.Position).Magnitude

		if distance < range then
			if not targetedOnly or nearestBall:getTargetPlayer() == player then
				playersModule.resetStat(player, "invincible", id)
				return nearestBall
			end
		end
	end
	playersModule.resetStat(player, "invincible", id)
end

local function deflect(player)
	local id = playersModule.setStat(player, "deflecting", true)

	task.delay(0.5, function()
		playersModule.resetStat(player, "deflecting", id)
	end)
end

local function rapture(player)
	playersModule.forceResetStat(player, "deflecting")

	task.spawn(function()
		local walkSpeedId = playersModule.setStat(player, "walkSpeed", 0)
		local jumpPowerId = playersModule.setStat(player, "jumpPower", 0)

		local ball = window(player, 1, 20, true)
		if not ball then
			playersModule.resetStat(player, "walkSpeed", walkSpeedId)
			playersModule.resetStat(player, "jumpPower", jumpPowerId)
			return
		end

		local velocityId = ball:setStat("velocity", Vector3.new(0, 0, 0))
		local accelId = ball:setStat("acceleration", 0)
		local jerkId = ball:setStat("jerk", 0)
		local controlledId = ball:setStat("controlled", true)

		task.wait(0.2)

		playersModule.resetStat(player, "walkSpeed", walkSpeedId)
		playersModule.resetStat(player, "jumpPower", jumpPowerId)

		local ballStillOurs = effectsModule.hasSameEffect(ball, "velocity", velocityId)

		ball:resetStat("velocity", velocityId)
		ball:resetStat("acceleration", accelId)
		ball:resetStat("jerk", jerkId)
		ball:resetStat("controlled", controlledId)

		if ballStillOurs then
			soundsModule.playSoundAtPlayer(player, "RaptureSound")
			
			local currAcceleration = ball:getStat("acceleration")
			
			local accelerationId = ball:setStat("acceleration", currAcceleration + 0.15)
			ball:changeStat("accleration", currAcceleration + 0.05)

			local connection
			connection = ball.onDeflect.Event:Connect(function()
				ball:resetStat("acceleration", accelerationId)

				if connection then
					connection:Disconnect()
				end
			end)

			ball:changeStat("velocity", Vector3.new(0, 10, 0))
			local nextTarget = ball:getNextTarget()
			ball:setTarget(nextTarget)
		end
	end)
end

local function dribble(player)
	playersModule.forceResetStat(player, "deflecting")

	task.spawn(function()
		local ball = window(player, 1, 15, true)

		if not ball then return end

		local invincibleId = playersModule.setStat(player, "invincible", true)

		ball:changeStat("velocity", Vector3.new(0, 1.6, 0)) 

		local accelerationId = ball:setStat("acceleration", 0.05) 
		local decayPowerId = ball:setStat("decayPower", 0)
		local maxDistId = ball:setStat("maxDist", 0)

		ball:deflect() 

		local connection
		connection = ball.onDeflect.Event:Connect(function()
			ball:resetStat("acceleration", accelerationId)
			ball:resetStat("decayPower", decayPowerId)
			ball:resetStat("maxDist", maxDistId)
			if connection then
				connection:Disconnect()
			end
		end)

		task.wait(0.7)
		ball:resetStat("decayPower", decayPowerId)
		ball:resetStat("maxDist", maxDistId)
		ball:resetStat("acceleration", accelerationId)
		
		playersModule.resetStat(player, "invincible", invincibleId)
	end)
end

local function titanBlade(player)
	local reachId = playersModule.setStat(player, "reach", 30)
	local strengthId = playersModule.setStat(player, "strength", 1)

	task.delay(5, function()
		playersModule.resetStat(player, "reach", reachId)
		playersModule.resetStat(player, "strength", strengthId)
	end)
end

local function singularity(player)
	task.spawn(function()
		local ball = window(player, 5, 25, false)
		if not ball then return end

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local walkSpeedId = playersModule.setStat(player, "walkSpeed", 80)
		local jumpPowerId = playersModule.setStat(player, "jumpPower", 100)

		local velocityId = ball:setStat("velocity", Vector3.new(0, 0, 0))
		local accelId = ball:setStat("acceleration", 0)
		local jerkId = ball:setStat("jerk", 0)
		local controlledId = ball:setStat("controlled", true)

		ball:setTarget(hrp)

		local orbitDuration = math.random(30, 50) / 10
		local orbitStart = tick()
		local angle = 0
		local orbitSpeed = 10
		local radius = 6

		while tick() - orbitStart < orbitDuration do
			local dt = task.wait()
			if not hrp then break end

			if not effectsModule.hasSameEffect(ball, "controlled", controlledId) then break end

			angle += orbitSpeed * dt
			orbitSpeed += 8 * dt

			local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			ball.ball.Position = hrp.Position + offset
		end

		playersModule.resetStat(player, "walkSpeed", walkSpeedId)
		playersModule.resetStat(player, "jumpPower", jumpPowerId)

		ball:resetStat("velocity", velocityId)
		ball:resetStat("acceleration", accelId)
		ball:resetStat("jerk", jerkId)
		if not effectsModule.hasSameEffect(ball, "controlled", controlledId) then return end

		ball:resetStat("controlled", controlledId)

		local nextTarget = ball:getNextTarget()
		if nextTarget then
			ball:setTarget(nextTarget)

			local launchDir = (nextTarget.Position - ball.ball.Position).Unit
			ball:changeStat("velocity", launchDir * 10)
		end
	end)
end

local function deathSlash(player)
	playersModule.forceResetStat(player, "deflecting")

	task.spawn(function()
		local walkSpeedId = playersModule.setStat(player, "walkSpeed", 0)
		local jumpPowerId = playersModule.setStat(player, "jumpPower", 0)

		local ball = window(player, 1, 20, true)
		if not ball then
			playersModule.resetStat(player, "walkSpeed", walkSpeedId)
			playersModule.resetStat(player, "jumpPower", jumpPowerId)
			return
		end

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local velocityId = ball:setStat("velocity", Vector3.new(0, 0, 0))
		local accelId = ball:setStat("acceleration", 0)
		local jerkId = ball:setStat("jerk", 0)
		local controlledId = ball:setStat("controlled", true)
		

		local holdDuration = math.random(20, 30) / 10
		local holdStart = tick()

		while tick() - holdStart < holdDuration do
			task.wait()
			if not hrp then break end
			if not effectsModule.hasSameEffect(ball, "controlled", controlledId) then break end

			local camCFrame = inputsModule.getCameraCFrame(player)
			if camCFrame then
				local flatLook = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
				local targetPos = hrp.Position + (flatLook * 5)

				ball.ball.Position = ball.ball.Position:Lerp(targetPos, 0.05)
			end
		end

		playersModule.resetStat(player, "walkSpeed", walkSpeedId)
		playersModule.resetStat(player, "jumpPower", jumpPowerId)

		ball:resetStat("velocity", velocityId)
		ball:resetStat("acceleration", accelId)
		ball:resetStat("jerk", jerkId)

		local ballStillOurs = effectsModule.hasSameEffect(ball, "controlled", controlledId)

		ball:resetStat("controlled", controlledId)

		if ballStillOurs then
			soundsModule.playSoundAtPlayer(player, "DeathSlashSound")
			
			local currAcceleration = ball:getStat("acceleration")
			
			local accelerationId = ball:setStat("acceleration", currAcceleration + 0.3)
			ball:changeStat("acceleration", currAcceleration + 0.1)

			local connection
			connection = ball.onDeflect.Event:Connect(function()
				ball:resetStat("acceleration", accelerationId)
				if connection then
					connection:Disconnect()
				end
			end)

			local nextTarget = ball:getNextTarget()
			if nextTarget then
				ball:setTarget(nextTarget)

				local toTarget = (nextTarget.Position - ball.ball.Position).Unit
				local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)

				local rightVector = hrp.CFrame.RightVector
				if flatToTarget.Magnitude > 0.001 then
					rightVector = flatToTarget.Unit:Cross(Vector3.new(0, 1, 0)).Unit
				end

				local upVector = Vector3.new(0, 1, 0)
				local launchDir = (toTarget + (rightVector * 1.5) + (upVector * 0.5)).Unit

				ball:changeStat("velocity", launchDir * 20) 
			end
		end
	end)
end

local function slashesOfFury(player)
	playersModule.forceResetStat(player, "deflecting")

	task.spawn(function()
		local ball = window(player, 1, 20, true)
		if not ball then return end

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local velocityId = ball:setStat("velocity", Vector3.new(0, 0, 0))
		local accelId = ball:setStat("acceleration", 0)
		local jerkId = ball:setStat("jerk", 0)
		local controlledId = ball:setStat("controlled", true)

		local holdStart = tick()
		local maxDuration = 5

		local userId = player.UserId
		slashesActivePlayers[userId] = { deflects = 0, lastClick = tick(), ball = ball }

		while tick() - holdStart < maxDuration do
			task.wait()
			if not hrp then break end
			if not effectsModule.hasSameEffect(ball, "controlled", controlledId) then break end

			local session = slashesActivePlayers[userId]

			if tick() - session.lastClick >= 0.8 then
				break
			end

			local camCFrame = inputsModule.getCameraCFrame(player)
			if camCFrame then
				local flatLook = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
				local targetPos = hrp.Position + (flatLook * 5)
				ball.ball.Position = ball.ball.Position:Lerp(targetPos, 0.1)
			else
				local targetPos = hrp.Position + (hrp.CFrame.LookVector * 5)
				ball.ball.Position = ball.ball.Position:Lerp(targetPos, 0.1)
			end
		end
		
		slashesOfFuryEvent:FireClient(player, ball.ball, nil)
		
		local finalDeflects = slashesActivePlayers[userId] and slashesActivePlayers[userId].deflects or 0
		slashesActivePlayers[userId] = nil
		
		ball:resetStat("velocity", velocityId)
		ball:resetStat("acceleration", accelId)
		ball:resetStat("jerk", jerkId)

		local ballStillOurs = effectsModule.hasSameEffect(ball, "controlled", controlledId)
		ball:resetStat("controlled", controlledId)

		if ballStillOurs then
			local finalPower = finalDeflects ^ 0.8

			ball:changeStat("velocity", Vector3.new(0, finalPower, 0))

			local maxDistId = ball:setStat("maxDist", 300)
			local decayPowerId = ball:setStat("decayPower", 0.3)
			ball:deflect()

			local connection
			connection = ball.onDeflect.Event:Connect(function()
				ball:resetStat("maxDist", maxDistId)
				ball:resetStat("decayPower", decayPowerId)
				if connection then
					connection:Disconnect()
				end
			end)

			local nextTarget = ball:getNextTarget()
			if nextTarget then
				ball:setTarget(nextTarget)
			end
		end
	end)
end

local function infinity(player)
	local userId = player.UserId

	if infinityActivePlayers[userId] then
		infinityActivePlayers[userId].endTime = tick() + 8
		return
	end

	playersModule.forceResetStat(player, "deflecting")

	task.spawn(function()
		local ballsModule = require(ServerStorage:WaitForChild("BallsModule"))
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local invincibleId = playersModule.setStat(player, "invincible", true)

		infinityActivePlayers[userId] = { shoot = false, endTime = tick() + 8 }

		local caughtBalls = {} 

		local function releaseBall(ballObj, stats, shouldDeflect)
			if not ballObj then return end

			if stats.velocityId then ballObj:resetStat("velocity", stats.velocityId) end
			if stats.accelId then ballObj:resetStat("acceleration", stats.accelId) end
			if stats.jerkId then ballObj:resetStat("jerk", stats.jerkId) end
			if stats.controlledId then ballObj:resetStat("controlled", stats.controlledId) end

			if shouldDeflect and ballObj.ball and ballObj.ball.Parent then
				ballObj:deflect()
				local nextTarget = ballObj:getNextTarget()
				if nextTarget then ballObj:setTarget(nextTarget) end
			end
		end

		while infinityActivePlayers[userId] and tick() < infinityActivePlayers[userId].endTime do
			task.wait() 
			if not (character and character.Parent and hrp) then break end

			if not effectsModule.hasSameEffect(player, "invincible", invincibleId) then
				break
			end

			local session = infinityActivePlayers[userId]
			local triggerShoot = session and session.shoot
			if triggerShoot then session.shoot = false end

			local camCFrame = inputsModule.getCameraCFrame(player)
			local look = camCFrame and camCFrame.LookVector or hrp.CFrame.LookVector

			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0.001 then
				flatLook = flatLook.Unit
			else
				flatLook = hrp.CFrame.LookVector
			end
			local targetPos = hrp.Position + (flatLook * 2)

			local ballsInZone = ballsModule.getBallsInRadius(hrp.Position, 30, player)
			local inZoneLookup = {}

			for _, b in ipairs(ballsInZone) do
				if not b or not b.ball or not b.ball.Parent then continue end

				inZoneLookup[b] = true

				if not caughtBalls[b] and not effectsModule.hasEffect(b, "controlled") then
					caughtBalls[b] = {
						velocityId = b:setStat("velocity", Vector3.zero),
						accelId = b:setStat("acceleration", 0),
						jerkId = b:setStat("jerk", 0),
						controlledId = b:setStat("controlled", true)
					}
				end

				if caughtBalls[b] then
					if triggerShoot then
						releaseBall(b, caughtBalls[b], true)
						caughtBalls[b] = nil
						playersModule.forceResetStat(player, "deflecting")
						module.resetCooldown(player, "Deflect")
					else
						if b.ball and b.ball.Parent then
							b.ball.Position = b.ball.Position:Lerp(targetPos, 0.05)
						end
					end
				end
			end

			for b, stats in pairs(caughtBalls) do
				if not inZoneLookup[b] then
					releaseBall(b, stats, false)
					caughtBalls[b] = nil
				end
			end
		end

		for b, stats in pairs(caughtBalls) do
			releaseBall(b, stats, false)
		end

		playersModule.resetStat(player, "invincible", invincibleId)
		infinityActivePlayers[userId] = nil
	end)
end

local function slashOfDuality(player)
	playersModule.forceResetStat(player, "deflecting")

	task.spawn(function()
		local ballsModule = require(ServerStorage:WaitForChild("BallsModule"))
		local ball = ballsModule.getNearestBall(player)
		if not ball then return end

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local mousePos = inputsModule.getMousePos(player)
		local targetPart = nil

		if mousePos then
			targetPart = ballsModule.getNearestTargetToPosition(mousePos, hrp)
		end

		targetPart = targetPart or ball:getNextTarget()

		task.wait(1)

		if not character or not character.Parent or not hrp or not targetPart then return end

		ball:setTarget(hrp)

		local launchDir = (targetPart.Position - ball.ball.Position).Unit
		if launchDir.Magnitude > 0 then
			ball:changeStat("velocity", launchDir * 15)
		end

		hrp.CFrame = ball.ball.CFrame
		ball:setTarget(targetPart)
	end)
end

function module.addPlayer(player)
	local userId = player.UserId
	playersCooldowns[userId] = {}
end

function module.removePlayer(player)
	local userId = player.UserId
	local playerCooldowns = playersCooldowns[userId]

	if playerCooldowns then
		for abilityName, state in pairs(playerCooldowns) do
			if state.stopwatch then
				task.cancel(state.stopwatch)
			end
		end
	end

	slashesActivePlayers[userId] = nil
	infinityActivePlayers[userId] = nil
	playersCooldowns[userId] = nil
end

function module.ability(player, ability)
	local userId = player.UserId

	if ability == "Deflect" then
		if slashesActivePlayers[userId] then
			slashesActivePlayers[userId].deflects += 1
			slashesActivePlayers[userId].lastClick = tick()
			soundsModule.playSoundAtPlayer(player, "DeflectSound")
			
			local currentBall = slashesActivePlayers[userId].ball
			slashesOfFuryEvent:FireClient(player, currentBall.ball, slashesActivePlayers[userId].deflects)
			return
		elseif infinityActivePlayers[userId] then
			infinityActivePlayers[userId].shoot = true
			return
		end
	end

	local playerCooldowns = playersCooldowns[userId]
	if not playerCooldowns then return end

	local info = abilitiesInfo[ability]

	if not playerCooldowns[ability] then
		playerCooldowns[ability] = {
			charges = info.charge,
			stopwatch = nil
		}
	end

	local state = playerCooldowns[ability]

	if state.charges <= 0 then
		return 
	end

	state.charges -= 1

	if ability == "Deflect" then
		deflect(player)
	elseif ability == "OP" then
		infinity(player)
	elseif ability == "Rapture" then
		rapture(player)
	elseif ability == "TitanBlade" then
		titanBlade(player)
	elseif ability == "Dribble" then
		dribble(player)
	elseif ability == "Singularity" then
		singularity(player)
	elseif ability == "DeathSlash" then
		deathSlash(player)
	elseif ability == "SlashesOfFury" then
		slashesOfFury(player)
	elseif ability == "Infinity" then
		infinity(player)
	elseif ability == "SlashOfDuality" then
		slashOfDuality(player)
	end

	local cooldownToSend = 0

	if info.charge > 1 then
		cooldownToSend = 0
	elseif state.charges == 0 then
		cooldownToSend = info.cooldown
	end

	if ability == "Deflect" then
		cooldownEvent:FireClient(player, "Deflect", cooldownToSend, state.charges)
	else
		cooldownEvent:FireClient(player, "Ability", cooldownToSend, state.charges)
	end

	if not state.stopwatch then
		state.stopwatch = task.spawn(function()
			while state.charges < info.charge do
				task.wait(info.cooldown)
				state.charges += 1

				if ability == "Deflect" then
					cooldownEvent:FireClient(player, "Deflect", 0, state.charges)
				else
					cooldownEvent:FireClient(player, "Ability", 0, state.charges)
					soundsModule.playSoundAtPlayer(player, "CooldownResetSound")
				end
			end
			state.stopwatch = nil
		end)
	end
end

function module.resetCooldown(player, ability)
	local userId = player.UserId
	local playerCooldowns = playersCooldowns[userId]
	if not playerCooldowns then return end

	for oldAbilityName, state in pairs(playerCooldowns) do
		if oldAbilityName ~= "Deflect" or ability == "Deflect" then
			if state.stopwatch then
				task.cancel(state.stopwatch)
				state.stopwatch = nil
			end

			if abilitiesInfo[oldAbilityName] then
				state.charges = abilitiesInfo[oldAbilityName].charge
			end
		end
	end

	if not playerCooldowns[ability] then
		playerCooldowns[ability] = {
			charges = abilitiesInfo[ability].charge,
			stopwatch = nil
		}
	end

	local state = playerCooldowns[ability]

	if ability == "Deflect" then
		cooldownEvent:FireClient(player, "Deflect", 0, state.charges)
	else
		cooldownEvent:FireClient(player, "Ability", 0, state.charges)
	end
end

return module
