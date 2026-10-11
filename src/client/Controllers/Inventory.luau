-- Inventar ("ABILITIES"): Loadout mit Slot 1-4, Sammlung aller Faehigkeiten, Detail-Ansicht
-- mit Ausruesten und VFX-Vorschau. Gebaut mit den Chunky-UI-Bausteinen aus UI.luau/Theme.luau:
-- feste Farben, dicke dunkle Umrisse, 3D-Buttons – keine Neon-Verlaeufe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))

local Controllers = script.Parent :: Instance
local State = require(Controllers:WaitForChild("State"))
local HUD = require(Controllers:WaitForChild("HUD"))
local VFXController = require(Controllers:WaitForChild("VFXController"))
local Client = Controllers.Parent :: Instance
local UIFolder = Client:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UI"))
local Theme = require(UIFolder:WaitForChild("Theme"))

local Inventory = {}

local Make = UI.Make
local C = Theme.Colors
local F = Theme.Fonts
local player = Players.LocalPlayer

-- Masse ---------------------------------------------------------------------------------
-- Fenster 1040 x 660, der Inhaltsbereich beginnt 70 px unter der Oberkante.
local WIN_W, WIN_H = 1040, 660
local CONTENT_H = WIN_H - 70
local PAD = 20 -- Aussenabstand links/rechts/unten
local TOP = 8 -- Abstand unter der Kopfleiste
local GAP = 16 -- Abstand zwischen linker Spalte und Detail-Karte
local DETAIL_W = 336
local LEFT_W = WIN_W - PAD * 2 - GAP - DETAIL_W -- 648
local COLUMN_H = CONTENT_H - TOP - PAD -- 562

local LOADOUT_H = 124
local SLOT_W, SLOT_H, SLOT_GAP = 112, 100, 8
local SLOT_TILE = 64

local CELL_W, CELL_H = 112, 110
local GRID_TILE = 80

local HERO_H = 188
local HERO_TILE = 116
local INNER_W = DETAIL_W - 32 -- nutzbare Breite in der Detail-Karte
local ACTION_Y = COLUMN_H - 16 - 56 -- grosser Button unten in der Detail-Karte
local ROW_Y = ACTION_Y - 12 - 52 -- Reihe mit den Slot-Buttons / Info-Box
local CAPTION_Y = ROW_Y - 24

local FILTERS = { "ALL", "OWNED", "LOCKED" }
local HAS_KEYBOARD = UserInputService.KeyboardEnabled

-- Zustand ------------------------------------------------------------------------------

type Cell = { Ring: Frame, Tile: Frame }

local window: UI.Window
local loadoutRow: Frame
local gridScroll: ScrollingFrame
local gridEmpty: TextLabel
local collectBar: UI.Bar
local detailsBody: Frame
local filterButtons: { [string]: TextButton } = {}

local selected: string? = nil
local shownId: string? = nil -- zuletzt im Detailbereich gezeigte Faehigkeit (fuer die Pop-Animation)
local filter = "ALL"
local equipBusy = false
local pendingPop: { Slot: number, Id: string }? = nil -- Slot, der nach dem Ausruesten kurz "aufploppt"

local gridCells: { [string]: Cell } = {}
local slotTiles: { [number]: GuiObject } = {}
local slotStrokes: { [number]: UIStroke } = {}
local slotIds: { [number]: string } = {}

-- Hilfsfunktionen ------------------------------------------------------------------------

local function textWidth(text: string, size: number, font: Enum.Font): number
	local ok, result = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 200))
	end)
	if ok and typeof(result) == "Vector2" then
		return result.X
	end
	return #text * size * 0.62
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function fmtNumber(n: number): string
	if n % 1 == 0 then
		return tostring(math.floor(n))
	end
	return string.format("%.1f", n)
end

local function sortedAbilities(): { any }
	local list = table.clone(Abilities.List)
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

local function equippedId(slot: number): string
	local p = State.Profile
	local id = if p and type(p.Equipped) == "table" then p.Equipped[slot] else nil
	return if type(id) == "string" then id else ""
