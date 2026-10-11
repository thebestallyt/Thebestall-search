-- Trainingspuppen in der Lobby und KI-Bots, die Runden auffuellen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Abilities = require(Shared:WaitForChild("Abilities"))

local Services = script.Parent :: Instance
local CombatService = require(Services:WaitForChild("CombatService"))

type Fighter = CombatService.Fighter

local BotService = {}

local rng = Random.new()
local botFolder: Folder
local bots: { Fighter } = {}

local BOT_NAMES = { "Orion", "Vega", "Nyx", "Rigel", "Lyra", "Sirius", "Draco", "Altair", "Kepler", "Nova" }
local BOT_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(90, 255, 150),
	Color3.fromRGB(255, 120, 220),
}

-- Fallback: einfacher R6-Koerper, falls das Laden des Standard-Avatars fehlschlaegt
local function buildR6(name: string, color: Color3): Model
	local model = Make("Model", { Name = name })
	local function p(partName: string, size: Vector3, col: Color3): Part
		return Make("Part", {
			Name = partName,
			Size = size,
			Color = col,
			Material = Enum.Material.SmoothPlastic,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Parent = model,
		})
	end
	local root = p("HumanoidRootPart", Vector3.new(2, 2, 1), color)
	root.Transparency = 1
	local torso = p("Torso", Vector3.new(2, 2, 1), color)
	local head = p("Head", Vector3.new(2, 1, 1), Color3.fromRGB(240, 220, 200))
	Make("SpecialMesh", { MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.25, 1.25, 1.25), Parent = head })
	local la = p("Left Arm", Vector3.new(1, 2, 1), color:Lerp(Color3.new(1, 1, 1), 0.3))
	local ra = p("Right Arm", Vector3.new(1, 2, 1), color:Lerp(Color3.new(1, 1, 1), 0.3))
	local ll = p("Left Leg", Vector3.new(1, 2, 1), Color3.fromRGB(40, 40, 60))
	local rl = p("Right Leg", Vector3.new(1, 2, 1), Color3.fromRGB(40, 40, 60))
	local function motor(motorName: string, parent: BasePart, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
		Make("Motor6D", { Name = motorName, Part0 = p0, Part1 = p1, C0 = c0, C1 = c1, Parent = parent })
	end
	motor("RootJoint", root, root, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Neck", torso, torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, torso, ra, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, torso, la, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, torso, rl, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, torso, ll, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	Make("Humanoid", { RigType = Enum.HumanoidRigType.R6, Parent = model })
	model.PrimaryPart = root
	return model
end

local function createRig(name: string, color: Color3): Model
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = Color3.fromRGB(240, 220, 200)
		desc.TorsoColor = color
		desc.LeftArmColor = color:Lerp(Color3.new(1, 1, 1), 0.3)
		desc.RightArmColor = color:Lerp(Color3.new(1, 1, 1), 0.3)
		desc.LeftLegColor = Color3.fromRGB(40, 40, 60)
		desc.RightLegColor = Color3.fromRGB(40, 40, 60)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		model.Name = name
		return model
	end
	return buildR6(name, color)
end

local function prepare(model: Model, displayName: string)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = true
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
end

-- Standard-Animationen von Roblox (Laufen/Stehen), damit NPCs nicht "gleiten"
local ANIMS = {
	R15 = { Idle = "rbxassetid://507766388", Walk = "rbxassetid://507777826" },
	R6 = { Idle = "rbxassetid://180435571", Walk = "rbxassetid://180426354" },
}

local function animate(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local hum = humanoid :: Humanoid
	local animator = hum:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		animator = Make("Animator", { Parent = hum })
	end
	local set = if hum.RigType == Enum.HumanoidRigType.R15 then ANIMS.R15 else ANIMS.R6
	local ok, idle, walk = pcall(function()
		local a1 = Make("Animation", { AnimationId = set.Idle })
		local a2 = Make("Animation", { AnimationId = set.Walk })
		local anim = animator :: Animator
		return anim:LoadAnimation(a1), anim:LoadAnimation(a2)
	end)
	if not ok or not idle or not walk then
		return
	end
	idle.Looped = true
	walk.Looped = true
	idle:Play()
	hum.Running:Connect(function(speed)
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.15)
				idle:Stop(0.15)
			end
			walk:AdjustSpeed(math.clamp(speed / 14, 0.6, 1.4))
		elseif walk.IsPlaying then
			walk:Stop(0.2)
			idle:Play(0.2)
		end
	end)
end

local function setOwner(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:CanSetNetworkOwnership() then
			part:SetNetworkOwner(nil)
		end
	end
end

-- Trainingspuppen -------------------------------------------------------------

local function spawnDummy(spot: CFrame, index: number)
	local model = createRig("TrainingDummy" .. index, Color3.fromRGB(230, 180, 90))
	prepare(model, "Training Dummy")
	model:PivotTo(spot)
	model.Parent = botFolder
	setOwner(model)
	task.spawn(animate, model)
	local f = CombatService.Register(model, { IsDummy = true, Name = "Training Dummy", BaseSpeed = 0 })
	if not f then
		model:Destroy()
		return
	end
	local fighter = f :: Fighter
	local lastHit = 0
	local conn = CombatService.Damaged:Connect(function(_, victim)
		if victim == fighter then
			lastHit = os.clock()
		end
	end)
	-- Regeneration + zurueck auf Position
	task.spawn(function()
		while model.Parent and fighter.Alive do
			task.wait(0.5)
			if os.clock() - lastHit > 3.5 and fighter.Alive then
				local h = fighter.Humanoid
				if h.Health < h.MaxHealth then
					h.Health = math.min(h.MaxHealth, h.Health + 25)
				end
				if (fighter.Root.Position - spot.Position).Magnitude > 3 and not fighter.Root.Anchored then
					model:PivotTo(spot)
					fighter.Root.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
	end)
	fighter.Humanoid.Died:Connect(function()
		conn:Disconnect()
		task.wait(3)
		model:Destroy()
		spawnDummy(spot, index)
	end)
end

function BotService.SpawnDummies(spots: { CFrame })
	for i, spot in spots do
		task.spawn(spawnDummy, spot, i)
	end
end

-- Arena-Bots ------------------------------------------------------------------

local function randomLoadout(): { string }
	local pool = {}
	for _, def in Abilities.List do
		if not def.Cutscene and not def.Exclusive then
			table.insert(pool, def.Id)
		end
	end
	local loadout = {}
	for _ = 1, 2 do
		if #pool == 0 then
			break
		end
		local i = rng:NextInteger(1, #pool)
		table.insert(loadout, pool[i])
		table.remove(pool, i)
	end
	return loadout
end

local function nearestEnemy(f: Fighter): Fighter?
	local best, bestDist = nil, math.huge
	for _, e in CombatService.Enemies(f) do
		local d = (e.Root.Position - f.Root.Position).Magnitude
		if d < bestDist then
			best, bestDist = e, d
		end
	end
	return best
end

local function runAI(f: Fighter)
	local humanoid = f.Humanoid
	local strafe = rng:NextNumber() > 0.5 and 1 or -1
	local nextStrafeSwap = 0
	local nextAbility = os.clock() + rng:NextNumber(2, 4)
	local nextBlock = os.clock() + rng:NextNumber(3, 6)
	while f.Alive and f.Character.Parent do
		task.wait(0.15)
		if not f.InRound or f.Frozen or f.InCutscene then
			continue
		end
		local target = nearestEnemy(f)
		if not target then
			continue
		end
		local myPos = f.Root.Position
		local tPos = target.Root.Position
		local dist = (tPos - myPos).Magnitude
		local t = os.clock()

		if CombatService.CanAct(f) then
			-- Faehigkeiten
			if t > nextAbility and f.Loadout and #f.Loadout > 0 then
				local id = f.Loadout[rng:NextInteger(1, #f.Loadout)]
				local def = Abilities.Get(id)
				if def and dist <= math.max(def.Range, 10) and (f.Cooldowns[id] or 0) < t then
					CombatService.TryCast(f, id, tPos)
					nextAbility = t + rng:NextNumber(3, 6)
					continue
				end
			end
			-- Blocken
			if t > nextBlock and dist < 9 then
				CombatService.TryBlock(f, true)
				task.delay(rng:NextNumber(0.5, 1.1), function()
					CombatService.TryBlock(f, false)
				end)
				nextBlock = t + rng:NextNumber(4, 8)
				continue
			end
		end

		-- Bewegen: auf Nahkampfdistanz gehen und dabei leicht seitlich ausweichen
		if t > nextStrafeSwap then
			strafe = -strafe
			nextStrafeSwap = t + rng:NextNumber(1, 2.5)
		end
		local toTarget = Vector3.new(tPos.X - myPos.X, 0, tPos.Z - myPos.Z)
		if dist > 5 then
			local side = if toTarget.Magnitude > 0 then toTarget.Unit:Cross(Vector3.yAxis) * strafe * 3 else Vector3.zero
			humanoid:MoveTo(tPos - (if toTarget.Magnitude > 0 then toTarget.Unit * 3.5 else Vector3.zero) + side)
		else
			humanoid:MoveTo(myPos)
			if toTarget.Magnitude > 0.1 and not f.Root.Anchored then
				f.Root.CFrame = CFrame.lookAt(myPos, myPos + toTarget)
			end
			if not f.Blocking then
				CombatService.DoM1(f)
			end
		end
	end
end

function BotService.SpawnArenaBot(spawnCF: CFrame): Fighter?
	local name = "Nova-Bot " .. BOT_NAMES[rng:NextInteger(1, #BOT_NAMES)]
	local color = BOT_COLORS[rng:NextInteger(1, #BOT_COLORS)]
	local model = createRig(name, color)
	prepare(model, name)
	model:PivotTo(spawnCF)
	model.Parent = botFolder
	setOwner(model)
	task.spawn(animate, model)
	local f = CombatService.Register(model, {
		IsBot = true,
		Name = name,
		BaseSpeed = 15,
		Loadout = randomLoadout(),
	})
	if not f then
		model:Destroy()
		return nil
	end
	table.insert(bots, f)
	task.spawn(runAI, f)
	f.Humanoid.Died:Connect(function()
		task.wait(2.5)
		if model.Parent then
			model:Destroy()
		end
	end)
	return f
end

function BotService.ClearArenaBots()
	for _, f in bots do
		if f.Character.Parent then
			f.Character:Destroy()
		end
	end
	table.clear(bots)
end

function BotService.Init()
	botFolder = Make("Folder", { Name = "NPCs", Parent = workspace })
end

return BotService
