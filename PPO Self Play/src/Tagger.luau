local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local agentData = DataStoreService:GetDataStore("AgentData1")

local updateEvent = ServerStorage:WaitForChild("UpdateEvent")
local selfPlayEvent = ServerStorage:WaitForChild("SelfPlayEvent")
local tagEvent = ServerStorage:WaitForChild("TagEvent")
local winEvent = ServerStorage:WaitForChild("WinEvent")
local valueEvent = ServerStorage:WaitForChild("ValueEvent")

local target = workspace:WaitForChild("Runner")

local agent = script.Parent
local mass = agent.AssemblyMass
local gravity = workspace.Gravity

-- Save parameters
local save = true
local key = 999
local baseKey = key * 21
local learning = true

-- Physical parameters
local color = Color3.fromRGB(42, 126, 251)

local numFrames = 8
local moveSpeed = 0.7
local turnSpeed = 2
local jumpHeight = 15
local jumpVelocity = Vector3.new(0, math.sqrt(2 * gravity * jumpHeight), 0) * mass

-- Hyperparameters
local numNeuralNetworksSelfPlay = 16
local numStepsForSaveNeuralNetwork = 1024

local batchSize = 128
local miniBatchSize = 32
local temperature = 1.0
local gamma = 0.95
local lambda = 0.99
local learningRate = 0.0003
local epsilon = 0.2
local epochs = 4

local entropyCoeff = 0.0
local explorationEntropy = 0.0

local centerToEdgeDistance = 30
local halfTurnRange = 180

-- Adam parameters
local beta1 = 0.9
local beta2 = 0.999
local adamEpsilon = 1e-8

-- Network sizes
local actorInput = 25
local actorHidden1 = 128
local actorHidden2 = 128
local actorOutput = 7 -- move(3) + turn(3) + jump(1)

local criticInput = 25
local criticHidden1 = 128
local criticHidden2 = 128
local criticOutput = 1

local actorNeuralNetwork = {}
local criticNeuralNetwork = {}

-- past states
local prevNormAgentPosX = agent.Position.X / centerToEdgeDistance
local prevNormAgentPosY = agent.Position.Y / centerToEdgeDistance
local prevNormAgentPosZ = agent.Position.Z / centerToEdgeDistance

local prevNormTargetPosX = target.Position.X / centerToEdgeDistance
local prevNormTargetPosY = target.Position.Y / centerToEdgeDistance
local prevNormTargetPosZ = target.Position.Z / centerToEdgeDistance

local prevNormAgentOriX = agent.Orientation.X / halfTurnRange
local prevNormAgentOriY = agent.Orientation.Y / halfTurnRange
local prevNormAgentOriZ = agent.Orientation.Z / halfTurnRange

local prevNormTargetOriX = target.Orientation.X / halfTurnRange
local prevNormTargetOriY = target.Orientation.Y / halfTurnRange
local prevNormTargetOriZ = target.Orientation.Z / halfTurnRange

-- Temporary variables
local batch = {}
local performanceGraph = {}

local phase = 0 -- 0=both train, 1=train against dummy, 2=dummy for opponent
local oldNeuralNetworks = {}
local steps = 0
local ready = 0
local isTag = false

local actorMomentEstimates, criticMomentEstimates

-- =========================
-- Utility helpers
-- =========================
local function initializeLayer(neuralNetwork, numNeurons, numWeights)
	local layer = {}
	local limit = math.sqrt(6 / (numWeights + numNeurons))
	for i = 1, numNeurons do
		local neuron = { bias = 0, weights = {} }
		for j = 1, numWeights do
			local weight = math.random() * 2 * limit - limit
			table.insert(neuron.weights, weight)
		end
		table.insert(layer, neuron)
	end
	table.insert(neuralNetwork, layer)
end

local function initializeGradients(neuralNetwork)
	local gradients = {}
	for i, layer in ipairs(neuralNetwork) do
		gradients[i] = {}
		for j, neuron in ipairs(layer) do
			local grad = { bias = 0, weights = {} }
			for k = 1, #neuron.weights do
				grad.weights[k] = 0
			end
			gradients[i][j] = grad
		end
	end
	return gradients
end