end

local function equippedSlotOf(id: string): number?
	for slot = 1, 4 do
		if equippedId(slot) == id then
			return slot
		end
	end
	return nil
end

-- Kleines rundes Schild mit Umriss ("x3", "OWNED", "SLOT 2" ...)
local function pill(
	parent: Instance,
	text: string,
	color: Color3,
	opts: { Position: UDim2, AnchorPoint: Vector2?, Height: number?, TextSize: number?, ZIndex: number?, MinWidth: number?, Transparency: number? }
): Frame
	local h = opts.Height or 22
	local ts = opts.TextSize or 14
	local z = opts.ZIndex or 5
	local w = math.max(opts.MinWidth or h, math.ceil(textWidth(text, ts, F.Heading)) + 16)
	local frame = Make("Frame", {
		Name = "Pill",
		BackgroundColor3 = color,
		BackgroundTransparency = opts.Transparency or 0,
		BorderSizePixel = 0,
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		Position = opts.Position,
		Size = UDim2.fromOffset(w, h),
		ZIndex = z,
		Parent = parent,
	})
	UI.Round(frame)
	UI.Stroke(frame, C.Ink, 2, 0)
	UI.Text({
		Text = text,
		Font = F.Heading,
		TextSize = ts,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Stroke = 1.5,
		Parent = frame,
	})
	return frame
end

-- Tasten-Schild wie in der HUD-Leiste (eckig, dunkel, Zahl)
local function keyBadge(parent: Instance, n: number, position: UDim2, color: Color3?, z: number?): Frame
	local zi = z or 6
	local key = Make("Frame", {
		Name = "Key",
		BackgroundColor3 = color or C.PanelDark,
		BorderSizePixel = 0,
		Position = position,
		Size = UDim2.fromOffset(24, 24),
		ZIndex = zi,
		Parent = parent,
	})
	UI.Corner(key, 6)
	UI.Stroke(key, C.Ink, 2, 0)
	UI.Text({
		Text = tostring(n),
		Font = F.Heading,
		TextSize = 15,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zi + 1,
		Stroke = 1.5,
		Parent = key,
	})
	return key
end

-- Kleine Ueberschrift (z.B. "EQUIP TO SLOT")
local function caption(parent: Instance, text: string, position: UDim2, size: UDim2, align: Enum.TextXAlignment?, color: Color3?): TextLabel
	return UI.Text({
		Text = text,
		Font = F.Heading,
		TextSize = 15,
		TextColor3 = color or C.Muted,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = position,
		Size = size,
		Parent = parent,
	})
end

-- Werte-Kaestchen in der Detail-Karte (DAMAGE / COOLDOWN / CUTSCENE)
local function statPill(parent: Instance, label: string, value: string, color: Color3, width: number, order: number)
	local box = UI.Inset({
		Name = label,
		Size = UDim2.fromOffset(width, 52),
		Radius = 10,
		LayoutOrder = order,
		Parent = parent,
	})
	-- farbiger Streifen oben als Kennzeichnung
	local accent = Make("Frame", {
		Name = "Accent",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(24, 4),
		Parent = box,
	})
	UI.Round(accent)
	UI.Text({
		Text = label,
		Font = F.Bold,
		TextSize = 11,
		TextColor3 = Theme.Lighten(color, 0.35),
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = box,
	})
	UI.Text({
		Text = value,
		Font = F.Heading,
		TextSize = 22,
		TextWrapped = false,
		Position = UDim2.fromOffset(0, 25),
		Size = UDim2.new(1, 0, 0, 24),
		Stroke = 2,
		Parent = box,
	})
end

-- Auswahl & Ausruesten ----------------------------------------------------------------------

local renderDetails: () -> ()

-- Goldrahmen im Raster und im Loadout an die aktuelle Auswahl anpassen
local function updateSelectionVisuals()
	for id, cell in gridCells do
		cell.Ring.Visible = id == selected
	end
	for slot, stroke in slotStrokes do
		local id = slotIds[slot]
		local isSel = id ~= nil and id ~= "" and id == selected
		stroke.Color = if isSel then C.Gold else C.Ink
		stroke.Thickness = if isSel then 3 else 2
		stroke.Transparency = if isSel then 0 else 0.3
	end
