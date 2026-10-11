-- Inventar: alle Faehigkeiten (Sammlung), Details, Ausruesten auf Slot 1-4, VFX-Vorschau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local WHITE = Color3.new(1, 1, 1)

local window: UI.Window
local equippedRow: Frame
local grid: ScrollingFrame
local details: Frame
local counter: TextLabel
local selected: string? = nil

local function sortedAbilities(): { any }
	local list = table.clone(Abilities.List)
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

local renderDetails: (string?) -> ()

local function abilityCard(def: any, parent: Instance, size: number, order: number, onClick: () -> ()): TextButton
	local owned = State.Owned(def.Id)
	local rarity = Rarities.Get(def.Rarity)
	local card = Make("TextButton", {
		Name = def.Id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(size, size + 26),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Corner(card, 16)
	UI.Gradient(card, if owned > 0 then ColorSequence.new(rarity.Dark, Color3.fromRGB(14, 11, 30)) else ColorSequence.new(Color3.fromRGB(22, 20, 34)), 120)
	local stroke = UI.Stroke(card, if owned > 0 then rarity.Color else C.Muted, if selected == def.Id then 4 else 2, if owned > 0 then 0 else 0.6)
	local icon = UI.Text({
		Text = if owned > 0 then def.Icon else "❔",
		TextSize = size * 0.45,
		Size = UDim2.new(1, 0, 0, size * 0.75),
		TextTransparency = if owned > 0 then 0 else 0.5,
		Parent = card,
	})
	local _ = icon
	UI.Text({
		Text = if owned > 0 then string.upper(def.Name) else "???",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = if owned > 0 then WHITE else C.Muted,
		Position = UDim2.new(0, 4, 0, size * 0.72),
		Size = UDim2.new(1, -8, 0, 20),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	UI.Text({
		Text = rarity.Name,
		Font = Theme.Fonts.Title,
		TextSize = 10,
		TextColor3 = rarity.Color,
		Position = UDim2.new(0, 0, 0, size * 0.72 + 20),
		Size = UDim2.new(1, 0, 0, 14),
		TextTransparency = if owned > 0 then 0 else 0.5,
		Parent = card,
	})
	if owned > 1 then
		UI.Text({
			Text = "x" .. owned,
			Font = Theme.Fonts.Title,
			TextSize = 14,
			TextColor3 = C.Gold,
			Position = UDim2.new(1, -40, 0, 4),
			Size = UDim2.fromOffset(36, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end
	if def.Cutscene then
		UI.Text({ Text = "🎬", TextSize = 16, Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(20, 20), Parent = card })
	end
	local scale = Make("UIScale", { Parent = card })
	card.MouseEnter:Connect(function()
		UI.Tween(scale, 0.15, { Scale = 1.06 })
		UI.Sound("Hover")
	end)
	card.MouseLeave:Connect(function()
		UI.Tween(scale, 0.2, { Scale = 1 })
	end)
	card.Activated:Connect(function()
		UI.Sound("Click")
		onClick()
	end)
	local __ = stroke
	return card
end

local function renderEquipped()
	for _, c in equippedRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local profile = State.Profile
	for slot = 1, 4 do
		local id = if profile then profile.Equipped[slot] else ""
		local def = Abilities.Get(id)
		local holder = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 132), LayoutOrder = slot, Parent = equippedRow })
		UI.Text({
			Text = "KEY " .. slot,
			Font = Theme.Fonts.Title,
			TextSize = 13,
			TextColor3 = C.Cyan,
			Size = UDim2.new(1, 0, 0, 16),
			Parent = holder,
		})
		local inner = Make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 18), Size = UDim2.fromOffset(102, 112), Parent = holder })
		if def then
			abilityCard(def, inner, 90, slot, function()
				renderDetails(def.Id)
			end).Position = UDim2.fromOffset(6, 0)
		else
			local empty = Make("Frame", {
				BackgroundColor3 = Color3.fromRGB(16, 13, 32),
				Position = UDim2.fromOffset(6, 0),
				Size = UDim2.fromOffset(90, 116),
				Parent = inner,
			})
			UI.Corner(empty, 16)
			UI.Stroke(empty, C.Muted, 2, 0.5)
			UI.Text({ Text = "EMPTY", TextSize = 14, Font = Theme.Fonts.Title, TextColor3 = C.Muted, Size = UDim2.fromScale(1, 1), Parent = empty })
		end
	end
end

local function renderGrid()
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local ownedCount = 0
	for i, def in sortedAbilities() do
		if State.Owned(def.Id) > 0 then
			ownedCount += 1
		end
		abilityCard(def, grid, 96, i, function()
			renderDetails(def.Id)
		end)
	end
	counter.Text = "COLLECTION  " .. ownedCount .. " / " .. #Abilities.List
end

renderDetails = function(id: string?)
	selected = id
	for _, c in details:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local def = Abilities.Get(id)
	if not def then
		UI.Text({
			Text = "Select an ability to see its details.",
			Font = Theme.Fonts.Body,
			TextSize = 16,
			TextColor3 = C.SubText,
			Size = UDim2.fromScale(1, 1),
			Parent = details,
		})
		return
	end
	local rarity = Rarities.Get(def.Rarity)
	local owned = State.Owned(def.Id)
	local iconBox = Make("Frame", {
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(130, 130),
		Parent = details,
	})
	UI.Corner(iconBox, 22)
	UI.Gradient(iconBox, ColorSequence.new(rarity.Color, rarity.Dark), 135)
	local st = UI.Stroke(iconBox, WHITE, 3, 0.1)
	UI.Animate(UI.Gradient(st, rarity.Gradient, 0), 120, "Rotate")
	UI.Text({ Text = if owned > 0 then def.Icon else "🔒", TextSize = 72, Size = UDim2.fromScale(1, 1), Parent = iconBox })
	UI.Pop(iconBox, 0.6, 0.35)
	UI.Text({
		Text = "✦ " .. rarity.Name .. " ✦",
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = rarity.Color,
		Position = UDim2.fromOffset(0, 148),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = details,
	})
	local name = UI.Text({
		Text = string.upper(def.Name),
		Font = Theme.Fonts.Title,
		TextSize = 28,
		Position = UDim2.fromOffset(0, 168),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = details,
	})
	UI.Gradient(name, ColorSequence.new(WHITE, rarity.Glow), 90)
	UI.Text({
		Text = def.Description,
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = C.SubText,
		Position = UDim2.fromOffset(10, 204),
		Size = UDim2.new(1, -20, 0, 62),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = details,
	})
	UI.Text({
		Text = "⚔️ " .. def.Damage .. " DMG    ⏱ " .. def.Cooldown .. "s" .. (if def.Cutscene then "    🎬 CUTSCENE" else ""),
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		Position = UDim2.fromOffset(0, 268),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = details,
	})
	if owned > 0 then
		local slotRow = Make("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 298),
			Size = UDim2.new(1, -20, 0, 46),
			Parent = details,
		})
		UI.List(slotRow, true, 8, Enum.HorizontalAlignment.Center)
		for slot = 1, 4 do
			local isHere = State.Profile and State.Profile.Equipped[slot] == def.Id
			UI.Button({
				Text = if isHere then "✓ " .. slot else "SLOT " .. slot,
				Style = if isHere then "Success" else "Secondary",
				Size = UDim2.fromOffset(72, 44),
				TextSize = 15,
				LayoutOrder = slot,
				Parent = slotRow,
				OnClick = function()
					local ok, err = Net.Function("EquipAbility"):InvokeServer(def.Id, slot)
					if ok then
						State.TutorialEvent:Fire("Equipped", def.Id)
					else
						HUD.Toast({ Text = err or "Could not equip.", Color = C.Danger, Icon = "⚠️" })
					end
				end,
			})
		end
		UI.Button({
			Text = "▶ PREVIEW",
			Style = "Primary",
			Size = UDim2.new(1, -20, 0, 50),
			Position = UDim2.fromOffset(10, 352),
			TextSize = 20,
			Parent = details,
			OnClick = function()
				window:Close()
				task.wait(0.25)
				VFXController.Preview(def.Id)
			end,
		})
	else
		UI.Text({
			Text = if def.Exclusive then "🔒 Exclusive – available in the 💎 SHOP" else "🔒 Not unlocked yet – find it in 🎁 CRATES",
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextColor3 = C.Gold,
			Position = UDim2.fromOffset(10, 304),
			Size = UDim2.new(1, -20, 0, 40),
			Parent = details,
		})
	end
end

local function refresh()
	if not window.IsOpen then
		return
	end
	renderEquipped()
	renderGrid()
	renderDetails(selected)
end

function Inventory.Open()
	window:Open()
	refresh()
end

function Inventory.Init()
	window = UI.Window({ Title = "ABILITIES", Icon = "🎒", Size = Vector2.new(1040, 640), Name = "Inventory" })
	local content = window.Content
	equippedRow = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 6),
		Size = UDim2.new(1, -360, 0, 136),
		Parent = content,
	})
	UI.List(equippedRow, true, 10, Enum.HorizontalAlignment.Left)
	counter = UI.Text({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(26, 146),
		Size = UDim2.fromOffset(400, 22),
		Parent = content,
	})
	grid = UI.Scroll(content, {
		Position = UDim2.fromOffset(20, 172),
		Size = UDim2.new(1, -370, 1, -186),
	})
	UI.Padding(grid, 6)
	Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(96, 122),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	details = UI.Panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 6),
		Size = UDim2.new(0, 320, 1, -20),
		Radius = 14,
		Parent = content,
	})
	State.ProfileChanged:Connect(refresh)
end

function Inventory.Start() end

return Inventory
