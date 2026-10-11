--!strict
-- Sound-Bibliothek.
-- Standardmaessig werden Sounds benutzt, die im Roblox-Client eingebaut sind (rbxasset://).
-- TIPP: Ersetze die IDs durch eigene Sounds aus dem Creator Store ("rbxassetid://123..."),
-- um den Sound noch epischer zu machen. Alles andere passt sich automatisch an.

export type SoundDef = { Id: string, Volume: number, Pitch: number? }

local S: { [string]: SoundDef } = {
	-- UI
	Hover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Pitch = 1.6 },
	Click = { Id = "rbxasset://sounds/button.wav", Volume = 0.5, Pitch = 1.1 },
	Open = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 0.8 },
	Close = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 0.6 },
	Coins = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.5 },
	Error = { Id = "rbxasset://sounds/button.wav", Volume = 0.5, Pitch = 0.5 },
	Countdown = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Pitch = 1 },
	Fight = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.9, Pitch = 0.8 },
	Victory = { Id = "rbxasset://sounds/victory.wav", Volume = 0.8, Pitch = 1 },
	Whoosh = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.5, Pitch = 1.2 },
	Tutorial = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Pitch = 1.25 },

	-- Kampf
	Swing = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.45, Pitch = 1.3 },
	Punch = { Id = "rbxasset://sounds/collide.wav", Volume = 0.7, Pitch = 1.2 },
	HeavyPunch = { Id = "rbxasset://sounds/collide.wav", Volume = 1, Pitch = 0.75 },
	Block = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.6, Pitch = 1.6 },
	GuardBreak = { Id = "rbxasset://sounds/glassbreak.wav", Volume = 0.8, Pitch = 1.1 },
	Dash = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.5, Pitch = 1.5 },

	-- Faehigkeiten
	Fire = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.7, Pitch = 0.9 },
	Explosion = { Id = "rbxasset://sounds/collide.wav", Volume = 1, Pitch = 0.45 },
	BigExplosion = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 1, Pitch = 0.45 },
	Rumble = { Id = "rbxasset://sounds/Launching rocket.wav", Volume = 0.6, Pitch = 0.5 },
	Wind = { Id = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.8, Pitch = 1 },
	Ice = { Id = "rbxasset://sounds/glassbreak.wav", Volume = 0.6, Pitch = 1.4 },
	Electric = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.5 },
	Thunder = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 1, Pitch = 0.35 },
	Water = { Id = "rbxasset://sounds/splat.wav", Volume = 0.8, Pitch = 0.7 },
	Slash = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.8, Pitch = 0.9 },
	Shadow = { Id = "rbxasset://sounds/HalloweenGhost.wav", Volume = 0.6, Pitch = 1.3 },
	Charge = { Id = "rbxasset://sounds/Launching rocket.wav", Volume = 0.6, Pitch = 1.2 },
	Holy = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 0.3 },
	Void = { Id = "rbxasset://sounds/HalloweenGhost.wav", Volume = 0.9, Pitch = 0.4 },
	Impact = { Id = "rbxasset://sounds/collide.wav", Volume = 1, Pitch = 0.6 },

	-- Kisten
	CrateLand = { Id = "rbxasset://sounds/collide.wav", Volume = 1, Pitch = 0.5 },
	CrateTap = { Id = "rbxasset://sounds/collide.wav", Volume = 0.8, Pitch = 1.4 },
	CrateUpgrade = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 1.2 },
	CrateOpen = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.8, Pitch = 1.3 },
	Reveal = { Id = "rbxasset://sounds/victory.wav", Volume = 0.7, Pitch = 1.1 },
	MythicReveal = { Id = "rbxasset://sounds/HalloweenGhost.wav", Volume = 0.9, Pitch = 0.6 },
}

return S