end

local function select(id: string)
	if selected == id then
		return
	end
	selected = id
	renderDetails()
	updateSelectionVisuals()
end

local function equip(id: string, slot: number)
	if equipBusy or equippedId(slot) == id then
		return
	end
	equipBusy = true
	pendingPop = { Slot = slot, Id = id }
	local okCall, ok, err = pcall(function()
		return Net.Function("EquipAbility"):InvokeServer(id, slot)
	end)
	equipBusy = false
	if okCall and ok == true then
		State.TutorialEvent:Fire("Equipped", id)
		UI.Sound("Tutorial")
		-- Kam das neue Profil schon vor der Antwort an, hier direkt aufploppen lassen
		local pop = pendingPop
		if pop and equippedId(pop.Slot) == pop.Id then
			pendingPop = nil
			local tile = slotTiles[pop.Slot]
			if tile and tile.Parent then
				UI.Pop(tile, 0.6, 0.35)
			end
		end
	else
		pendingPop = nil
		local msg = if okCall and type(err) == "string" and err ~= "" then err else "Could not equip this ability."
		HUD.Toast({ Text = msg, Color = C.Red, Icon = "!" })
	end
end

-- Loadout (oben) ------------------------------------------------------------------------------

local function renderLoadout()
	clear(loadoutRow)
	table.clear(slotTiles)
	table.clear(slotStrokes)
	table.clear(slotIds)
	for slot = 1, 4 do
		local id = equippedId(slot)
		local def = Abilities.Get(id)
		slotIds[slot] = if def then id else ""

		local button = Make("TextButton", {
			Name = "Slot" .. slot,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Text = "",
			Position = UDim2.fromOffset((slot - 1) * (SLOT_W + SLOT_GAP), 0),
			Size = UDim2.fromOffset(SLOT_W, SLOT_H),
			Parent = loadoutRow,
		})
		local bump = Make("UIScale", { Parent = button })
		local back = UI.Inset({ Name = "Back", Size = UDim2.fromScale(1, 1), Radius = 12, Parent = button })
		local stroke = back:FindFirstChildOfClass("UIStroke")
		if stroke then
			slotStrokes[slot] = stroke :: UIStroke
		end

		local tilePos = UDim2.fromOffset((SLOT_W - SLOT_TILE) / 2, 8)
		if def then
			local tile = UI.AbilityTile({ AbilityId = id, Size = SLOT_TILE, Position = tilePos, Parent = button })
			tile.ZIndex = 2
			slotTiles[slot] = tile
			local pop = pendingPop
			if pop and pop.Slot == slot and pop.Id == id then
				pendingPop = nil
				UI.Pop(tile, 0.6, 0.35)
			end
		else
			-- leerer Slot: vertiefte Flaeche mit "+"
			local empty = Make("Frame", {
				Name = "Empty",
				BackgroundColor3 = Theme.Darken(C.PanelDark, 0.25),
				BorderSizePixel = 0,
				Position = tilePos,
				Size = UDim2.fromOffset(SLOT_TILE, SLOT_TILE - 4),
				ZIndex = 2,
				Parent = button,
			})
			UI.Corner(empty, 12)
			UI.Stroke(empty, C.Line, 2, 0.2)
			UI.Text({
				Text = "+",
				Font = F.Heading,
				TextSize = 36,
				TextColor3 = C.Muted,
				TextWrapped = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				Parent = empty,
			})
		end

		local defaultName = if def then string.upper(def.Name) else "EMPTY"
		local defaultColor = if def then C.Text else C.Muted
		local nameLabel = UI.Text({
			Name = "AbilityName",
			Text = defaultName,
			Font = F.Heading,
			TextSize = 14,
			TextScaled = true,
			TextWrapped = false,
			TextColor3 = defaultColor,
			Position = UDim2.fromOffset(6, SLOT_TILE + 13),
			Size = UDim2.new(1, -12, 0, 16),
			ZIndex = 3,
			Stroke = 1.5,
			Parent = button,
		})
		Make("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8, Parent = nameLabel })
		keyBadge(button, slot, UDim2.fromOffset(-6, -6), nil, 6)

		-- Leerer Slot + ausgewaehlte eigene Faehigkeit -> Klick ruestet sie hier aus
		local function canDropHere(): boolean
			local sel = selected
			return def == nil and sel ~= nil and State.Owned(sel) > 0
		end
		button.MouseEnter:Connect(function()
			UI.Tween(bump, 0.12, { Scale = 1.04 })
			UI.Sound("Hover")
			if canDropHere() then
				nameLabel.Text = "EQUIP HERE"
				nameLabel.TextColor3 = C.Green
			end
		end)
		button.MouseLeave:Connect(function()
			UI.Tween(bump, 0.15, { Scale = 1 })
			nameLabel.Text = defaultName
			nameLabel.TextColor3 = defaultColor
		end)
		button.Activated:Connect(function()
			UI.Sound("Click")
			if def then
				if selected == id then
					-- schon ausgewaehlt: nur kurz wippen (der Button selbst hat schon eine UIScale)
					local tile = slotTiles[slot]
					if tile and tile.Parent then
						UI.Pop(tile, 0.85, 0.25)
					end
				else
					select(id)
				end
			elseif canDropHere() then
				local sel = selected :: string
				task.spawn(equip, sel, slot)
			else
				HUD.Toast({ Text = "Pick an ability you own below, then choose a slot.", Color = C.Blue, Icon = "i" })
			end
		end)
	end
end

-- Sammlung (Raster) -------------------------------------------------------------------------

local function buildCell(def: any, owned: number, order: number)
	local locked = owned <= 0
	local cell = Make("TextButton", {
		Name = def.Id,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		LayoutOrder = order,
		Parent = gridScroll,
	})
	-- Goldrahmen fuer die aktuelle Auswahl (liegt hinter der Kachel)
	local ring = Make("Frame", {
		Name = "Ring",
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset((CELL_W - GRID_TILE) / 2 - 5, 0),
		Size = UDim2.fromOffset(GRID_TILE + 10, GRID_TILE + 10),
		Visible = false,
		ZIndex = 1,
		Parent = cell,
	})
	UI.Corner(ring, 18)
	UI.Stroke(ring, C.Ink, 2, 0)

	local tile = UI.AbilityTile({
		AbilityId = def.Id,
		Size = GRID_TILE,
		Locked = locked,
		Position = UDim2.fromOffset((CELL_W - GRID_TILE) / 2, 5),
		Parent = cell,
	})
	tile.ZIndex = 2
	local bump = Make("UIScale", { Parent = tile })

	local nameLabel = UI.Text({
		Name = "AbilityName",
		Text = string.upper(def.Name),
		Font = F.Heading,
		TextSize = 14,
		TextScaled = true,
		TextWrapped = false,
		TextColor3 = if locked then C.Muted else C.Text,
		Position = UDim2.fromOffset(2, GRID_TILE + 12),
		Size = UDim2.new(1, -4, 0, 16),
		ZIndex = 3,
		Stroke = 1.5,
		Parent = cell,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8, Parent = nameLabel })

	-- Anzahl (nur bei Duplikaten)
	if owned > 1 then
		pill(cell, "x" .. owned, C.Gold, {
			Position = UDim2.fromOffset((CELL_W + GRID_TILE) / 2 + 6, 0),
			AnchorPoint = Vector2.new(1, 0),
			Height = 20,
			TextSize = 13,
			ZIndex = 6,
		})
	end
	-- Cutscene-Markierung
	if def.Cutscene then
		pill(cell, "🎬", C.PurpleDark, {
			Position = UDim2.fromOffset((CELL_W - GRID_TILE) / 2 - 6, 0),
			Height = 20,
			TextSize = 11,
			MinWidth = 28,
			ZIndex = 6,
		})
	end
	-- Ausgeruestet: gruenes Tasten-Schild mit der Slot-Nummer
	local slot = equippedSlotOf(def.Id)
	if slot then
		keyBadge(cell, slot, UDim2.fromOffset((CELL_W - GRID_TILE) / 2 - 6, GRID_TILE - 16), C.Green, 6)
	end

	cell.MouseEnter:Connect(function()
		UI.Tween(bump, 0.12, { Scale = 1.07 })
		UI.Sound("Hover")
	end)
	cell.MouseLeave:Connect(function()
		UI.Tween(bump, 0.15, { Scale = 1 })
	end)
	cell.Activated:Connect(function()
		UI.Sound("Click")
		select(def.Id)
	end)
	gridCells[def.Id] = { Ring = ring, Tile = tile }
end

local function renderGrid()
	clear(gridScroll)
	table.clear(gridCells)
	local ownedCount, shown = 0, 0
	for i, def in sortedAbilities() do
		local owned = State.Owned(def.Id)
		if owned > 0 then
			ownedCount += 1
		end
		local visible = filter == "ALL" or (filter == "OWNED" and owned > 0) or (filter == "LOCKED" and owned <= 0)
		if visible then
			shown += 1
			buildCell(def, owned, i)
		end
	end
	local total = #Abilities.List
	collectBar.Set(if total > 0 then ownedCount / total else 0)
	collectBar.Label.Text = ownedCount .. " / " .. total .. " COLLECTED"
	gridEmpty.Visible = shown == 0
	gridEmpty.Text = if filter == "LOCKED" then "You own every ability. Legendary!" else "Nothing here yet. Open a crate to get abilities!"
end

local function setFilter(name: string)
	filter = name
	for n, b in filterButtons do
		UI.SetButtonStyle(b, if n == name then "Blue" else "Dark")
	end
	if window and window.IsOpen then
		renderGrid()
		updateSelectionVisuals()
	end
end

-- Detail-Karte (rechts) --------------------------------------------------------------------

renderDetails = function()
	clear(detailsBody)
	local def = Abilities.Get(selected)
	if not def then
		shownId = nil
		UI.Text({
			Text = "Select an ability to see its details.",
			Font = F.Heading,
			TextSize = 18,
			TextColor3 = C.Muted,
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -48, 1, 0),
			Parent = detailsBody,
		})
		return
	end
	local id = def.Id
	local changed = shownId ~= id
	shownId = id
	local rarity = Rarities.Get(def.Rarity)
	local owned = State.Owned(id)
	local locked = owned <= 0
	local slotNow = equippedSlotOf(id)
	local center = DETAIL_W / 2

	-- Kopfbereich in (abgedunkelter) Seltenheitsfarbe, Kachel steht auf einem Sockel
	local heroColor = if locked then C.GreyDark else Theme.Darken(rarity.Color, 0.52)
	local hero = Make("Frame", {
		Name = "Hero",
		BackgroundColor3 = heroColor,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, HERO_H),
		ZIndex = 1,
		Parent = detailsBody,
	})
	UI.Corner(hero, 14)
	-- untere Ecken eckig + dunkle Kante
	Make("Frame", {
		BackgroundColor3 = heroColor,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = hero,
	})
	Make("Frame", {
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, 3),
		ZIndex = 2,
		Parent = hero,
	})
	-- weiches Licht hinter der Kachel
	local light = Make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center, 92),
		Size = UDim2.fromOffset(150, 150),
		Parent = hero,
	})
	UI.Round(light)
	-- Sockel
	local pedestal = Make("Frame", {
		BackgroundColor3 = Theme.Darken(heroColor, 0.4),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center, 38 + HERO_TILE),
		Size = UDim2.fromOffset(152, 26),
		ZIndex = 2,
		Parent = hero,
	})
	UI.Round(pedestal)
	UI.Stroke(pedestal, C.Ink, 2, 0)
	local bigTile = UI.AbilityTile({
		AbilityId = id,
		Size = HERO_TILE,
		Locked = locked,
		Position = UDim2.fromOffset(center - HERO_TILE / 2, 38),
		Parent = hero,
	})
	bigTile.ZIndex = 3
	if changed then
		UI.Pop(bigTile, 0.7, 0.35)
	end

	-- Status-Schilder oben links / rechts
	local statusText = if locked then "LOCKED" elseif owned > 1 then "OWNED x" .. owned else "OWNED"
	pill(hero, statusText, C.Ink, {
		Position = UDim2.fromOffset(12, 12),
		Height = 26,
		TextSize = 14,
		Transparency = 0.25,
		ZIndex = 4,
	})
	if slotNow then
		pill(hero, "SLOT " .. slotNow, C.Green, {
			Position = UDim2.new(1, -12, 0, 12),
			AnchorPoint = Vector2.new(1, 0),
			Height = 26,
			TextSize = 14,
			ZIndex = 4,
		})
	end

	-- Seltenheits-Band (mit zwei dunkleren "Enden" dahinter)
	local ribbonColor = rarity.Color
	local ribbonW = math.max(150, math.ceil(textWidth(rarity.Name, 18, F.Heading)) + 52)
	for side = -1, 1, 2 do
		local tail = Make("Frame", {
			Name = "RibbonTail",
			BackgroundColor3 = Theme.Darken(ribbonColor, 0.4),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center + side * (ribbonW / 2 + 2), HERO_H + 6),
			Size = UDim2.fromOffset(36, 26),
			ZIndex = 4,
			Parent = detailsBody,
		})
		UI.Corner(tail, 6)
		UI.Stroke(tail, C.Ink, 2, 0)
	end
	local ribbon = Make("Frame", {
		Name = "Ribbon",
		BackgroundColor3 = ribbonColor,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center, HERO_H),
		Size = UDim2.fromOffset(ribbonW, 34),
		ZIndex = 5,
		Parent = detailsBody,
	})
	UI.Corner(ribbon, 8)
	UI.Stroke(ribbon, C.Ink, 2.5, 0)
	UI.Shade(ribbon)
	UI.Text({
		Text = rarity.Name,
		Font = F.Heading,
		TextSize = 18,
		TextWrapped = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Stroke = 2,
		StrokeColor = Theme.Darken(ribbonColor, 0.65),
		Parent = ribbon,
	})

	-- Name + Beschreibung
	local nameLabel = UI.Text({
		Name = "AbilityName",
		Text = string.upper(def.Name),
		Font = F.Heading,
		TextSize = 30,
		TextScaled = true,
		TextWrapped = false,
		Position = UDim2.fromOffset(16, HERO_H + 26),
		Size = UDim2.new(1, -32, 0, 34),
		Stroke = 2.5,
		Parent = detailsBody,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 16, Parent = nameLabel })
	UI.Text({
		Name = "Description",
		Text = def.Description,
		Font = F.Body,
		TextSize = 14,
		TextColor3 = C.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, HERO_H + 64),
		Size = UDim2.new(1, -32, 0, 60),
		Parent = detailsBody,
	})

	-- Werte
	local stats = Make("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, HERO_H + 134),
		Size = UDim2.fromOffset(INNER_W, 52),
		Parent = detailsBody,
	})
	UI.List(stats, true, 8, Enum.HorizontalAlignment.Center)
	local statW = if def.Cutscene then 96 else 120
	statPill(stats, "DAMAGE", fmtNumber(def.Damage), C.Red, statW, 1)
	statPill(stats, "COOLDOWN", fmtNumber(def.Cooldown) .. "s", C.Blue, statW, 2)
	if def.Cutscene then
		statPill(stats, "CUTSCENE", "YES", C.Purple, statW, 3)
	end

	if locked then
		-- Wie bekommt man die Faehigkeit?
		caption(detailsBody, "HOW TO UNLOCK", UDim2.fromOffset(16, CAPTION_Y), UDim2.fromOffset(INNER_W, 18))
		local info = UI.Inset({
			Name = "Unlock",
			Position = UDim2.fromOffset(16, ROW_Y),
			Size = UDim2.fromOffset(INNER_W, 52),
			Radius = 10,
			Parent = detailsBody,
		})
		local gold = hex(C.Gold)
		UI.Text({
			Text = if def.Exclusive
				then 'Exclusive ability. Only available in the <font color="' .. gold .. '">SHOP</font>.'
				else 'Drops from <font color="' .. gold .. '">CRATES</font>. Rarer crates give better odds.',
			Font = F.Bold,
			TextSize = 14,
			TextColor3 = C.SubText,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Parent = info,
		})
		local target = if def.Exclusive then "Shop" else "Crates"
		UI.Button({
			Name = "Unlock",
			Text = if def.Exclusive then "GO TO SHOP" else "OPEN CRATES",
			Style = if def.Exclusive then "Robux" else "Green",
			Size = UDim2.fromOffset(INNER_W, 56),
			Position = UDim2.fromOffset(16, ACTION_Y),
			TextSize = 24,
			Parent = detailsBody,
			OnClick = function()
				window:Close()
				-- laeuft ueber dieselbe Verdrahtung wie die HUD-Knoepfe (Main.client)
				HUD.MenuButtonPressed:Fire(target)
			end,
		})
		return
	end

	-- Ausruesten auf Slot 1-4
	caption(detailsBody, "EQUIP TO SLOT", UDim2.fromOffset(16, CAPTION_Y), UDim2.fromOffset(INNER_W, 18))
	local slotW = (INNER_W - 3 * 8) / 4
	for slot = 1, 4 do
		local isHere = slotNow == slot
		local b: TextButton
		b = UI.Button({
			Name = "Slot" .. slot,
			Text = "SLOT " .. slot,
			Style = if isHere then "Green" else "Blue",
			Size = UDim2.fromOffset(slotW, 52),
			Position = UDim2.fromOffset(16 + (slot - 1) * (slotW + 8), ROW_Y),
			TextSize = 16,
			Parent = detailsBody,
			OnClick = function()
				if isHere then
					UI.Pop(b, 0.9, 0.25)
					return
				end
				equip(id, slot)
			end,
		})
	end
	UI.Button({
		Name = "Preview",
		Text = "PREVIEW",
		Style = "Gold",
		Size = UDim2.fromOffset(INNER_W, 56),
		Position = UDim2.fromOffset(16, ACTION_Y),
		TextSize = 24,
		Shine = true,
		Parent = detailsBody,
		OnClick = function()
			if not player.Character then
				HUD.Toast({ Text = "Wait until your character has spawned.", Color = C.Blue, Icon = "i" })
				return
			end
			window:Close()
			task.wait(0.25)
			VFXController.Preview(id)
		end,
	})
