-- Kampfsystem: Kaempfer-Verwaltung, M1-Kombos, Blocken, Dash, Schaden, Knockback, Stun.
-- Der Server ist die Autoritaet. Clients schicken nur Eingaben.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Signal = require(Shared:WaitForChild("Signal"))
local Net = require(Shared:WaitForChild("Net"))
local Make = require(Shared:WaitForChild("Make"))
local Services = script.Parent :: Instance
local DataService = require(Services:WaitForChild("DataService"))

local CombatConfig = Config.Combat

export type Fighter = {
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	Name: string,
	IsBot: boolean,
	IsDummy: boolean,
	InRound: boolean,
	Alive: boolean,
	Blocking: boolean,
	Combo: number,
	LastM1: number,
	NextM1: number,
	NextDash: number,
	StunUntil: number,
	SlowUntil: number,
	SlowSpeed: number,
	ChannelUntil: number,
	CastLockUntil: number,
	InCutscene: boolean,
	Frozen: boolean,
	Cooldowns: { [string]: number },
	LastAttacker: any?,
	LastAttackTime: number,
	BaseSpeed: number,
	Loadout: { string }?,
}

export type HitOptions = {
	Knockback: Vector3?,
	KnockTime: number?,
	Stun: number?,
	Slow: number?,
	SlowTime: number?,
	Heavy: boolean?,
	Unblockable: boolean?,
	IgnoreCutscene: boolean?,
	Color: Color3?,
	Effect: string?,
}

local CombatService = {}
CombatService.FighterDied = Signal.new() -- (victim: Fighter, killer: Fighter?)
CombatService.FighterAdded = Signal.new()
CombatService.Damaged = Signal.new() -- (attacker: Fighter?, victim: Fighter, amount: number)
CombatService.CastHandler = nil :: ((Fighter, any, Vector3) -> ())?

local fighters: { [Model]: Fighter } = {}

local PlayVFX = Net.Event("PlayVFX")
local HitConfirm = Net.Event("HitConfirm")
local CooldownStart = Net.Event("CooldownStart")
local CombatInput = Net.Event("CombatInput")

-- Hilfsfunktionen ---------------------------------------------------------

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end
CombatService.Flat = flat

function CombatService.Broadcast(name: string, payload: any)
	PlayVFX:FireAllClients(name, payload)
end

function CombatService.GetFighter(character: Instance?): Fighter?
	if not character then
		return nil
	end
	return fighters[character :: Model]
end

function CombatService.GetFighterFromPlayer(player: Player): Fighter?
	local char = player.Character
	return if char then fighters[char] else nil
end

function CombatService.All(): { Fighter }
	local list = {}
	for _, f in fighters do
		table.insert(list, f)
	end
	return list
end

local function now(): number
	return os.clock()
end

function CombatService.IsStunned(f: Fighter): boolean
	return now() < f.StunUntil
end

function CombatService.CanAct(f: Fighter): boolean
	if not f.Alive or f.InCutscene or f.Frozen then
		return false
	end
	local t = now()
	if t < f.StunUntil or t < f.CastLockUntil then
		return false
	end
	-- Hinweis: "Busy" (Menue/Tutorial/Kiste) sperrt NICHT den Kampf, nur die Rundenteilnahme.
	return true
end

-- Darf "attacker" das Ziel "victim" treffen?
function CombatService.CanHit(attacker: Fighter?, victim: Fighter): boolean
	if not victim.Alive or victim.Humanoid.Health <= 0 then
		return false
	end
	if attacker == nil then
		return true
	end
	if attacker == victim then
		return false
	end
	if victim.IsDummy then
		return not attacker.InRound
	end
	return attacker.InRound and victim.InRound
end

function CombatService.Enemies(attacker: Fighter): { Fighter }
	local list = {}
	for _, f in fighters do
		if CombatService.CanHit(attacker, f) then
			table.insert(list, f)
		end
	end
	return list
end