local function resetState()
	agent.CFrame = CFrame.new(Vector3.new(-25.5, 1.5, 0)) * CFrame.Angles(0, math.rad(-90), 0)
	agent.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	agent.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
end

local function relu(x) return math.max(0, x) end
local function reluDerivative(a) return a > 0 and 1 or 0 end

local function forwardPass(neuralNetwork, input)
	local activations = { input }
	for i, layer in ipairs(neuralNetwork) do
		local layerActivations = {}
		for _, neuron in ipairs(layer) do
			local pre = neuron.bias
			for j, w in ipairs(neuron.weights) do
				pre += activations[i][j] * w
			end
			local act = (i < #neuralNetwork) and relu(pre) or pre
			table.insert(layerActivations, act)
		end
		table.insert(activations, layerActivations)
	end
	return activations
end

local function initializeMomentEstimates(neuralNetwork)
	local moments = { m1 = {}, m2 = {}, timestep = 0 }
	for l, layer in ipairs(neuralNetwork) do
		moments.m1[l] = {}
		moments.m2[l] = {}
		for n, neuron in ipairs(layer) do
			moments.m1[l][n] = { bias = 0, weights = {} }
			moments.m2[l][n] = { bias = 0, weights = {} }
			for w = 1, #neuron.weights do
				moments.m1[l][n].weights[w] = 0
				moments.m2[l][n].weights[w] = 0
			end
		end
	end
	return moments
end

local function backpropagation(neuralNetwork, activations, errorList)
	local deltas = {}
	local gradients = {}

	table.insert(deltas, errorList)

	for i = #neuralNetwork - 1, 1, -1 do
		local layer = neuralNetwork[i]
		local nextLayer = neuralNetwork[i + 1]
		local layerDelta = {}
		for j, _ in ipairs(layer) do
			local d = 0
			for k, nextNeuron in ipairs(nextLayer) do
				d += deltas[1][k] * nextNeuron.weights[j]
			end
			d *= reluDerivative(activations[i + 1][j])
			table.insert(layerDelta, d)
		end
		table.insert(deltas, 1, layerDelta)
	end

	for i, layer in ipairs(neuralNetwork) do
		gradients[i] = {}
		for j, neuron in ipairs(layer) do
			local grad = { bias = deltas[i][j], weights = {} }
			for k, _ in ipairs(neuron.weights) do
				grad.weights[k] = deltas[i][j] * activations[i][k]
			end
			gradients[i][j] = grad
		end
	end

	return gradients
end

local function adam(momentEstimates, neuralNetwork, gradients)
	momentEstimates.timestep += 1
	local t = momentEstimates.timestep

	for l, layer in ipairs(neuralNetwork) do
		for n, neuron in ipairs(layer) do
			local gb = gradients[l][n].bias
			momentEstimates.m1[l][n].bias = beta1 * momentEstimates.m1[l][n].bias + (1 - beta1) * gb
			momentEstimates.m2[l][n].bias = beta2 * momentEstimates.m2[l][n].bias + (1 - beta2) * (gb * gb)

			local m1b = momentEstimates.m1[l][n].bias / (1 - beta1 ^ t)
			local m2b = momentEstimates.m2[l][n].bias / (1 - beta2 ^ t)
			neuron.bias -= learningRate * m1b / (math.sqrt(m2b) + adamEpsilon)

			for w = 1, #neuron.weights do
				local gw = gradients[l][n].weights[w]
				momentEstimates.m1[l][n].weights[w] = beta1 * momentEstimates.m1[l][n].weights[w] + (1 - beta1) * gw
				momentEstimates.m2[l][n].weights[w] = beta2 * momentEstimates.m2[l][n].weights[w] + (1 - beta2) * (gw * gw)

				local m1w = momentEstimates.m1[l][n].weights[w] / (1 - beta1 ^ t)
				local m2w = momentEstimates.m2[l][n].weights[w] / (1 - beta2 ^ t)
				neuron.weights[w] -= learningRate * m1w / (math.sqrt(m2w) + adamEpsilon)
			end
		end
	end
end

local function averageGradients(gradients, denom)
	for l, layer in ipairs(gradients) do
		for n, neuron in ipairs(layer) do
			gradients[l][n].bias /= denom
			for w = 1, #neuron.weights do
				gradients[l][n].weights[w] /= denom
			end
		end
	end
end

local function normalizeAdvantages(advantages)
	local sum, sumSq = 0, 0
	for _, a in ipairs(advantages) do
		sum += a
		sumSq += a * a
	end
	local mean = sum / #advantages
	local var = (sumSq / #advantages) - mean * mean
	local std = math.sqrt(var + 1e-8)
	for i = 1, #advantages do
		advantages[i] = (advantages[i] - mean) / std
	end
	return advantages
end

local function getTDError(r, v, vNext)
	return r + gamma * vNext - v
end

local function GAE(tdErrors)
	local gae = 0
	local adv = {}
	for i = #tdErrors, 1, -1 do
		gae = tdErrors[i] + gamma * lambda * gae
		table.insert(adv, 1, gae)
	end
	return adv
end

local function touchingGround()
	for _, part in pairs(agent:GetTouchingParts()) do
		if part.Name == "Baseplate" then
			return true
		end
	end
	return false
end

local function deepcopy(original, copies)
	copies = copies or {}
	if type(original) ~= "table" then return original end
	if copies[original] then return copies[original] end
	local copy = {}
	copies[original] = copy
	for k, v in next, original do
		copy[deepcopy(k, copies)] = deepcopy(v, copies)
	end
	return copy
end

local function clamp01(p) return math.clamp(p, 1e-10, 1 - 1e-10) end

local function softmax(logits, startIdx, count)
	local maxLogit = -math.huge
	for i = 0, count - 1 do
		maxLogit = math.max(maxLogit, logits[startIdx + i])
	end
	local exps, sum = {}, 0
	for i = 0, count - 1 do
		local e = math.exp(logits[startIdx + i] - maxLogit)
		exps[i + 1] = e
		sum += e
	end
	for i = 1, count do
		exps[i] /= sum
	end
	return exps
end

local function sampleCategorical(probs)
	local r = math.random()
	local cum = 0
	for i, p in ipairs(probs) do
		cum += p
		if r <= cum then return i end
	end
	return #probs
end

local function logProbCategorical(probs, idx)
	return math.log(clamp01(probs[idx]))
end

local function bernoulliProbFromLogit(logit)
	return 1 / (1 + math.exp(-logit / temperature))
end

local function logProbBernoulli(p, aBool)
	p = clamp01(p)
	return aBool and math.log(p) or math.log(1 - p)
end

-- =========================
-- Inputs / rewards
-- =========================
local function getInputs()
	local agentPos = agent.Position
	local targetPos = target.Position
	local agentOri = agent.Orientation
	local targetOri = target.Orientation

	local normAgentPosX = agentPos.X / centerToEdgeDistance
	local normAgentPosY = agentPos.Y / centerToEdgeDistance
	local normAgentPosZ = agentPos.Z / centerToEdgeDistance

	local normTargetPosX = targetPos.X / centerToEdgeDistance
	local normTargetPosY = targetPos.Y / centerToEdgeDistance
	local normTargetPosZ = targetPos.Z / centerToEdgeDistance

	local normAgentOriX = agentOri.X / halfTurnRange
	local normAgentOriY = agentOri.Y / halfTurnRange
	local normAgentOriZ = agentOri.Z / halfTurnRange

	local normTargetOriX = targetOri.X / halfTurnRange
	local normTargetOriY = targetOri.Y / halfTurnRange
	local normTargetOriZ = targetOri.Z / halfTurnRange

	local inputs = {
		normAgentPosX, normAgentPosY, normAgentPosZ,
		normTargetPosX, normTargetPosY, normTargetPosZ,
		normAgentOriX, normAgentOriY, normAgentOriZ,
		normTargetOriX, normTargetOriY, normTargetOriZ,

		prevNormAgentPosX, prevNormAgentPosY, prevNormAgentPosZ,
		prevNormTargetPosX, prevNormTargetPosY, prevNormTargetPosZ,
		prevNormAgentOriX, prevNormAgentOriY, prevNormAgentOriZ,
		prevNormTargetOriX, prevNormTargetOriY, prevNormTargetOriZ,

		#batch / batchSize,
	}

	prevNormAgentPosX, prevNormAgentPosY, prevNormAgentPosZ = normAgentPosX, normAgentPosY, normAgentPosZ
	prevNormTargetPosX, prevNormTargetPosY, prevNormTargetPosZ = normTargetPosX, normTargetPosY, normTargetPosZ
	prevNormAgentOriX, prevNormAgentOriY, prevNormAgentOriZ = normAgentOriX, normAgentOriY, normAgentOriZ
	prevNormTargetOriX, prevNormTargetOriY, prevNormTargetOriZ = normTargetOriX, normTargetOriY, normTargetOriZ

	return inputs
end

local function getOutcome(previousPosition)
	local distance = (target.Position - agent.Position).Magnitude
	if distance < 5.2 then
		return 1, true
	end
	local prevDistance = (target.Position - previousPosition).Magnitude
	local distanceChange = prevDistance - distance -- positive if tagger got closer
	local reward = distanceChange * 0.002
	return reward, false
end

local function shuffleList(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- =========================
-- PPO batch update
-- =========================
local function processBatch(batchLocal)
	local tdErrors = {}

	for i, exp in ipairs(batchLocal) do
		local v = exp.value
		local vNext = 0
		if (not exp.done) and i < #batchLocal then
			vNext = batchLocal[i + 1].value
		end
		tdErrors[i] = getTDError(exp.reward, v, vNext)
	end

	-- Critic
	local accCrit = initializeGradients(criticNeuralNetwork)
	for i, td in ipairs(tdErrors) do
		local activ = batchLocal[i].criticActivations
		local grads = backpropagation(criticNeuralNetwork, activ, { -2 * td })
		for l = 1, #criticNeuralNetwork do
			for n = 1, #criticNeuralNetwork[l] do
				accCrit[l][n].bias += grads[l][n].bias
				for w = 1, #criticNeuralNetwork[l][n].weights do
					accCrit[l][n].weights[w] += grads[l][n].weights[w]
				end
			end
		end
		if i % 64 == 0 then task.wait() end
	end
	averageGradients(accCrit, #batchLocal)
	adam(criticMomentEstimates, criticNeuralNetwork, accCrit)

	local advantages = normalizeAdvantages(GAE(tdErrors))
	for i = 1, #batchLocal do
		batchLocal[i].advantage = advantages[i]
	end

	-- Actor
	if phase ~= 2 then
		for _ = 1, epochs do
			batchLocal = shuffleList(batchLocal)
			local numMini = math.ceil(#batchLocal / miniBatchSize)

			for mb = 1, numMini do
				local s = (mb - 1) * miniBatchSize + 1
				local e = math.min(mb * miniBatchSize, #batchLocal)

				local accAct = initializeGradients(actorNeuralNetwork)
				local denom = 0

				for idx = s, e do
					local exp = batchLocal[idx]
					local A = exp.advantage
					local oldLogP = exp.log_pi_old

					local activ = forwardPass(actorNeuralNetwork, exp.state)
					local logits = activ[#activ]

					local moveProbs = softmax(logits, 1, 3)
					local turnProbs = softmax(logits, 4, 3)
					local jumpP = bernoulliProbFromLogit(logits[7])

					local newLogP =
						logProbCategorical(moveProbs, exp.moveIdx) +
						logProbCategorical(turnProbs, exp.turnIdx) +
						logProbBernoulli(jumpP, exp.jump)

					local ratio = math.exp(newLogP - oldLogP)
					local rClip = math.clamp(ratio, 1 - epsilon, 1 + epsilon)

					local chosenR
					local clippedActive = false
					if A >= 0 then
						chosenR = math.min(ratio, rClip)
						clippedActive = (chosenR == rClip) and (rClip < ratio)
					else
						chosenR = math.max(ratio, rClip)
						clippedActive = (chosenR == rClip) and (rClip > ratio)
					end

					local grad_logp = 0
					if not clippedActive then
						grad_logp = -(A * ratio)
					end

					local errorList = {0,0,0,0,0,0,0}

					for k = 1, 3 do
						local one = (k == exp.moveIdx) and 1 or 0
						errorList[k] = grad_logp * (one - moveProbs[k])
					end
					for k = 1, 3 do
						local one = (k == exp.turnIdx) and 1 or 0
						errorList[3 + k] = grad_logp * (one - turnProbs[k])
					end

					local aJump = exp.jump and 1 or 0
					errorList[7] = grad_logp * (aJump - jumpP)

					local grads = backpropagation(actorNeuralNetwork, activ, errorList)
					for l = 1, #actorNeuralNetwork do
						for n = 1, #actorNeuralNetwork[l] do
							accAct[l][n].bias += grads[l][n].bias
							for w = 1, #actorNeuralNetwork[l][n].weights do
								accAct[l][n].weights[w] += grads[l][n].weights[w]
							end
						end
					end

					denom += 1
					if denom % 32 == 0 then task.wait() end
				end

				averageGradients(accAct, denom)
				adam(actorMomentEstimates, actorNeuralNetwork, accAct)
			end
		end
	end

	local sum = 0
	for _, exp in ipairs(batchLocal) do sum += exp.reward end
	return sum / #batchLocal
end

-- =========================
-- Init networks
-- =========================
initializeLayer(actorNeuralNetwork, actorHidden1, actorInput)
initializeLayer(actorNeuralNetwork, actorHidden2, actorHidden1)
initializeLayer(actorNeuralNetwork, actorOutput, actorHidden2)

initializeLayer(criticNeuralNetwork, criticHidden1, criticInput)
initializeLayer(criticNeuralNetwork, criticHidden2, criticHidden1)
initializeLayer(criticNeuralNetwork, criticOutput, criticHidden2)

actorMomentEstimates = initializeMomentEstimates(actorNeuralNetwork)
criticMomentEstimates = initializeMomentEstimates(criticNeuralNetwork)

-- =========================
-- DataStore load/save
-- =========================
if save then
	local keyIndex = baseKey
	local ok = true
	local dataToLoad = {}
	for i = 1, 21 do
		keyIndex += 1
		local attempts = 0
		local success, value
		repeat
			attempts += 1
			success, value = pcall(function() return agentData:GetAsync(keyIndex) end)
			if not success then task.wait(1) end
		until attempts >= 5 or success

		if success and value ~= nil then
			table.insert(dataToLoad, value)
		else
			ok = false
		end
	end

	if ok then
		local idx = 1
		performanceGraph = dataToLoad[idx]

		for i = 1, #actorNeuralNetwork do
			idx += 1
			actorNeuralNetwork[i] = dataToLoad[idx]
		end
		for i = 1, #criticNeuralNetwork do
			idx += 1
			criticNeuralNetwork[i] = dataToLoad[idx]
		end
		for i = 1, #actorMomentEstimates.m1 do
			idx += 1
			actorMomentEstimates.m1[i] = dataToLoad[idx]
		end
		for i = 1, #actorMomentEstimates.m2 do
			idx += 1
			actorMomentEstimates.m2[i] = dataToLoad[idx]
		end
		for i = 1, #criticMomentEstimates.m1 do
			idx += 1
			criticMomentEstimates.m1[i] = dataToLoad[idx]
		end
		for i = 1, #criticMomentEstimates.m2 do
			idx += 1
			criticMomentEstimates.m2[i] = dataToLoad[idx]
		end
		idx += 1
		actorMomentEstimates.timestep = dataToLoad[idx]
		idx += 1
		criticMomentEstimates.timestep = dataToLoad[idx]
	end
end

game:BindToClose(function()
	print("Tagger", performanceGraph)
	local keyIndex = baseKey
	local dataToSave = {}
	table.insert(dataToSave, performanceGraph)

	for _, layer in ipairs(actorNeuralNetwork) do table.insert(dataToSave, layer) end
	for _, layer in ipairs(criticNeuralNetwork) do table.insert(dataToSave, layer) end
	for _, layer in ipairs(actorMomentEstimates.m1) do table.insert(dataToSave, layer) end
	for _, layer in ipairs(actorMomentEstimates.m2) do table.insert(dataToSave, layer) end
	for _, layer in ipairs(criticMomentEstimates.m1) do table.insert(dataToSave, layer) end
	for _, layer in ipairs(criticMomentEstimates.m2) do table.insert(dataToSave, layer) end
	table.insert(dataToSave, actorMomentEstimates.timestep)
	table.insert(dataToSave, criticMomentEstimates.timestep)

	for _, value in ipairs(dataToSave) do
		keyIndex += 1
		local attempts = 0
		local success
		repeat
			attempts += 1
			success = pcall(function()
				agentData:SetAsync(keyIndex, value)
			end)
			if not success then task.wait(1) end
		until attempts >= 5 or success
	end
end)

-- =========================
-- Events
-- =========================
updateEvent.Event:Connect(function() ready += 1 end)

selfPlayEvent.Event:Connect(function(agentName)
	if agentName == "Tagger" then
		phase = 2
		agent.Color = Color3.new(0.5, 0.5, 0.5)
	end
end)

tagEvent.Event:Connect(function()
	isTag = true
end)

local function waitForUpdate()
	updateEvent:Fire()
	while ready < 2 do task.wait() end
	ready = 0
end

-- =========================
-- Main loop
-- =========================
resetState()

while true do
	if phase == 0 and learning then
		steps += 1
	end

	local currentActor = (phase == 2) and oldNeuralNetworks[1] or actorNeuralNetwork
	local state = getInputs()

	local actActiv = forwardPass(currentActor, state)
	local logits = actActiv[#actActiv]

	local critActiv = forwardPass(criticNeuralNetwork, state)
	local value = critActiv[#critActiv][1]
	valueEvent:Fire("Tagger", value)

	local moveProbs = softmax(logits, 1, 3)
	local turnProbs = softmax(logits, 4, 3)
	local jumpP = bernoulliProbFromLogit(logits[7])

	local moveIdx = sampleCategorical(moveProbs)
	local turnIdx = sampleCategorical(turnProbs)

	local jump
	if math.random() <= explorationEntropy then
		jump = (math.random() < 0.5)
	else
		jump = (math.random() < jumpP)
	end

	local logOld =
		logProbCategorical(moveProbs, moveIdx) +
		logProbCategorical(turnProbs, turnIdx) +
		logProbBernoulli(jumpP, jump)

	local prevPos = agent.Position

	for _ = 1, numFrames do
		if moveIdx == 1 then
			agent.CFrame = agent.CFrame * CFrame.new(0, 0, -moveSpeed)
		elseif moveIdx == 3 then
			agent.CFrame = agent.CFrame * CFrame.new(0, 0, moveSpeed)
		end

		if turnIdx == 1 then
			agent.CFrame = agent.CFrame * CFrame.Angles(0, math.rad(turnSpeed), 0)
		elseif turnIdx == 3 then
			agent.CFrame = agent.CFrame * CFrame.Angles(0, math.rad(-turnSpeed), 0)
		end

		if jump and touchingGround() then
			agent:ApplyImpulse(jumpVelocity)
		end

		agent.Orientation = Vector3.new(0, agent.Orientation.Y, 0)
		task.wait()
	end

	local reward, tagged = getOutcome(prevPos)

	local done = tagged or isTag
	if (#batch + 1) >= batchSize then
		reward = -1 -- failed to tag in time
		done = true
	end

	if tagged then
		tagEvent:Fire()
	end

	table.insert(batch, {
		state = state,
		moveIdx = moveIdx,
		turnIdx = turnIdx,
		jump = jump,
		reward = reward,
		log_pi_old = logOld,
		value = value,
		criticActivations = critActiv,
		done = done,
	})

	if #batch >= batchSize or isTag then
		if phase == 0 and (tagged or isTag) then
			winEvent:Fire("Tagger")
		end

		if learning then
			if phase == 2 then
				table.remove(oldNeuralNetworks, 1)
				if #oldNeuralNetworks <= numNeuralNetworksSelfPlay / 2 then
					selfPlayEvent:Fire("Runner")
					phase = 0
					agent.Color = color
				end
			else
				local avgR = processBatch(batch)
				table.insert(performanceGraph, avgR)
			end
		end

		batch = {}
		resetState()
		waitForUpdate()
		isTag = false
	end

	if phase == 0 and steps % numStepsForSaveNeuralNetwork == 0 then
		table.insert(oldNeuralNetworks, deepcopy(actorNeuralNetwork))
		if #oldNeuralNetworks >= numNeuralNetworksSelfPlay then
			if #batch ~= 0 then
				batch = {}
				resetState()
				waitForUpdate()
				isTag = false
			end
			phase = 1
			steps = 0
		end
	end
end
