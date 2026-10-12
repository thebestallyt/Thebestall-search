-- Server-Logik aller Faehigkeiten: Hitboxen, Schaden, Bewegung, Cutscene-Steuerung.
-- Die Effekte selbst rendert jeder Client (siehe client/VFX/Abilities*).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local Services = script.Parent :: Instance
local CombatService = require(Services:WaitForChild("CombatService"))

type Fighter = CombatService.Fighter

local AbilityService = {}

local flat = CombatService.Flat
local rng = Random.new()

-- Hilfsfunktionen ---------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshRayFilter()
	local exclude = {}
	for _, f in CombatService.All() do
		table.insert(exclude, f.Character)
	end
	local vfx = workspace:FindFirstChild("ClientVFX")
	if vfx then
		table.insert(exclude, vfx)
	end
	rayParams.FilterDescendantsInstances = exclude
end

-- Bodenpunkt unter/ueber einer Position
local function ground(pos: Vector3): Vector3
	refreshRayFilter()
	local res = workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -140, 0), rayParams)
	return if res then res.Position else pos
end

local function hasGround(pos: Vector3): boolean
	refreshRayFilter()
	return workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rayParams) ~= nil
end

-- Wie weit kann man in Richtung "dir" gehen, ohne gegen eine Wand zu laufen / ins Leere zu fallen?
local function safeDistance(origin: Vector3, dir: Vector3, maxDist: number): number
	refreshRayFilter()
	local dist = maxDist
	-- Als "Characters" casten, damit auch die unsichtbaren Lobby-/Arena-Grenzen getroffen werden
	rayParams.CollisionGroup = "Characters"
	local hit = workspace:Raycast(origin, dir * maxDist, rayParams)
	rayParams.CollisionGroup = "Default"
	if hit then
		dist = math.max(0, hit.Distance - 2.5)
	end
	while dist > 3 and not hasGround(origin + dir * dist) do
		dist -= 3
	end
	return dist
end

local function payload(f: Fighter, def: any, aim: Vector3, extra: { [string]: any }?): { [string]: any }
	return {
		Id = def.Id,
		Caster = f.Character,
		Origin = f.Root.CFrame,
		Aim = aim,
		Targets = {},
		Extra = extra or {},
		Seed = rng:NextInteger(1, 1000000),
	}
end

local function cast(p: { [string]: any })
	CombatService.Broadcast("Ability", p)
end

local function chars(list: { Fighter }): { Model }
	local out = {}
	for _, f in list do
		table.insert(out, f.Character)
	end
	return out
end

-- Bots drehen wir serverseitig zum Ziel (Spieler drehen sich selbst auf dem Client)
local function faceIfBot(f: Fighter, point: Vector3)
	if f.Player == nil and not f.Root.Anchored then
		local pos = f.Root.Position
		local look = Vector3.new(point.X, pos.Y, point.Z)
		if (look - pos).Magnitude > 0.5 then
			f.Root.CFrame = CFrame.lookAt(pos, look)
		end
	end
end

-- Bewegt den Zaubernden selbst (Ansturm, Sprung ...)
local function propel(f: Fighter, velocity: Vector3, duration: number): Instance
	local root = f.Root
	local att = root:FindFirstChild("NovaPropelAtt") :: Attachment?
	if not att then
		att = Make("Attachment", { Name = "NovaPropelAtt", Parent = root })
	end
	local lv = Make("LinearVelocity", {
		Name = "NovaPropel",
		Attachment0 = att,
		MaxForce = 80000,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VectorVelocity = velocity,
		Parent = root,
	})
	Debris:AddItem(lv, duration)
	return lv
end

local function outward(from: Vector3, to: Vector3): Vector3
	return flat(to - from)
end