function CombatService.InRadius(attacker: Fighter, center: Vector3, radius: number): { Fighter }
	local list = {}
	for _, f in CombatService.Enemies(attacker) do
		local offset = f.Root.Position - center
		-- etwas grosszuegiger in der Hoehe
		local d = Vector3.new(offset.X, offset.Y * 0.6, offset.Z).Magnitude
		if d <= radius then
			table.insert(list, f)
		end
	end
	table.sort(list, function(a, b)
		return (a.Root.Position - center).Magnitude < (b.Root.Position - center).Magnitude
	end)
	return list
end

function CombatService.InCone(attacker: Fighter, origin: Vector3, dir: Vector3, range: number, minDot: number): { Fighter }
	local list = {}
	local d = flat(dir)
	for _, f in CombatService.Enemies(attacker) do
		local offset = f.Root.Position - origin
		local dist = offset.Magnitude
		if dist <= range and math.abs(offset.Y) < 10 then
			local dot = if dist < 2 then 1 else flat(offset):Dot(d)
			if dot >= minDot then
				table.insert(list, f)
			end
		end
	end
	return list
end

function CombatService.NearSegment(attacker: Fighter, a: Vector3, b: Vector3, radius: number): { Fighter }
	local list = {}
	local ab = b - a
	local len2 = ab:Dot(ab)
	for _, f in CombatService.Enemies(attacker) do
		local p = f.Root.Position
		local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
		local closest = a + ab * t
		if (p - closest).Magnitude <= radius then
			table.insert(list, f)
		end
	end
	return list
end

-- Zustand -----------------------------------------------------------------

local function setAttr(f: Fighter, name: string, value: any)
	if f.Character:GetAttribute(name) ~= value then
		f.Character:SetAttribute(name, value)
	end
end

function CombatService.SetBlocking(f: Fighter, on: boolean)
	if f.Blocking == on then
		return
	end
	f.Blocking = on
	setAttr(f, "Blocking", on)
	CombatService.Broadcast("Block", { Caster = f.Character, On = on })
end

function CombatService.Stun(f: Fighter, duration: number)
	if not f.Alive then
		return
	end
	f.StunUntil = math.max(f.StunUntil, now() + duration)
	if f.Blocking then
		CombatService.SetBlocking(f, false)
	end
end

function CombatService.Slow(f: Fighter, speed: number, duration: number)
	f.SlowUntil = math.max(f.SlowUntil, now() + duration)
	f.SlowSpeed = speed
end

function CombatService.Channel(f: Fighter, duration: number)
	f.ChannelUntil = math.max(f.ChannelUntil, now() + duration)
end

function CombatService.Knockback(f: Fighter, velocity: Vector3, duration: number)
	if not f.Alive or f.InCutscene or f.Root.Anchored then
		return
	end
	local root = f.Root
	local old = root:FindFirstChild("NovaKnockback")
	if old then
		old:Destroy()
	end
	local att = root:FindFirstChild("NovaKBAttachment") :: Attachment?
	if not att then
		att = Make("Attachment", { Name = "NovaKBAttachment", Parent = root })
	end
	local lv = Make("LinearVelocity", {
		Name = "NovaKnockback",
		Attachment0 = att,
		MaxForce = 60000,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VectorVelocity = velocity,
		Parent = root,
	})
	Debris:AddItem(lv, duration)
end

function CombatService.SetCutscene(f: Fighter, on: boolean)
	f.InCutscene = on
	setAttr(f, "InCutscene", on)
	if on then
		CombatService.SetBlocking(f, false)
		local kb = f.Root:FindFirstChild("NovaKnockback")
		if kb then
			kb:Destroy()
		end
	end
	if f.Root.Parent then
		f.Root.Anchored = on
	end
end

function CombatService.SetFrozen(f: Fighter, on: boolean)
	f.Frozen = on
	setAttr(f, "Frozen", on)
end

function CombatService.SetInRound(f: Fighter, on: boolean)
	f.InRound = on
	setAttr(f, "InRound", on)
end

function CombatService.HealFull(f: Fighter)
	if f.Alive then
		f.Humanoid.Health = f.Humanoid.MaxHealth
	end
end

function CombatService.ResetCooldowns(f: Fighter)
	table.clear(f.Cooldowns)
	if f.Player then
		CooldownStart:FireClient(f.Player, "*", 0)
	end
