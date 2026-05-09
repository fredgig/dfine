local Instance = require("@lune/roblox").Instance
local D = require("@dfine")

local assert: (boolean, string?) -> () = assert :: any

-- ---------------------------------------------------------------------------
-- Definitions
--
-- Hierarchy:
--   Vehicle
--   ├─ Car            (extends Vehicle)
--   │  └─ SportsCar    (extends Car — multi-level)
--   ├─ Motorcycle     (extends Vehicle — sibling to Car)
--   ├─ Boat           (extends Vehicle — sibling to Car)
--   └─ AmphibiousCar  (extends Car + Boat — multiple inheritance)
-- ---------------------------------------------------------------------------

local Vehicle = D.fine {
	[D.Name] = "Vehicle",

	Color = "white",
	TopSpeed = 60,
	Wheels = 4,
	Owner = D.Nil :: Player?,

	Honk = function(self): string
		return "Beep!"
	end,
}

local Car = D.fine {
	[D.Name] = "Car",
	[D.Container] = Instance.new("Model"),
	[D.Extends] = { Vehicle },

	Color = "red",
	TopSpeed = 120,

	Drive = function(self, distance: number): string
		return `drove {distance}m at {self.TopSpeed}km/h`
	end,

	Server_Refuel = function(self): string
		return "tank full"
	end,

	Client_PlayHorn = function(self): string
		return self:Honk()
	end,
}

local Motorcycle = D.fine {
	[D.Name] = "Motorcycle",
	[D.Container] = Instance.new("Model"),
	[D.Extends] = { Vehicle },

	Wheels = 2,
	TopSpeed = 80,

	Wheelie = function(self): string
		return `wheelie at {self.TopSpeed}km/h`
	end,
}

local SportsCar = D.fine {
	[D.Name] = "SportsCar",
	[D.Container] = Instance.new("Model"),
	[D.Extends] = { Car },

	Color = "black",
	TopSpeed = 300,

	Boost = function(self): string
		return `boosting to {self.TopSpeed}km/h`
	end,

	-- Overrides Car.Drive to demonstrate method override.
	Drive = function(self, distance: number): string
		return `flew {distance}m at {self.TopSpeed}km/h`
	end,
}

local Boat = D.fine {
	[D.Name] = "Boat",
	[D.Container] = Instance.new("Model"),
	[D.Extends] = { Vehicle },

	Color = "blue",
	Wheels = 0,
	TopSpeed = 40,
	HasHull = true,

	Sail = function(self, distance: number): string
		return `sailed {distance}m at {self.TopSpeed}km/h`
	end,

	Server_DropAnchor = function(self): string
		return "anchor down"
	end,
}

-- AmphibiousCar drives on land and sails on water. It pulls in both surfaces'
-- methods. When Car and Boat declare the same property (Color, TopSpeed, etc.)
-- the *first* parent in [D.Extends] wins — here Car beats Boat for overlap.
local AmphibiousCar = D.fine {
	[D.Name] = "AmphibiousCar",
	[D.Container] = Instance.new("Model"),
	[D.Extends] = { Car, Boat },

	SwitchMode = function(self, mode: string): string
		return `switched to {mode} mode`
	end,
}

-- ---------------------------------------------------------------------------
-- Vehicle (parent on its own)
-- ---------------------------------------------------------------------------

local v = D.new(Vehicle)
assert(v.Color == "white", `Vehicle.Color: got {v.Color}`)
assert(v.TopSpeed == 60, `Vehicle.TopSpeed: got {v.TopSpeed}`)
assert(v.Wheels == 4, `Vehicle.Wheels: got {v.Wheels}`)
assert(v.Owner == nil, `Vehicle.Owner: got {v.Owner}`)
assert(v:Honk() == "Beep!", `Vehicle:Honk(): got {v:Honk()}`)
-- No [D.Container] declared, so default Folder is used.
assert(v.ClassName == "Folder", `Vehicle default container: got {v.ClassName}`)

-- ---------------------------------------------------------------------------
-- Car — defaults, inheritance, methods
-- ---------------------------------------------------------------------------

local car = D.new(Car)