-- Cutscene-Rahmen: friert alle Beteiligten ein und gibt sie GARANTIERT wieder frei
local function runCutscene(f: Fighter, targets: { Fighter }, maxDuration: number, fn: (release: (Fighter) -> ()) -> ())
	local involved = { f }
	for _, t in targets do
		table.insert(involved, t)
	end
	local released: { [Fighter]: boolean } = {}
	local function release(v: Fighter)
		if released[v] then
			return
		end
		released[v] = true
		if v.Character.Parent then
			CombatService.SetCutscene(v, false)
		end
	end
	for _, v in involved do
		CombatService.SetCutscene(v, true)
	end
	task.delay(maxDuration + 3, function()
		for _, v in involved do
			release(v)
		end
	end)
	local ok, err = pcall(fn, release)
	for _, v in involved do
		release(v)
	end
	if not ok then
		error(err)
	end
end

local function tweenRoot(f: Fighter, cf: CFrame, duration: number, style: Enum.EasingStyle?)
	if not f.Root.Parent then
		return
	end
	TweenService:Create(f.Root, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = cf,
	}):Play()
end

-- Faehigkeiten --------------------------------------------------------------

local Handlers: { [string]: (Fighter, any, Vector3) -> () } = {}

Handlers.EmberPunch = function(f, def, aim)
	local dir = outward(f.Root.Position, aim)
	faceIfBot(f, aim)
	local p = payload(f, def, aim, { Dir = dir })
	cast(p)
	local lv = propel(f, dir * 68, def.Timing.Lunge)
	local hitSet: { [Fighter]: boolean } = {}
	for _ = 1, 6 do
		task.wait(0.04)
		if not f.Alive then
			return
		end
		for _, v in CombatService.InRadius(f, f.Root.Position + dir * 2.5, 6) do
			if not hitSet[v] then
				hitSet[v] = true
				CombatService.Hit(f, v, def.Damage, {
					Heavy = true,
					Knockback = dir * 72 + Vector3.new(0, 32, 0),
					KnockTime = 0.25,
					Stun = 0.8,
					Color = def.Color,
					Effect = "Fire",
				})
			end
		end
		if next(hitSet) then
			lv:Destroy()
			break
		end
	end
end

Handlers.StoneSmash = function(f, def, aim)
	faceIfBot(f, aim)
	local p = payload(f, def, aim, { Ground = ground(f.Root.Position) })
	cast(p)
	propel(f, Vector3.new(0, 30, 0), 0.16)
	task.wait(def.Timing.Impact)
	if not f.Alive then
		return
	end
	local center = f.Root.Position
	for _, v in CombatService.InRadius(f, center, def.Range) do
		CombatService.Hit(f, v, def.Damage, {
			Heavy = true,
			Knockback = outward(center, v.Root.Position) * 30 + Vector3.new(0, 52, 0),
			KnockTime = 0.25,
			Stun = 0.9,
			Effect = "Rock",
		})
	end
end

Handlers.GaleBurst = function(f, def, aim)
	local dir = outward(f.Root.Position, aim)
	faceIfBot(f, aim)
	cast(payload(f, def, aim, { Dir = dir }))
	task.wait(def.Timing.Release)
	if not f.Alive then
		return
	end
	for _, v in CombatService.InCone(f, f.Root.Position, dir, def.Range, 0.42) do
		CombatService.Hit(f, v, def.Damage, {
			Knockback = outward(f.Root.Position, v.Root.Position) * 88 + Vector3.new(0, 30, 0),
			KnockTime = 0.3,
			Stun = 0.5,
			Effect = "Wind",
		})
	end
end