end

-- Schaden -----------------------------------------------------------------

-- Gibt (getroffen, geblockt) zurueck
function CombatService.DealDamage(attacker: Fighter?, victim: Fighter, amount: number, opts: HitOptions?): (boolean, boolean)
	local o: HitOptions = opts or {}
	if not CombatService.CanHit(attacker, victim) then
		return false, false
	end
	if victim.InCutscene and not o.IgnoreCutscene then
		return false, false
	end
	if victim.Frozen then
		return false, false
	end
	local blocked = false
	if victim.Blocking and not o.Unblockable then
		local facing = true
		if attacker then
			local toAttacker = flat(attacker.Root.Position - victim.Root.Position)
			facing = victim.Root.CFrame.LookVector:Dot(toAttacker) > -0.25
		end
		if facing then
			blocked = true
			amount *= CombatConfig.BlockDamageMultiplier
		end
	end
	amount = math.max(0, math.floor(amount * 10 + 0.5) / 10)
	local humanoid = victim.Humanoid
	humanoid.Health = math.max(0, humanoid.Health - amount)
	if attacker then
		victim.LastAttacker = attacker
		victim.LastAttackTime = now()
	end

	CombatService.Broadcast("Hit", {
		Victim = victim.Character,
		Attacker = if attacker then attacker.Character else nil,
		Amount = amount,
		Blocked = blocked,
		Heavy = o.Heavy == true,
		Color = o.Color,
		Effect = o.Effect,
	})
	if attacker and attacker.Player then
		HitConfirm:FireClient(attacker.Player, {
			Victim = victim.Character,
			Amount = amount,
			Blocked = blocked,
			IsDummy = victim.IsDummy,
		})
	end
	CombatService.Damaged:Fire(attacker, victim, amount)
	return true, blocked
end

-- Schaden + Knockback + Stun in einem Aufruf
function CombatService.Hit(attacker: Fighter?, victim: Fighter, damage: number, opts: HitOptions?): boolean
	local o: HitOptions = opts or {}
	local hit, blocked = CombatService.DealDamage(attacker, victim, damage, o)
	if not hit then
		return false
	end
	if victim.Alive and victim.Humanoid.Health > 0 then
		if o.Knockback then
			local kb = if blocked then o.Knockback * 0.25 else o.Knockback
			CombatService.Knockback(victim, kb, o.KnockTime or 0.2)
		end
		if o.Stun and not blocked then
			CombatService.Stun(victim, o.Stun)
		end
		if o.Slow then
			CombatService.Slow(victim, o.Slow, o.SlowTime or 2)
		end
	end
	return true
end

-- M1 / Block / Dash ---------------------------------------------------------

function CombatService.DoM1(f: Fighter)
	if not CombatService.CanAct(f) or f.Blocking then
		return
	end
	local t = now()
	if t < f.NextM1 then
		return
	end
	if t - f.LastM1 > CombatConfig.M1ComboReset then
		f.Combo = 0
	end
	f.Combo = f.Combo % 4 + 1
	f.LastM1 = t
	local combo = f.Combo
	local finisher = combo == 4
	f.NextM1 = t + (if finisher then CombatConfig.M1FinisherCooldown else CombatConfig.M1Cooldown)

	CombatService.Broadcast("M1", { Caster = f.Character, Combo = combo })

	task.delay(0.08, function()
		if not f.Alive then
			return
		end
		local look = f.Root.CFrame.LookVector
		local origin = f.Root.Position + flat(look) * 2.5
		local targets = CombatService.InCone(f, f.Root.Position, look, CombatConfig.M1Range, 0.2)
		local count = 0
		for _, victim in targets do
			if (victim.Root.Position - origin).Magnitude <= CombatConfig.M1Range then
				count += 1
				if count > 3 then
					break
				end
				local damage = CombatConfig.M1Damage[combo]
				if finisher and victim.Blocking then
					-- Guard Break!
					CombatService.SetBlocking(victim, false)
					CombatService.Stun(victim, CombatConfig.GuardBreakStun)
					CombatService.Broadcast("GuardBreak", { Victim = victim.Character })
					CombatService.Hit(f, victim, damage, { Heavy = true, Unblockable = true })
				elseif finisher then
					CombatService.Hit(f, victim, damage, {
						Heavy = true,
						Knockback = flat(look) * 62 + Vector3.new(0, 26, 0),
						KnockTime = 0.22,
						Stun = 0.7,
					})
				else
					CombatService.Hit(f, victim, damage, {
						Knockback = flat(look) * 8,
						KnockTime = 0.1,
						Stun = 0.42,
					})
				end
			end
		end
	end)