end

-- Aufbau / Aktualisieren -------------------------------------------------------------------

-- Sinnvolle Startauswahl: erster belegter Slot, sonst erste eigene Faehigkeit
local function ensureSelection()
	if selected and Abilities.Get(selected) then
		return
	end
	selected = nil
	for slot = 1, 4 do
		local id = equippedId(slot)
		if Abilities.Get(id) then
			selected = id
			return
		end
	end
	local list = sortedAbilities()
	for _, def in list do
		if State.Owned(def.Id) > 0 then
			selected = def.Id
			return
		end
	end
	selected = if list[1] then list[1].Id else nil
end

local function refresh()
	if not window or not window.IsOpen then
		return
	end
	ensureSelection()
	renderLoadout()
	renderGrid()
	renderDetails()
	updateSelectionVisuals()
end

function Inventory.Open()
	window:Open()
	refresh()
end

function Inventory.Init()
	window = UI.Window({ Title = "ABILITIES", Size = Vector2.new(WIN_W, WIN_H), Name = "Inventory", Color = C.Blue })
	local content = window.Content

	local left = Make("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PAD, TOP),
		Size = UDim2.fromOffset(LEFT_W, COLUMN_H),
		Parent = content,
	})

	-- LOADOUT ------------------------------------------------------------
	local loadout = UI.Card({
		Name = "Loadout",
		Size = UDim2.fromOffset(LEFT_W, LOADOUT_H),
		Radius = 14,
		Parent = left,
	})
	local rowW = 4 * SLOT_W + 3 * SLOT_GAP
	local labelW = LEFT_W - rowW - 16 * 2 - 12
	UI.Text({
		Text = "LOADOUT",
		Font = F.Heading,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(16, 18),
		Size = UDim2.fromOffset(labelW, 32),
		Stroke = 2,
		Parent = loadout,
	})
	UI.Text({
		Text = if HAS_KEYBOARD then "Your abilities in battle. Use them with keys 1-4." else "Your four abilities in battle.",
		Font = F.Body,
		TextSize = 13,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.fromOffset(labelW, 56),
		Parent = loadout,
	})
	loadoutRow = Make("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(LEFT_W - 16 - rowW, (LOADOUT_H - SLOT_H) / 2),
		Size = UDim2.fromOffset(rowW, SLOT_H),
		Parent = loadout,
	})

	-- COLLECTION-Kopfzeile -----------------------------------------------------------
	local headerY = LOADOUT_H + 16
	local filterW, filterGap = 80, 8
	local filtersX = LEFT_W - (#FILTERS * filterW + (#FILTERS - 1) * filterGap)
	local titleW = math.ceil(textWidth("COLLECTION", 24, F.Heading)) + 4
	UI.Text({
		Text = "COLLECTION",
		Font = F.Heading,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		Position = UDim2.fromOffset(4, headerY),
		Size = UDim2.fromOffset(titleW, 40),
		Stroke = 2,
		Parent = left,
	})
	-- Fortschrittsbalken "8 / 15 COLLECTED" direkt hinter dem Titel
	local barX = 4 + titleW + 12
	local barW = math.clamp(filtersX - 24 - barX, 150, 210)
	collectBar = UI.ProgressBar({
		Size = UDim2.fromOffset(barW, 28),
		Position = UDim2.fromOffset(barX, headerY + 6),
		Color = C.Gold,
		Text = "",
		Parent = left,
	})
	collectBar.Label.TextWrapped = false
	collectBar.Label.TextSize = 15
	collectBar.Set(0, true)

	for i, name in FILTERS do
		filterButtons[name] = UI.Button({
			Name = "Filter" .. name,
			Text = name,
			Style = if name == filter then "Blue" else "Dark",
			Size = UDim2.fromOffset(filterW, 36),
			Position = UDim2.fromOffset(filtersX + (i - 1) * (filterW + filterGap), headerY + 2),
			TextSize = 15,
			Lip = 4,
			Parent = left,
			OnClick = function()
				setFilter(name)
			end,
		})
	end

	-- Raster ---------------------------------------------------------------------------
	local gridY = headerY + 52
	local gridBox = UI.Inset({
		Name = "Collection",
		Position = UDim2.fromOffset(0, gridY),
		Size = UDim2.fromOffset(LEFT_W, COLUMN_H - gridY),
		Radius = 12,
		Parent = left,
	})
	gridScroll = UI.Scroll(gridBox, {
		Name = "Grid",
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.new(1, -16, 1, -20),
		ScrollBarThickness = 6,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	})
	Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL_W, CELL_H),
		CellPadding = UDim2.fromOffset(12, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gridScroll,
	})
	gridEmpty = UI.Text({
		Name = "Empty",
		Text = "",
		Font = F.Heading,
		TextSize = 18,
		TextColor3 = C.Muted,
		Visible = false,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -48, 1, 0),
		Parent = gridBox,
	})

	-- DETAILS --------------------------------------------------------------------------
	local detailsCard = UI.Card({
		Name = "Details",
		Position = UDim2.fromOffset(WIN_W - PAD - DETAIL_W, TOP),
		Size = UDim2.fromOffset(DETAIL_W, COLUMN_H),
		Radius = 14,
		Parent = content,
	})
	detailsBody = Make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = detailsCard,
	})

	State.ProfileChanged:Connect(refresh)
end

function Inventory.Start() end

return Inventory