Handlers.FrostShard = function(f, def, aim)
	faceIfBot(f, aim)
	local origin = f.Root.Position + Vector3.new(0, 1, 0) + flat(aim - f.Root.Position) * 2
	local baseDir = aim - origin
	if baseDir.Magnitude < 1 then
		baseDir = f.Root.CFrame.LookVector
	end
	baseDir = baseDir.Unit
	-- nicht zu steil nach oben/unten
	baseDir = Vector3.new(baseDir.X, math.clamp(baseDir.Y, -0.35, 0.35), baseDir.Z).Unit
	local dirs = {}
	for _, angle in { -11, 0, 11 } do
		table.insert(dirs, CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(baseDir))
	end
	cast(payload(f, def, aim, { Origin = origin, Dirs = dirs }))
	task.wait(def.Timing.Release)

	local speed = def.Timing.Speed
	local shards = {}
	for _, d in dirs do
		table.insert(shards, { pos = origin, dir = d, traveled = 0, alive = true })
	end
	local perShard = def.Damage / 3
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		local anyAlive = false
		refreshRayFilter()
		for _, s in shards do
			if not s.alive then
				continue
			end
			anyAlive = true
			local step = speed * dt
			local nextPos = s.pos + s.dir * step
			local victims = CombatService.NearSegment(f, s.pos, nextPos, 3.4)
			if victims[1] then
				s.alive = false
				CombatService.Hit(f, victims[1], perShard, {
					Knockback = s.dir * 18,
					KnockTime = 0.12,
					Stun = 0.3,
					Slow = 7,
					SlowTime = 2.5,
					Effect = "Ice",
				})
			elseif workspace:Raycast(s.pos, s.dir * step, rayParams) then
				s.alive = false
			end
			s.pos = nextPos
			s.traveled += step
			if s.traveled >= def.Range then
				s.alive = false
			end
		end
		if not anyAlive then
			conn:Disconnect()
		end
	end)
end

Handlers.VoltDash = function(f, def, aim)
	local from = f.Root.Position
	local dir = outward(from, aim)
	local dist = safeDistance(from, dir, def.Range)
	local to = from + dir * dist
	cast(payload(f, def, aim, { From = from, To = to, Dir = dir }))
	task.wait(def.Timing.Teleport)
	if not f.Alive or f.InCutscene then
		return
	end
	f.Character:PivotTo(CFrame.lookAt(to, to + dir))
	for _, v in CombatService.NearSegment(f, from, to, 5.5) do
		CombatService.Hit(f, v, def.Damage, {
			Knockback = dir * 14 + Vector3.new(0, 18, 0),
			KnockTime = 0.18,
			Stun = 0.95,
			Effect = "Electric",
		})
	end
end

Handlers.InfernoRing = function(f, def, aim)
	local _ = aim
	cast(payload(f, def, aim))
	CombatService.Channel(f, def.Timing.Charge + 0.2)
	task.wait(def.Timing.Charge)
	if not f.Alive then
		return
	end
	local center = f.Root.Position
	local hitSet: { [Fighter]: boolean } = {}
	for step = 1, 3 do
		local r = def.Range * step / 3
		for _, v in CombatService.InRadius(f, center, r) do
			if not hitSet[v] then
				hitSet[v] = true
				CombatService.Hit(f, v, 18, {
					Heavy = true,
					Knockback = outward(center, v.Root.Position) * 48 + Vector3.new(0, 24, 0),
					KnockTime = 0.22,
					Stun = 0.6,
					Effect = "Fire",
				})
				-- Brandschaden
				task.spawn(function()
					for _ = 1, 3 do
						task.wait(0.5)
						if v.Alive then
							CombatService.DealDamage(f, v, 2, { Effect = "Burn" })
						end
					end
				end)
			end
		end
		task.wait(def.Timing.Expand / 3)
	end
end

Handlers.TidalVortex = function(f, def, aim)
	faceIfBot(f, aim)
	local center = ground(aim)
	cast(payload(f, def, aim, { Center = center }))
	task.wait(def.Timing.Spawn)
	local elapsed, tickTimer = 0, 0
	while elapsed < def.Timing.Duration do
		local dt = task.wait(0.1)
		elapsed += dt
		tickTimer += dt
		local doTick = tickTimer >= def.Timing.Tick
		if doTick then
			tickTimer = 0
		end
		for _, v in CombatService.InRadius(f, center, 15) do
			if v.InCutscene then
				continue
			end
			local pos = v.Root.Position
			local toCenter = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
			local horizontal = if toCenter.Magnitude > 0.5 then toCenter.Unit * math.min(toCenter.Magnitude * 3, 32) else Vector3.zero
			-- seitliche Wirbelbewegung
			local swirl = if toCenter.Magnitude > 0.5 then toCenter.Unit:Cross(Vector3.yAxis) * 14 else Vector3.zero
			local lift = math.clamp((center.Y + 7 - pos.Y) * 3, -10, 22)
			CombatService.Knockback(v, horizontal + swirl + Vector3.new(0, lift, 0), 0.15)
			if doTick then
				CombatService.DealDamage(f, v, 3, { Effect = "Water" })
				CombatService.Stun(v, 0.45)
			end
		end
	end
	for _, v in CombatService.InRadius(f, center, 15) do
		CombatService.Hit(f, v, 4, {
			Knockback = outward(center, v.Root.Position) * 55 + Vector3.new(0, 20, 0),
			KnockTime = 0.22,
			Effect = "Water",
		})
	end
