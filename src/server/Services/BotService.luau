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
-- Outfit-Farben der Arena-Bots (satt, aber natuerlich - kein Neon)
local BOT_COLORS = {
	Color3.fromRGB(196, 58, 52),
	Color3.fromRGB(52, 102, 192),
	Color3.fromRGB(228, 158, 46),
	Color3.fromRGB(118, 74, 176),
	Color3.fromRGB(58, 146, 82),
	Color3.fromRGB(40, 150, 160),
}

-- Aussehen ----------------------------------------------------------------------

local C = Color3.fromRGB
local SKIN_TONES = { C(255, 220, 178), C(240, 196, 152), C(222, 172, 128), C(188, 134, 92), C(142, 96, 64), C(108, 72, 50) }
local PANTS = { C(46, 50, 64), C(66, 54, 44), C(36, 36, 42), C(84, 78, 68) }
local ACCENTS = { C(238, 234, 222), C(34, 34, 40), C(232, 184, 64), C(150, 40, 36) }
local LEG_NAMES = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot", "Left Leg", "Right Leg" }
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Zylinderachse (X) nach oben

type Look = { Head: Color3, Torso: Color3, LeftArm: Color3, RightArm: Color3, LeftLeg: Color3, RightLeg: Color3 }

-- Strohpuppe: Sackleinen-Kopf, Strohkoerper
local function dummyLook(): Look
	local straw = C(208, 170, 102)
	return {
		Head = C(214, 190, 142),
		Torso = straw,
		LeftArm = C(198, 160, 94),
		RightArm = C(198, 160, 94),
		LeftLeg = straw,
		RightLeg = straw,
	}
end