assert(car.Color == "red", `Car.Color override: got {car.Color}`)
assert(car.TopSpeed == 120, `Car.TopSpeed override: got {car.TopSpeed}`)
assert(car.Wheels == 4, `Car.Wheels inherited: got {car.Wheels}`)
assert(car.Owner == nil, `Car.Owner via D.Nil: got {car.Owner}`)

assert(car.Name == "Model", `Car container Name: got {car.Name}`)
assert(typeof(car:GetChildren()) == "table", `GetChildren returns table`)
assert(#car:GetChildren() == 0, `GetChildren empty: got {#car:GetChildren()}`)

assert(rawget(car, "Color") == nil, `Color initially off-wrapper: got {rawget(car, "Color")}`)
assert(rawget(car, "Wheels") == nil, `Wheels initially off-wrapper: got {rawget(car, "Wheels")}`)

assert(car:Drive(50) == "drove 50m at 120km/h", `Car:Drive(50): got {car:Drive(50)}`)
assert(car:Honk() == "Beep!", `Car:Honk() inherited: got {car:Honk()}`)
assert(car:Refuel() == "tank full", `Car:Refuel() via Server_ prefix: got {car:Refuel()}`)
assert(car:PlayHorn() == "Beep!", `Car:PlayHorn() → inherited Honk: got {car:PlayHorn()}`)

-- ---------------------------------------------------------------------------
-- Car — property writes
-- ---------------------------------------------------------------------------

car.Color = "blue"
assert(car.Color == "blue", `Car.Color after set: got {car.Color}`)
assert(rawget(car, "Color") == "blue", `Color override on wrapper: got {rawget(car, "Color")}`)

-- Resetting to default value does NOT clear an already-materialized override
-- (Lua only fires __newindex for missing keys). Documented limitation.
car.Color = "red"
assert(car.Color == "red", `Car.Color after reset: got {car.Color}`)
assert(rawget(car, "Color") == "red", `Override slot stays: got {rawget(car, "Color")}`)

car.Wheels = 6
assert(car.Wheels == 6, `Inherited Wheels override: got {car.Wheels}`)
assert(rawget(car, "Wheels") == 6, `Wheels stored on wrapper: got {rawget(car, "Wheels")}`)

car.Color ..= " (mod)"
assert(car.Color == "red (mod)", `Compound assign Color: got {car.Color}`)

car.Name = "MyCar"
assert(car.Name == "MyCar", `Name fall-through write: got {car.Name}`)
assert(rawget(car, "Name") == nil, `Name off-wrapper: got {rawget(car, "Name")}`)

car.Name ..= " v2"
assert(car.Name == "MyCar v2", `Name compound assign: got {car.Name}`)

-- ---------------------------------------------------------------------------
-- Car — methods are write-protected (own and inherited)
-- ---------------------------------------------------------------------------

local ok, err = pcall(function()
	(car :: any).Drive = function() end
end)
assert(not ok, "Overwriting Drive should error")
assert(typeof(err) == "string" and err:find("Drive") ~= nil, `Error mentions Drive: got {err}`)

local ok2 = pcall(function()
	(car :: any).Honk = function() end
end)
assert(not ok2, "Overwriting inherited Honk should error")

-- ---------------------------------------------------------------------------
-- Motorcycle — sibling extension of Vehicle
-- ---------------------------------------------------------------------------

local moto = D.new(Motorcycle)

-- Own overrides
assert(moto.Wheels == 2, `Motorcycle.Wheels: got {moto.Wheels}`)
assert(moto.TopSpeed == 80, `Motorcycle.TopSpeed: got {moto.TopSpeed}`)

-- Inherited from Vehicle (untouched)
assert(moto.Color == "white", `Motorcycle.Color inherited: got {moto.Color}`)
assert(moto.Owner == nil, `Motorcycle.Owner inherited: got {moto.Owner}`)

-- Own method
assert(moto:Wheelie() == "wheelie at 80km/h", `Motorcycle:Wheelie(): got {moto:Wheelie()}`)
-- Inherited method
assert(moto:Honk() == "Beep!", `Motorcycle:Honk() inherited: got {moto:Honk()}`)

-- Sibling isolation: Motorcycle does not get Car's methods.
local hasRefuel = pcall(function() return (moto :: any):Refuel() end)
assert(not hasRefuel, "Motorcycle should not inherit Car's Refuel")

local hasDrive = pcall(function() return (moto :: any):Drive(1) end)
assert(not hasDrive, "Motorcycle should not inherit Car's Drive")

-- ---------------------------------------------------------------------------
-- SportsCar — multi-level inheritance (SportsCar → Car → Vehicle)
-- ---------------------------------------------------------------------------

local sc = D.new(SportsCar)

-- Own overrides
assert(sc.Color == "black", `SportsCar.Color: got {sc.Color}`)
assert(sc.TopSpeed == 300, `SportsCar.TopSpeed: got {sc.TopSpeed}`)

-- Inherited from Car (which itself doesn't override these — they came from Vehicle)
assert(sc.Wheels == 4, `SportsCar.Wheels (Vehicle via Car): got {sc.Wheels}`)
assert(sc.Owner == nil, `SportsCar.Owner (Vehicle via Car): got {sc.Owner}`)

-- Own method
assert(sc:Boost() == "boosting to 300km/h", `SportsCar:Boost(): got {sc:Boost()}`)

-- Method override: SportsCar.Drive shadows Car.Drive.
-- self.TopSpeed correctly resolves to SportsCar's override (300).
assert(sc:Drive(10) == "flew 10m at 300km/h", `SportsCar:Drive(10): got {sc:Drive(10)}`)

-- Inherited method from Car (Server_Refuel)
assert(sc:Refuel() == "tank full", `SportsCar:Refuel() via Car: got {sc:Refuel()}`)

-- Deeply inherited method from Vehicle (Honk)
assert(sc:Honk() == "Beep!", `SportsCar:Honk() via Vehicle: got {sc:Honk()}`)

-- Inherited Car.Client_PlayHorn calling self:Honk() resolves through
-- SportsCar's MRO and finds Vehicle.Honk.
assert(sc:PlayHorn() == "Beep!", `SportsCar:PlayHorn() chained: got {sc:PlayHorn()}`)

-- Method protection still applies across the chain.
local ok3 = pcall(function()
	(sc :: any).Boost = function() end
end)
assert(not ok3, "Overwriting SportsCar.Boost should error")

local ok4 = pcall(function()
	(sc :: any).Drive = function() end
end)
assert(not ok4, "Overwriting overridden Drive should error")

local ok5 = pcall(function()
	(sc :: any).Honk = function() end
end)
assert(not ok5, "Overwriting deeply inherited Honk should error")

-- ---------------------------------------------------------------------------
-- Boat — sibling extension of Vehicle that overrides shared properties
-- ---------------------------------------------------------------------------

local boat = D.new(Boat)

assert(boat.Color == "blue", `Boat.Color override: got {boat.Color}`)
assert(boat.Wheels == 0, `Boat.Wheels override: got {boat.Wheels}`)
assert(boat.TopSpeed == 40, `Boat.TopSpeed override: got {boat.TopSpeed}`)
assert(boat.HasHull == true, `Boat.HasHull own: got {tostring(boat.HasHull)}`)
assert(boat.Owner == nil, `Boat.Owner inherited via D.Nil: got {boat.Owner}`)

assert(boat:Sail(20) == "sailed 20m at 40km/h", `Boat:Sail(20): got {boat:Sail(20)}`)
assert(boat:Honk() == "Beep!", `Boat:Honk() inherited: got {boat:Honk()}`)
assert(boat:DropAnchor() == "anchor down", `Boat:DropAnchor() via Server_ prefix: got {boat:DropAnchor()}`)

-- Boat does not inherit Car's surface
local boatNoDrive = pcall(function() return (boat :: any):Drive(1) end)
assert(not boatNoDrive, "Boat should not inherit Car's Drive")
local boatNoRefuel = pcall(function() return (boat :: any):Refuel() end)
assert(not boatNoRefuel, "Boat should not inherit Car's Refuel")

-- ---------------------------------------------------------------------------
-- AmphibiousCar — multiple inheritance (Car + Boat)
--
-- Both parents declare Color, TopSpeed, Wheels, etc. The ordering in
-- [D.Extends] = { Car, Boat } means Car's values win on overlap; Boat
-- contributes its unique fields (HasHull, Sail, DropAnchor).
-- ---------------------------------------------------------------------------

local amph = D.new(AmphibiousCar)

-- Conflict winners: Car beats Boat because it appears first in [D.Extends]
assert(amph.Color == "red", `AmphibiousCar.Color (Car wins): got {amph.Color}`)
assert(amph.TopSpeed == 120, `AmphibiousCar.TopSpeed (Car wins): got {amph.TopSpeed}`)
assert(amph.Wheels == 4, `AmphibiousCar.Wheels (Car wins): got {amph.Wheels}`)

-- Unique to Boat: makes it through cleanly
assert(amph.HasHull == true, `AmphibiousCar.HasHull (from Boat): got {tostring(amph.HasHull)}`)

-- Inherited from Vehicle (via either parent)
assert(amph.Owner == nil, `AmphibiousCar.Owner: got {amph.Owner}`)

-- Methods from Car
assert(amph:Drive(50) == "drove 50m at 120km/h", `AmphibiousCar:Drive(50): got {amph:Drive(50)}`)
assert(amph:Refuel() == "tank full", `AmphibiousCar:Refuel() (Car): got {amph:Refuel()}`)
assert(amph:PlayHorn() == "Beep!", `AmphibiousCar:PlayHorn() (Car) → Honk: got {amph:PlayHorn()}`)

-- Methods from Boat
assert(amph:Sail(15) == "sailed 15m at 120km/h", `AmphibiousCar:Sail(15) at Car's TopSpeed: got {amph:Sail(15)}`)
assert(amph:DropAnchor() == "anchor down", `AmphibiousCar:DropAnchor() (Boat): got {amph:DropAnchor()}`)

-- Method from Vehicle (deepest ancestor)
assert(amph:Honk() == "Beep!", `AmphibiousCar:Honk() (Vehicle): got {amph:Honk()}`)

-- Own method
assert(amph:SwitchMode("water") == "switched to water mode", `AmphibiousCar:SwitchMode("water"): got {amph:SwitchMode("water")}`)

-- Method protection covers every parent's contributions
local ampOk1 = pcall(function() (amph :: any).Drive = function() end end)
assert(not ampOk1, "AmphibiousCar.Drive (from Car) should be write-protected")

local ampOk2 = pcall(function() (amph :: any).Sail = function() end end)
assert(not ampOk2, "AmphibiousCar.Sail (from Boat) should be write-protected")

local ampOk3 = pcall(function() (amph :: any).Honk = function() end end)
assert(not ampOk3, "AmphibiousCar.Honk (from Vehicle) should be write-protected")

local ampOk4 = pcall(function() (amph :: any).SwitchMode = function() end end)
assert(not ampOk4, "AmphibiousCar.SwitchMode (own) should be write-protected")

-- ---------------------------------------------------------------------------
-- Instance independence across multiple kinds and sibling classes
-- ---------------------------------------------------------------------------

local car2 = D.new(Car)
car2.Color = "green"
car2.Name = "Car2"

assert(car.Color == "red (mod)", `car isolation from car2: got {car.Color}`)
assert(car.Name == "MyCar v2", `car.Name isolation: got {car.Name}`)
assert(car2.Color == "green", `car2.Color: got {car2.Color}`)
assert(car2.Name == "Car2", `car2.Name: got {car2.Name}`)

-- Mutating sc/moto doesn't leak into Car instances.
sc.Color = "yellow"
moto.Wheels = 3
assert(car.Color == "red (mod)", `car unaffected by sc: got {car.Color}`)
assert(car2.Wheels == 4, `car2.Wheels unaffected by moto: got {car2.Wheels}`)
assert(sc.Color == "yellow", `sc.Color updated: got {sc.Color}`)
assert(moto.Wheels == 3, `moto.Wheels updated: got {moto.Wheels}`)