end

function CombatService.TryBlock(f: Fighter, on: boolean)
	if on then
		if not CombatService.CanAct(f) then
			return
		end
		CombatService.SetBlocking(f, true)
	else
		CombatService.SetBlocking(f, false)
	end
end

function CombatService.TryDash(f: Fighter, direction: Vector3?)
	if not CombatService.CanAct(f) or f.Blocking then
		return false
	end
	local t = now()
	if t < f.NextDash then
		return false
	end
	f.NextDash = t + CombatConfig.DashCooldown - 0.15 -- kleine Toleranz fuer Latenz
	local dir = if direction then flat(direction) else flat(f.Root.CFrame.LookVector)
	CombatService.Broadcast("Dash", { Caster = f.Character, Direction = dir })
	return true
end

-- Faehigkeiten --------------------------------------------------------------

function CombatService.TryCast(f: Fighter, abilityId: string, aim: Vector3?): boolean
	local def = Abilities.Get(abilityId)
	if not def or not CombatService.CastHandler then
		return false
	end
	if not CombatService.CanAct(f) or f.Blocking then
		return false
	end
	local t = now()
	if (f.Cooldowns[abilityId] or 0) > t + 0.15 then
		return false
	end
	f.Cooldowns[abilityId] = t + def.Cooldown
	f.CastLockUntil = t + def.CastLock
	if f.Player then
		CooldownStart:FireClient(f.Player, abilityId, def.Cooldown)
	end

	-- Zielpunkt pruefen/begrenzen
	local root = f.Root
	local target: Vector3 = if typeof(aim) == "Vector3" then aim else root.Position + root.CFrame.LookVector * 20
	if target ~= target then -- NaN-Schutz
		target = root.Position + root.CFrame.LookVector * 20
	end
	local offset = target - root.Position
	if offset.Magnitude > def.Range then
		target = root.Position + offset.Unit * def.Range
	end

	local handler = CombatService.CastHandler :: (Fighter, any, Vector3) -> ()
	task.spawn(function()
		local ok, err = pcall(handler, f, def, target)
		if not ok then
			warn("[Ability] Fehler in " .. def.Id .. ": " .. tostring(err))
			-- Sicherheitsnetz: niemals in einer Cutscene haengen bleiben
			if f.InCutscene then
				CombatService.SetCutscene(f, false)
			end
		end
	end)
	return true
end

-- Registrierung -------------------------------------------------------------

local function setCollisionGroup(character: Model)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Characters"
		end
	end
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Characters"
		end
	end)
end

