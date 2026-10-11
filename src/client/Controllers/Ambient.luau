-- Welt-Atmosphaere auf dem Client:
-- * rotierende/schwebende Deko (Tags "Spin" / "Float")
-- * Baumkronen wiegen sich im Wind (Tag "Sway", nur in Kameranaehe, max. 30x pro Sekunde)
-- * flackernde Feuer-/Laternenlichter (Tag "Flicker")
-- * Lebensbalken ueber Kaempfern im Chunky-Stil
-- * ProximityPrompts (Kisten-Altar / Black-Hole-Schrein)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Controllers = script.Parent :: Instance
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Ambient = {}
Ambient.PromptTriggered = nil :: ((string) -> ())?

local player = Players.LocalPlayer
local Make = UI.Make
local C = Theme.Colors
local TAU = math.pi * 2

-- =============================================================================
-- Drehen & Schweben
-- =============================================================================

type Animated = { inst: Instance, base: CFrame, phase: number, spin: boolean, float: boolean }
local animated: { [Instance]: Animated } = {}

local function baseCFrame(inst: Instance): CFrame?
	if inst:IsA("Model") then
		return (inst :: Model):GetPivot()
	elseif inst:IsA("BasePart") then
		return (inst :: BasePart).CFrame
	end
	return nil
end

local function track(inst: Instance)
	local cf = baseCFrame(inst)
	if not cf then
		return
	end
	local entry = animated[inst]
	if not entry then
		entry = {
			inst = inst,
			base = cf,
			phase = (cf.Position.X * 0.13 + cf.Position.Z * 0.07) % TAU,
			spin = false,
			float = false,
		}
		animated[inst] = entry
	end
	entry.spin = entry.spin or CollectionService:HasTag(inst, "Spin")
	entry.float = entry.float or CollectionService:HasTag(inst, "Float")
end

local function stepAnimated()
	local t = os.clock()
	for inst, e in animated do
		if not inst.Parent then
			animated[inst] = nil
			continue
		end
		local cf = e.base
		if e.float then
			cf = cf * CFrame.new(0, math.sin(t * 1.1 + e.phase) * 0.9, 0)
		end
		if e.spin then
			cf = cf * CFrame.Angles(0, t * 0.6 + e.phase, 0)
		end
		if inst:IsA("Model") then
			(inst :: Model):PivotTo(cf)
		elseif inst:IsA("BasePart") then
			(inst :: BasePart).CFrame = cf
		end
	end
end

-- =============================================================================
-- Wind in den Baumkronen
-- =============================================================================

local SWAY_RANGE = 250
local SWAY_STEP = 1 / 30

type SwayEntry = {
	model: Model,
	base: CFrame,
	parts: { BasePart }?,
	offsets: { CFrame }?,
	phase: number,
	amp: number,
	speed: number,
	active: boolean,
}
local swayList: { SwayEntry } = {}
local swayKnown: { [Instance]: boolean } = {}

local function trackSway(inst: Instance)
	if not inst:IsA("Model") or swayKnown[inst] then
		return
	end
	swayKnown[inst] = true
	local model = inst :: Model
	local base = model:GetPivot()
	local p = base.Position
	local seed = (p.X * 0.071 + p.Z * 0.053) % 1
	table.insert(swayList, {
		model = model,
		base = base,
		parts = nil,
		offsets = nil,
		phase = seed * TAU,
		amp = math.rad(0.7 + seed * 0.6),
		speed = 0.9 + ((p.X * 0.013) % 1) * 0.5,
		active = false,
	})
end

-- Teile erst einsammeln, wenn der Baum zum ersten Mal in Reichweite ist
local function gatherSway(e: SwayEntry)
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, d in e.model:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			table.insert(parts, part)
			table.insert(offsets, e.base:ToObjectSpace(part.CFrame))
		end
	end
	if #parts > 0 then
		e.parts = parts
		e.offsets = offsets
	end