local function fighterLook(color: Color3): Look
	local skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	local pants = PANTS[rng:NextInteger(1, #PANTS)]
	local sleeves = rng:NextNumber() < 0.5
	local arm = if sleeves then color:Lerp(Color3.new(0, 0, 0), 0.12) else skin
	return { Head = skin, Torso = color, LeftArm = arm, RightArm = arm, LeftLeg = pants, RightLeg = pants }
end

-- Fallback: einfacher R6-Koerper, falls das Laden des Standard-Avatars fehlschlaegt
local function buildR6(name: string, look: Look): Model
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
	local root = p("HumanoidRootPart", Vector3.new(2, 2, 1), look.Torso)
	root.Transparency = 1
	local torso = p("Torso", Vector3.new(2, 2, 1), look.Torso)
	local head = p("Head", Vector3.new(2, 1, 1), look.Head)
	Make("SpecialMesh", { MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.25, 1.25, 1.25), Parent = head })
	local la = p("Left Arm", Vector3.new(1, 2, 1), look.LeftArm)
	local ra = p("Right Arm", Vector3.new(1, 2, 1), look.RightArm)
	local ll = p("Left Leg", Vector3.new(1, 2, 1), look.LeftLeg)
	local rl = p("Right Leg", Vector3.new(1, 2, 1), look.RightLeg)
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

local function findPart(model: Model, ...: string): BasePart?
	for _, name in { ... } do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p :: BasePart
		end
	end
	return nil
end

-- Sichtbare Groesse des Kopfes (R6-Kopf ist ein 2x1x1-Teil mit Kopf-Mesh)
local function headExtents(head: BasePart): Vector3
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Head then
		local base = math.min(head.Size.X, head.Size.Y, head.Size.Z)
		return Vector3.new(base, base, base) * mesh.Scale
	end
	if head:IsA("MeshPart") then
		return head.Size
	end
	return Vector3.new(math.min(head.Size.X, 1.3), math.min(head.Size.Y, 1.3), math.min(head.Size.Z, 1.3))
end

-- Deko-Teil, fest an ein Koerperteil geschweisst: masselos, ohne Kollision, stoert den Humanoid nicht
local function gear(rig: Model, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, partShape: Enum.PartType?): Part
	local part: Part = Make("Part", {
		Name = "Gear_" .. name,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Material = material or Enum.Material.SmoothPlastic,
		Color = color,
	})
	if partShape then
		part.Shape = partShape
	end
	part.Size = size
	part.CFrame = base.CFrame * offset
	Make("WeldConstraint", { Part0 = base, Part1 = part, Parent = part })
	part.Parent = rig
	return part
end

-- Trainingspuppe: Beine weg, stattdessen ein Holzpfahl mit Standkreuz, Seile, Zielscheibe, Naht-Augen
local function decorateDummy(rig: Model)
	local root = findPart(rig, "HumanoidRootPart")
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local head = findPart(rig, "Head")
	local torso = findPart(rig, "UpperTorso", "Torso")
	if not root or not humanoid or not head or not torso then
		return
	end
	local isR15 = rig:FindFirstChild("UpperTorso") ~= nil
	for _, n in LEG_NAMES do
		local leg = findPart(rig, n)
		if leg then
			leg.Transparency = 1
		end
	end
	local wood, woodDark = C(124, 86, 54), C(92, 62, 40)
	local rope = C(150, 112, 66)
	-- Pfahl bis zum Boden + Standkreuz
	local groundDist = if isR15 then humanoid.HipHeight + root.Size.Y / 2 else root.Size.Y / 2 + 2
	groundDist = math.clamp(groundDist, 2.2, 4.5)
	gear(rig, root, "Post", Vector3.new(groundDist + 0.4, 0.7, 0.7), CFrame.new(0, -groundDist / 2 + 0.2, 0) * UPRIGHT, wood, Enum.Material.Wood, Enum.PartType.Cylinder)
	for _, yaw in { 0, math.pi / 2 } do
		gear(rig, root, "Foot", Vector3.new(3.4, 0.36, 0.6), CFrame.new(0, -groundDist + 0.18, 0) * CFrame.Angles(0, yaw, 0), woodDark, Enum.Material.Wood)
	end
	-- Seile um den Koerper
	local ts = torso.Size
	for _, y in { ts.Y * 0.28, -ts.Y * 0.3 } do
		gear(rig, torso, "Rope", Vector3.new(ts.X + 0.08, 0.2, ts.Z + 0.08), CFrame.new(0, y, 0), rope, Enum.Material.Fabric)
	end
	gear(rig, torso, "NeckRope", Vector3.new(0.3, ts.Z * 0.9, ts.Z * 0.9), CFrame.new(0, ts.Y / 2 + 0.05, 0) * UPRIGHT, rope, Enum.Material.Fabric, Enum.PartType.Cylinder)
	for _, armName in { "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" } do
		local arm = findPart(rig, armName)
		if arm then
			local s = arm.Size
			gear(rig, arm, "Rope", Vector3.new(s.X + 0.08, 0.18, s.Z + 0.08), CFrame.new(0, -s.Y / 2 + 0.3, 0), rope, Enum.Material.Fabric)
		end
	end
	-- Zielscheibe auf der Brust
	local d = math.min(ts.X, ts.Y) * 0.62
	for i, ring in { { 1, C(196, 52, 46) }, { 0.66, C(240, 232, 214) }, { 0.33, C(196, 52, 46) } } do
		local dd = d * ring[1]
		gear(rig, torso, "Target", Vector3.new(0.06, dd, dd), CFrame.new(0, ts.Y * 0.05, -ts.Z / 2 - 0.02 - i * 0.03) * CFrame.Angles(0, math.rad(90), 0), ring[2], Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
	-- Gesicht: aufgenaehte X-Augen statt Smiley
	for _, c in head:GetChildren() do
		if c:IsA("Decal") then
			c:Destroy()
		end
	end
	local he = headExtents(head)
	local thread = C(70, 46, 30)
	for _, x in { -1, 1 } do
		for _, rot in { 45, -45 } do
			gear(rig, head, "Stitch", Vector3.new(he.X * 0.26, 0.07, 0.05), CFrame.new(x * he.X * 0.2, he.Y * 0.1, -he.Z / 2 - 0.01) * CFrame.Angles(0, 0, math.rad(rot)), thread)
		end
	end
	gear(rig, head, "Stitch", Vector3.new(he.X * 0.38, 0.07, 0.05), CFrame.new(0, -he.Y * 0.2, -he.Z / 2 - 0.01), thread)
	-- Strohbueschel oben auf dem Kopf
	gear(rig, head, "Tuft", Vector3.new(0.5, he.Y * 0.35, 0.5), CFrame.new(0, he.Y / 2 + 0.05, 0) * CFrame.Angles(0, 0, 0.15), C(226, 192, 110), Enum.Material.Fabric)
end

-- Arena-Kaempfer: Stirnband, Schal, Schulterschutz, Guertel, Armbaender (zufaellige Kombination)
local function decorateFighter(rig: Model, color: Color3)
	local head = findPart(rig, "Head")
	local torso = findPart(rig, "UpperTorso", "Torso")
	if not head or not torso then
		return
	end
	local isR15 = rig:FindFirstChild("UpperTorso") ~= nil
	local accent = ACCENTS[rng:NextInteger(1, #ACCENTS)]
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local leather = C(92, 64, 44)
	local variant = rng:NextInteger(1, 4)
	local ts = torso.Size
	local he = headExtents(head)

	if variant == 1 or variant == 3 then
		-- Stirnband mit flatternden Enden
		local band = if rng:NextNumber() < 0.5 then accent else dark
		gear(rig, head, "Headband", Vector3.new(he.Y * 0.24, he.X * 1.07, he.Z * 1.07), CFrame.new(0, he.Y * 0.2, 0) * UPRIGHT, band, Enum.Material.Fabric, Enum.PartType.Cylinder)
		for _, x in { -0.14, 0.14 } do
			gear(rig, head, "BandTail", Vector3.new(0.2, 0.9, 0.06), CFrame.new(x, he.Y * 0.2 - 0.4, he.Z * 0.54 + 0.08) * CFrame.Angles(math.rad(22), 0, math.rad(x * 80)), band, Enum.Material.Fabric)
		end
	end
	if variant == 2 or variant == 3 then
		-- Schal um den Hals, ein Ende haengt am Ruecken
		local scarf = if variant == 3 then dark else accent
		gear(rig, torso, "Scarf", Vector3.new(0.5, ts.Z * 1.3, ts.Z * 1.3), CFrame.new(0, ts.Y / 2 - 0.05, 0) * UPRIGHT, scarf, Enum.Material.Fabric, Enum.PartType.Cylinder)
		gear(rig, torso, "ScarfTail", Vector3.new(0.55, 1.3, 0.12), CFrame.new(0.35, ts.Y / 2 - 0.7, ts.Z / 2 + 0.1) * CFrame.Angles(math.rad(-8), 0, math.rad(6)), scarf, Enum.Material.Fabric)
	end
	if variant == 1 or variant == 4 then
		-- Schulterschutz
		local padColor = if rng:NextNumber() < 0.5 then C(150, 150, 158) else leather
		local padMat = if padColor == leather then Enum.Material.Leather else Enum.Material.Metal
		for side, armName in { "LeftUpperArm", "RightUpperArm" } do
			local arm = findPart(rig, armName, if side == 1 then "Left Arm" else "Right Arm")
			if arm then
				local s = arm.Size
				local tilt = if side == 1 then math.rad(14) else math.rad(-14)
				gear(rig, arm, "ShoulderPad", Vector3.new(s.X + 0.32, 0.36, s.Z + 0.36), CFrame.new(0, s.Y / 2 + 0.06, 0) * CFrame.Angles(0, 0, tilt), padColor, padMat)
			end
		end
	end
	if variant == 2 or variant == 4 then
		-- Armbaender
		for _, armName in { "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm" } do
			local arm = findPart(rig, armName)
			if arm then
				local s = arm.Size
				gear(rig, arm, "Wrap", Vector3.new(s.X + 0.12, 0.34, s.Z + 0.12), CFrame.new(0, -s.Y / 2 + 0.3, 0), accent, Enum.Material.Fabric)
			end
		end
	end
	-- Guertel mit Schnalle (immer)
	local hip = if isR15 then findPart(rig, "LowerTorso") else torso
	if hip then
		local hs = hip.Size
		local y = if isR15 then 0 else -hs.Y * 0.4
		local h = if isR15 then math.min(hs.Y * 0.9, 0.42) else 0.32
		gear(rig, hip, "Belt", Vector3.new(hs.X + 0.1, h, hs.Z + 0.1), CFrame.new(0, y, 0), leather, Enum.Material.Leather)
		gear(rig, hip, "Buckle", Vector3.new(0.42, h + 0.04, 0.08), CFrame.new(0, y, -hs.Z / 2 - 0.08), C(232, 184, 64), Enum.Material.Metal)
	end
end

local function createRig(name: string, color: Color3, style: string?): Model
	local isDummy = style == "Dummy"
	local look = if isDummy then dummyLook() else fighterLook(color)
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = look.Head
		desc.TorsoColor = look.Torso
		desc.LeftArmColor = look.LeftArm
		desc.RightArmColor = look.RightArm
		desc.LeftLegColor = look.LeftLeg
		desc.RightLegColor = look.RightLeg
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	local rig: Model = if ok and model then model else buildR6(name, look)
	rig.Name = name
	rig:SetAttribute("RigStyle", if isDummy then "Dummy" else "Fighter")
	local decorated, err = pcall(function()
		if isDummy then
			decorateDummy(rig)
		else
			decorateFighter(rig, color)
		end
	end)
	if not decorated then
		warn("[BotService] Deko fehlgeschlagen: " .. tostring(err))
	end
	return rig
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
	-- Trainingspuppen stehen still wie echte Strohpuppen
	if model:GetAttribute("RigStyle") == "Dummy" then
		return
	end
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
	local model = createRig("TrainingDummy" .. index, Color3.fromRGB(208, 170, 102), "Dummy")
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
	local model = createRig(name, color, "Fighter")
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