function CombatService.Register(
	character: Model,
	opts: { Player: Player?, IsBot: boolean?, IsDummy: boolean?, Name: string?, BaseSpeed: number?, Loadout: { string }? }
): Fighter?
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return nil
	end
	local f: Fighter = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Player = opts.Player,
		Name = opts.Name or character.Name,
		IsBot = opts.IsBot == true,
		IsDummy = opts.IsDummy == true,
		InRound = false,
		Alive = true,
		Blocking = false,
		Combo = 0,
		LastM1 = 0,
		NextM1 = 0,
		NextDash = 0,
		StunUntil = 0,
		SlowUntil = 0,
		SlowSpeed = CombatConfig.NormalWalkSpeed,
		ChannelUntil = 0,
		CastLockUntil = 0,
		InCutscene = false,
		Frozen = false,
		Cooldowns = {},
		LastAttacker = nil,
		LastAttackTime = 0,
		BaseSpeed = opts.BaseSpeed or CombatConfig.NormalWalkSpeed,
		Loadout = opts.Loadout,
	}
	fighters[character] = f
	humanoid.MaxHealth = CombatConfig.MaxHealth
	humanoid.Health = CombatConfig.MaxHealth
	character:SetAttribute("Fighter", true)
	character:SetAttribute("DisplayName", f.Name)
	if f.IsDummy then
		character:SetAttribute("Dummy", true)
	end
	setCollisionGroup(character)

	humanoid.Died:Connect(function()
		if not f.Alive then
			return
		end
		f.Alive = false
		f.Blocking = false
		local killer: Fighter? = nil
		if f.LastAttacker and now() - f.LastAttackTime <= CombatConfig.KillCreditTime then
			killer = f.LastAttacker
		end
		CombatService.Broadcast("Death", { Character = character })
		CombatService.FighterDied:Fire(f, killer)
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			fighters[character] = nil
		end
	end)
	CombatService.FighterAdded:Fire(f)
	return f
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Humanoid", 10)
	if not character.Parent then
		return
	end
	CombatService.Register(character, { Player = player, Name = player.DisplayName })
end

-- Laeuft 10x pro Sekunde: Laufgeschwindigkeit & Sprungkraft je nach Zustand
local function updateStates()
	local t = now()
	for _, f in fighters do
		if not f.Alive then
			continue
		end
		local speed = f.BaseSpeed
		local jump = if f.IsDummy then 0 else 52
		if f.Frozen or f.InCutscene then
			speed, jump = 0, 0
		elseif t < f.StunUntil then
			speed, jump = 3, 0
		elseif t < f.ChannelUntil then
			speed, jump = 6, 0
		elseif f.Blocking then
			speed, jump = CombatConfig.BlockWalkSpeed, 0
		elseif t < f.SlowUntil then
			speed = math.min(speed, f.SlowSpeed)
		end
		if f.Humanoid.WalkSpeed ~= speed then
			f.Humanoid.WalkSpeed = speed
		end
		if f.Humanoid.JumpPower ~= jump then
			f.Humanoid.UseJumpPower = true
			f.Humanoid.JumpPower = jump
		end
		setAttr(f, "Stunned", t < f.StunUntil)
		setAttr(f, "Slowed", t < f.SlowUntil)
	end
end

-- Eingaben der Clients ------------------------------------------------------

local rate: { [Player]: { count: number, window: number } } = {}

local function allowInput(player: Player): boolean
	local t = now()
	local r = rate[player]
	if not r or t - r.window > 1 then
		rate[player] = { count = 1, window = t }
		return true
	end
	r.count += 1
	return r.count <= 25
end

local function onCombatInput(player: Player, action: any, a: any, b: any)
	if type(action) ~= "string" or not allowInput(player) then
		return
	end
	local f = CombatService.GetFighterFromPlayer(player)
	if not f then
		return
	end
	if action == "M1" then
		CombatService.DoM1(f)
	elseif action == "Block" then
		CombatService.TryBlock(f, a == true)
	elseif action == "Dash" then
		CombatService.TryDash(f, if typeof(a) == "Vector3" then a else nil)
	elseif action == "Ability" then
		if type(a) ~= "number" then
			return
		end
		local slot = math.floor(a)
		if slot < 1 or slot > 4 then
			return
		end
		local profile = DataService.Get(player)
		if not profile then
			return
		end
		local abilityId = profile.Equipped[slot]
		if abilityId and abilityId ~= "" and profile.Owned[abilityId] then
			CombatService.TryCast(f, abilityId, if typeof(b) == "Vector3" then b else nil)
		end
	end
end

function CombatService.Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Characters")
		PhysicsService:RegisterCollisionGroup("VFX")
	end)
	PhysicsService:CollisionGroupSetCollidable("VFX", "Characters", false)
	PhysicsService:CollisionGroupSetCollidable("VFX", "VFX", false)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		rate[player] = nil
	end)

	CombatInput.OnServerEvent:Connect(onCombatInput)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			updateStates()
		end
	end)
end

return CombatService