end

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function stepSway()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local t = os.clock()
	-- sanfte Boeen: der Wind wird mal staerker, mal schwaecher
	local gust = 0.75 + 0.2 * math.sin(t * 0.23) + 0.12 * math.sin(t * 0.61 + 1.7)
	table.clear(moveParts)
	table.clear(moveCFrames)
	for i = #swayList, 1, -1 do
		local e = swayList[i]
		if not e.model.Parent then
			swayKnown[e.model] = nil
			table.remove(swayList, i)
			continue
		end
		local near = (e.base.Position - camPos).Magnitude < SWAY_RANGE
		if near and not e.parts then
			gatherSway(e)
		end
		local parts, offsets = e.parts, e.offsets
		if not parts or not offsets then
			continue
		end
		local cf: CFrame
		if near then
			local s = t * e.speed + e.phase
			local ax = math.sin(s) * e.amp * gust
			local az = math.sin(s * 0.77 + 1.3) * e.amp * 0.6 * gust
			cf = e.base * CFrame.Angles(ax, 0, az)
			e.active = true
		elseif e.active then
			-- ausser Reichweite: einmal zurueck in die Ruhelage
			cf = e.base
			e.active = false
		else
			continue
		end
		for j, part in parts do
			table.insert(moveParts, part)
			table.insert(moveCFrames, cf * offsets[j])
		end
	end
	if #moveParts > 0 then
		pcall(function()
			workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end
end

-- =============================================================================
-- Flackernde Lichter (Lagerfeuer, Fackeln, Laternen)
-- =============================================================================

type Flicker = { light: Light, base: number, seed: number }
local flickers: { Flicker } = {}
local flickerKnown: { [Instance]: boolean } = {}

local function trackFlicker(inst: Instance)
	if not inst:IsA("Light") or flickerKnown[inst] then
		return
	end
	flickerKnown[inst] = true
	local light = inst :: Light
	table.insert(flickers, { light = light, base = light.Brightness, seed = #flickers * 1.37 + 0.5 })
end

local function stepFlicker()
	local t = os.clock()
	for i = #flickers, 1, -1 do
		local f = flickers[i]
		if not f.light.Parent then
			flickerKnown[f.light] = nil
			table.remove(flickers, i)
			continue
		end
		local n = math.noise(t * 5, f.seed, 0.5) -- etwa -0.5 .. 0.5
		f.light.Brightness = f.base * (0.88 + n * 0.35)
	end
end

-- =============================================================================
-- Lebensbalken ueber Kaempfern
-- =============================================================================

local function statusChip(parent: Instance, text: string, color: Color3, width: number, order: number): Frame
	local chip = Make("Frame", {
		Name = text,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, 18),
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	})
	UI.Corner(chip, 6)
	UI.Stroke(chip, C.Ink, 2)
	UI.Text({
		Text = text,
		Font = Theme.Fonts.Heading,
		TextSize = 12,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		Stroke = 1.5,
		Parent = chip,
	})
	return chip
end

local function attachBar(character: Model)
	if character == player.Character then
		return
	end
	local head = character:WaitForChild("Head", 10) :: BasePart?
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not head or not humanoid then
		return
	end
	if head:FindFirstChild("NovaBar") then
		return
	end
	local hum = humanoid :: Humanoid
	local gui = Make("BillboardGui", {
		Name = "NovaBar",
		Size = UDim2.fromOffset(168, 64),
		StudsOffset = Vector3.new(0, 2.9, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = 110,
		Parent = head,
	})
	local nameLabel = UI.Text({
		Name = "PlayerName",
		Text = character:GetAttribute("DisplayName") or character.Name,
		Font = Theme.Fonts.Heading,
		TextSize = 17,
		TextWrapped = false,
		RichText = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
		Stroke = 2,
		Parent = gui,
	})
	local bar = UI.ProgressBar({
		Size = UDim2.new(1, -24, 0, 14),
		Position = UDim2.fromOffset(12, 23),
		Color = C.Health,
		Parent = gui,
	})
	bar.Label.Text = ""
	local chips = Make("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 43),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = gui,
	})
	UI.List(chips, true, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local blockChip = statusChip(chips, "BLOCK", C.Blue, 52, 1)
	local stunChip = statusChip(chips, "STUN", C.Gold, 44, 2)
	local slowChip = statusChip(chips, "SLOW", Theme.Lighten(C.Blue, 0.35), 44, 3)

	local function update(instant: boolean?)
		local ratio = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		bar.Set(ratio, instant)
		bar.Fill.BackgroundColor3 = if ratio < 0.3 then C.HealthLow else C.Health
	end
	local function updateStatus()
		blockChip.Visible = character:GetAttribute("Blocking") == true
		stunChip.Visible = character:GetAttribute("Stunned") == true
		slowChip.Visible = character:GetAttribute("Slowed") == true
	end
	local function updateVisible()
		gui.Enabled = character:GetAttribute("InRound") == true or character:GetAttribute("Dummy") == true
	end
	hum.HealthChanged:Connect(function()
		update(false)
	end)
	for _, attr in { "Blocking", "Stunned", "Slowed" } do
		character:GetAttributeChangedSignal(attr):Connect(updateStatus)
	end
	character:GetAttributeChangedSignal("InRound"):Connect(updateVisible)
	character:GetAttributeChangedSignal("Dummy"):Connect(updateVisible)
	character:GetAttributeChangedSignal("DisplayName"):Connect(function()
		nameLabel.Text = character:GetAttribute("DisplayName") or character.Name
	end)
	update(true)
	updateStatus()
	updateVisible()
end

local function watchCharacter(character: Instance)
	if character:IsA("Model") then
		if character:GetAttribute("Fighter") then
			task.spawn(attachBar, character :: Model)
		else
			character:GetAttributeChangedSignal("Fighter"):Connect(function()
				if character:GetAttribute("Fighter") then
					task.spawn(attachBar, character :: Model)
				end
			end)
		end
	end
end

-- =============================================================================

function Ambient.Init() end

function Ambient.Start()
	for _, tag in { "Spin", "Float" } do
		for _, inst in CollectionService:GetTagged(tag) do
			track(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	end
	for _, inst in CollectionService:GetTagged("Sway") do
		trackSway(inst)
	end
	CollectionService:GetInstanceAddedSignal("Sway"):Connect(trackSway)
	for _, inst in CollectionService:GetTagged("Flicker") do
		trackFlicker(inst)
	end
	CollectionService:GetInstanceAddedSignal("Flicker"):Connect(trackFlicker)

	RunService.RenderStepped:Connect(stepAnimated)

	local swayAcc, flickerAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		swayAcc += dt
		flickerAcc += dt
		if swayAcc >= SWAY_STEP then
			swayAcc = 0
			stepSway()
		end
		if flickerAcc >= 1 / 20 then
			flickerAcc = 0
			stepFlicker()
		end
	end)

	-- Lebensbalken fuer alle Kaempfer
	local function onPlayer(plr: Player)
		plr.CharacterAdded:Connect(watchCharacter)
		if plr.Character then
			watchCharacter(plr.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, plr in Players:GetPlayers() do
		onPlayer(plr)
	end
	task.spawn(function()
		local npcs = workspace:WaitForChild("NPCs", 30)
		if npcs then
			npcs.ChildAdded:Connect(watchCharacter)
			for _, m in npcs:GetChildren() do
				watchCharacter(m)
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if Ambient.PromptTriggered then
			Ambient.PromptTriggered(prompt.Name)
		end
	end)
end

return Ambient