end

Handlers.Thunderclap = function(f, def, aim)
	faceIfBot(f, aim)
	local center = ground(aim)
	local strikes = { center }
	for _ = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(4, 8)
		table.insert(strikes, ground(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)))
	end
	cast(payload(f, def, aim, { Strikes = strikes }))
	local times = { def.Timing.Strike1, def.Timing.Strike2, def.Timing.Strike3 }
	for i, t in times do
		task.delay(t, function()
			for _, v in CombatService.InRadius(f, strikes[i], 7.5) do
				CombatService.Hit(f, v, def.Damage / 3, {
					Knockback = Vector3.new(0, 22, 0) + outward(strikes[i], v.Root.Position) * 10,
					KnockTime = 0.15,
					Stun = 0.55,
					Heavy = i == 3,
					Effect = "Electric",
				})
			end
		end)
	end
end

Handlers.ShadowStep = function(f, def, aim)
	local _ = aim
	local enemies = CombatService.InRadius(f, f.Root.Position, def.Range)
	local target = enemies[1]
	local dest: CFrame
	if target then
		local behind = (target.Root.CFrame * CFrame.new(0, 0, 3.6)).Position
		dest = CFrame.lookAt(behind, Vector3.new(target.Root.Position.X, behind.Y, target.Root.Position.Z))
		CombatService.Stun(target, 0.5)
	else
		local dir = flat(f.Root.CFrame.LookVector)
		local dist = safeDistance(f.Root.Position, dir, 20)
		local pos = f.Root.Position + dir * dist
		dest = CFrame.lookAt(pos, pos + dir)
	end
	local p = payload(f, def, aim, { Dest = dest, Target = if target then target.Character else nil })
	cast(p)
	task.wait(def.Timing.Teleport)
	if not f.Alive or f.InCutscene then
		return
	end
	f.Character:PivotTo(dest)
	task.wait(def.Timing.Slash - def.Timing.Teleport)
	if not f.Alive then
		return
	end
	local victims = CombatService.InRadius(f, dest.Position + dest.LookVector * 2, 6.5)
	for _, v in victims do
		CombatService.Hit(f, v, def.Damage, {
			Heavy = true,
			Knockback = dest.LookVector * 34 + Vector3.new(0, 14, 0),
			KnockTime = 0.2,
			Stun = 1.0,
			Effect = "Shadow",
		})
	end
end

Handlers.MeteorStrike = function(f, def, aim)
	faceIfBot(f, aim)
	local center = ground(aim)
	local back = outward(center, f.Root.Position)
	local start = center + back * 55 + Vector3.new(0, 140, 0)
	cast(payload(f, def, aim, { Center = center, Start = start }))
	task.wait(def.Timing.Fall)
	local radius = def.Timing.Radius
	for _, v in CombatService.InRadius(f, center, radius) do
		local d = (v.Root.Position - center).Magnitude
		local falloff = 1 - math.clamp(d / radius, 0, 1) * 0.4
		CombatService.Hit(f, v, def.Damage * falloff, {
			Heavy = true,
			Knockback = outward(center, v.Root.Position) * 78 + Vector3.new(0, 58, 0),
			KnockTime = 0.28,
			Stun = 1.0,
			Effect = "Fire",
		})
	end
end

Handlers.DragonBreath = function(f, def, aim)
	faceIfBot(f, aim)
	cast(payload(f, def, aim))
	CombatService.Channel(f, def.Timing.Windup + def.Timing.Channel)
	task.wait(def.Timing.Windup)
	local ticks = math.floor(def.Timing.Channel / def.Timing.Tick)
	local per = def.Damage / ticks
	for _ = 1, ticks do
		if not f.Alive or f.InCutscene then
			break
		end
		local look = f.Root.CFrame.LookVector
		for _, v in CombatService.InCone(f, f.Root.Position, look, def.Range, 0.74) do
			if CombatService.DealDamage(f, v, per, { Effect = "Burn" }) then
				CombatService.Knockback(v, flat(look) * 14, 0.12)
			end
		end
		task.wait(def.Timing.Tick)
	end
end

-- MYTHISCH / GOETTLICH / EXKLUSIV (Cutscenes) ---------------------------------

Handlers.CelestialJudgment = function(f, def, aim)
	local center = ground(aim)
	local radius = def.Timing.Radius
	local targets = CombatService.InRadius(f, center, radius)
	runCutscene(f, targets, def.CutsceneDuration, function(release)
		local look = Vector3.new(center.X, f.Root.Position.Y, center.Z)
		if (look - f.Root.Position).Magnitude > 1 then
			f.Root.CFrame = CFrame.lookAt(f.Root.Position, look)
		end
		local p = payload(f, def, aim, { Center = center })
		p.Targets = chars(targets)
		cast(p)
		task.wait(def.Timing.Impact)
		for _, v in targets do
			release(v)
		end
		for _, v in CombatService.InRadius(f, center, radius) do
			CombatService.Hit(f, v, def.Damage, {
				Heavy = true,
				Unblockable = true,
				IgnoreCutscene = true,
				Knockback = outward(center, v.Root.Position) * 40 + Vector3.new(0, 75, 0),
				KnockTime = 0.3,
				Stun = 1.2,
				Effect = "Holy",
			})
		end
		task.wait(def.CutsceneDuration - def.Timing.Impact)
	end)
end

Handlers.BloodMoon = function(f, def, aim)
	local targets = CombatService.InRadius(f, f.Root.Position, def.Range)
	runCutscene(f, targets, def.CutsceneDuration, function(release)
		local p = payload(f, def, aim)
		p.Targets = chars(targets)
		cast(p)
		task.wait(def.Timing.SlashStart)
		for _ = 1, 5 do
			for _, v in targets do
				CombatService.DealDamage(f, v, 5.6, {
					Unblockable = true,
					IgnoreCutscene = true,
					Effect = "Slash",
					Color = def.Color,
				})
			end
			task.wait(0.18)
		end
		task.wait(math.max(0, def.Timing.FinalSlash - def.Timing.SlashStart - 0.9))
		for _, v in targets do
			release(v)
		end
		for _, v in targets do
			CombatService.Hit(f, v, 8, {
				Heavy = true,
				Unblockable = true,
				Knockback = outward(f.Root.Position, v.Root.Position) * 32 + Vector3.new(0, 62, 0),
				KnockTime = 0.28,
				Stun = 1.0,
				Effect = "Slash",
				Color = def.Color,
			})
		end
		task.wait(def.CutsceneDuration - def.Timing.FinalSlash)
	end)
end

Handlers.Supernova = function(f, def, aim)
	local center = f.Root.Position
	local targets = CombatService.InRadius(f, center, def.Range)
	runCutscene(f, targets, def.CutsceneDuration, function(release)
		local startCF = f.Root.CFrame
		local p = payload(f, def, aim, { Center = center })
		p.Targets = chars(targets)
		cast(p)
		tweenRoot(f, startCF + Vector3.new(0, 9, 0), def.Timing.Rise)
		task.wait(def.Timing.Explode)
		for _, v in targets do
			release(v)
		end
		for _, v in CombatService.InRadius(f, center, def.Range) do
			local d = (v.Root.Position - center).Magnitude
			local falloff = 1 - math.clamp(d / def.Range, 0, 1) * 0.3
			CombatService.Hit(f, v, def.Damage * falloff, {
				Heavy = true,
				Unblockable = true,
				IgnoreCutscene = true,
				Knockback = outward(center, v.Root.Position) * 95 + Vector3.new(0, 62, 0),
				KnockTime = 0.3,
				Stun = 1.3,
				Effect = "Holy",
			})
		end
		task.wait(0.3)
		tweenRoot(f, startCF, 0.3, Enum.EasingStyle.Quad)
		task.wait(math.max(0, def.CutsceneDuration - def.Timing.Explode - 0.3))
	end)
end

Handlers.BlackHole = function(f, def, aim)
	local center = ground(aim) + Vector3.new(0, 7, 0)
	local rootPos = f.Root.Position
	if Vector3.new(center.X - rootPos.X, 0, center.Z - rootPos.Z).Magnitude < 10 then
		center = f.Root.Position + flat(f.Root.CFrame.LookVector) * 16 + Vector3.new(0, 6, 0)
	end
	local targets = CombatService.InRadius(f, center, def.Range)
	runCutscene(f, targets, def.CutsceneDuration, function(release)
		local startCF = f.Root.CFrame
		local look = Vector3.new(center.X, startCF.Position.Y, center.Z)
		if (look - startCF.Position).Magnitude > 1 then
			startCF = CFrame.lookAt(startCF.Position, look)
			f.Root.CFrame = startCF
		end
		local p = payload(f, def, aim, { Center = center })
		p.Targets = chars(targets)
		cast(p)
		tweenRoot(f, startCF + Vector3.new(0, 5, 0), 0.8)
		task.wait(def.Timing.Form)

		-- Ziele spiralfoermig ins Schwarze Loch ziehen
		local pullTime = def.Timing.Collapse - def.Timing.Form
		for _, v in targets do
			task.spawn(function()
				local startPos = v.Root.Position
				local rel = startPos - center
				local startAngle = math.atan2(rel.Z, rel.X)
				local startDist = Vector3.new(rel.X, 0, rel.Z).Magnitude
				local spinAxis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit
				local t = 0
				local tickTimer = 0
				while t < pullTime and v.Root.Parent and v.InCutscene do
					local dt = RunService.Heartbeat:Wait()
					t += dt
					tickTimer += dt
					local alpha = math.clamp(t / pullTime, 0, 1)
					local eased = alpha * alpha
					local dist = startDist + (4.5 - startDist) * eased
					local angle = startAngle + eased * math.pi * 3
					local height = rel.Y * (1 - eased)
					local pos = center + Vector3.new(math.cos(angle) * dist, height, math.sin(angle) * dist)
					v.Root.CFrame = CFrame.lookAt(pos, center) * CFrame.fromAxisAngle(spinAxis, eased * math.pi * 4)
					if tickTimer >= 0.5 then
						tickTimer = 0
						CombatService.DealDamage(f, v, 3, { IgnoreCutscene = true, Unblockable = true, Effect = "Void" })
					end
				end
			end)
		end
		task.wait(def.Timing.Explode - def.Timing.Form)
		for _, v in targets do
			release(v)
		end
		for _, v in CombatService.InRadius(f, center, def.Range) do
			CombatService.Hit(f, v, 35, {
				Heavy = true,
				Unblockable = true,
				IgnoreCutscene = true,
				Knockback = outward(center, v.Root.Position) * 105 + Vector3.new(0, 64, 0),
				KnockTime = 0.3,
				Stun = 1.4,
				Effect = "Void",
			})
		end
		task.wait(0.35)
		tweenRoot(f, startCF, 0.3)
		task.wait(math.max(0, def.CutsceneDuration - def.Timing.Explode - 0.35))
	end)
end

function AbilityService.Init()
	CombatService.CastHandler = function(f: Fighter, def: any, aim: Vector3)
		local handler = Handlers[def.Id]
		if handler then
			handler(f, def, aim)
		else
			warn("[AbilityService] Kein Handler fuer " .. tostring(def.Id))
		end
	end
end

return AbilityService
