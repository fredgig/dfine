type EntityConfigBase = {
	[string]: any,
}

local Instance = require("@lune/roblox").Instance

local entities = {}

local Nil = "DEFIN_NIL"
local Name = "DEFIN_NAME"
local Container = "DEFIN_CONTAINER"
local Extends = "DEFIN_EXTENDS"

function cloneValue(value)
	if type(value) == "table" then
		local _table = {}
		
		for index, _value in pairs(value) do
			_table[index] = cloneValue(_value)
		end
		
		return _table
	elseif typeof(value) == "Instance" then
		local clone = value:Clone()
		clone.Parent = value.Parent
		
		return clone
	else
		return value
	end
end

function compareValues(value1, value2)
	if type(value1) ~= type(value2) then
		return false
	elseif type(value1) == "table" then
		for index, _value in pairs(value1) do
			if not compareValues(_value, value2[index]) then
				return false
			end
		end
		
		for index, _value in pairs(value2) do
			if not compareValues(_value, value1[index]) then
				return false
			end
		end
		
		return true
	else
		return value1 == value2
	end
end

local D = {
	Nil = Nil,
	Name = Name,
	Container = Container,
	Extends = Extends,

	fine = function<T>(config: EntityConfigBase & T): T
		local base = config :: EntityConfigBase
		base[Container] = base[Container] or Instance.new("Folder")

		local extends = base[Extends] or {}

		base[Extends] = extends

		for _, parent in ipairs(extends) do
			for index, value in pairs(parent) do
				if index == Extends then
					for _, grandparent in ipairs(value) do
						table.insert(extends, grandparent)
					end
				elseif index ~= Name and index ~= Container and base[index] == nil then
					base[index] = value
				end
			end
		end

		return config
	end,

	new = function<E>(config: EntityConfigBase & { Entity: E? }): E
		local container = (config[Container] :: Instance):Clone()

		local entity = {}

		entities[container] = entity

		setmetatable(entity :: any, {
			__index = function(_, index)
				local value = config[`Server_{index}`] or config[`Client_{index}`] or config[index]

				if type(value) == "function" then
					return function(_, ...)
						return value(entity, ...)
					end
				elseif value ~= nil and index ~= Name and index ~= Container and index ~= Extends then
					if value == Nil then
						return nil
					else
						return value
					end
				else
					local containerValue = (container :: any)[index]
					if type(containerValue) == "function" then
						return function(_, ...)
							return containerValue(container, ...)
						end
					end
					return containerValue
				end
			end,

			__newindex = function(_, index, value)
				if type(config[index]) == "function" then
					error("Cannot overwrite method " .. index)
				elseif config[index] ~= nil and index ~= Name and index ~= Container and index ~= Extends then
					if value == config[index] or (typeof(config[index]) == "table" and compareValues(config[index], value) ) then
						rawset(entity, index, nil)
					else
						rawset(entity, index, value)
					end
				else
					container[index] = value
				end
			end,
		})

		return entity :: any
	end,
}
-- Begin Types

-- ----------------------------------------
-- User type aliases (hoisted from spec files)
-- ----------------------------------------

export type AmphibiousCarMode = "land" | "water"

-- ----------------------------------------
-- Module: Vehicle, Car, Motorcycle, SportsCar, Boat, AmphibiousCar
-- Source: scripts/Tests.luau
-- ----------------------------------------

export type VehicleProperties = {
	Color: string,
	TopSpeed: number,
	Wheels: number,
	Owner: Player?,
}

export type VehicleMethods = {
	Honk: (self: Vehicle) -> string,
}

export type VehicleClientMethods = {
}

export type VehicleServerMethods = {
}

export type Vehicle = VehicleProperties & VehicleMethods & Folder

export type VehicleClient = Vehicle & VehicleClientMethods

export type VehicleServer = Vehicle & VehicleServerMethods

export type VehicleConfig = {
	Color: any,
	TopSpeed: any,
	Wheels: any,
	Owner: any,
	Honk: (self: Vehicle) -> string,
	[string]: string | Instance | { any },
}

export type CarProperties = {
	Color: string,
	TopSpeed: number,
} & VehicleProperties

export type CarMethods = {
	Drive: (self: Car, distance: number) -> string,
	Stop: (self: Car) -> string,
} & VehicleMethods

export type CarClientMethods = {
	PlayHorn: (self: CarClient) -> string,
} & VehicleClientMethods

export type CarServerMethods = {
	Refuel: (self: CarServer) -> string,
} & VehicleServerMethods

export type Car = CarProperties & CarMethods & Model

export type CarClient = Car & CarClientMethods

export type CarServer = Car & CarServerMethods

export type CarConfig = {
	Color: any,
	TopSpeed: any,
	Drive: (self: Car, distance: number) -> string,
	Stop: (self: Car) -> string,
	Server_Refuel: (self: CarServer) -> string,
	Client_PlayHorn: (self: CarClient) -> string,
	[string]: string | Instance | { any },
}

export type MotorcycleProperties = {
	Wheels: number,
	TopSpeed: number,
} & VehicleProperties

export type MotorcycleMethods = {
	Wheelie: (self: Motorcycle) -> string,
} & VehicleMethods

export type MotorcycleClientMethods = {
} & VehicleClientMethods

export type MotorcycleServerMethods = {
} & VehicleServerMethods

export type Motorcycle = MotorcycleProperties & MotorcycleMethods & Model

export type MotorcycleClient = Motorcycle & MotorcycleClientMethods

export type MotorcycleServer = Motorcycle & MotorcycleServerMethods

export type MotorcycleConfig = {
	Wheels: any,
	TopSpeed: any,
	Wheelie: (self: Motorcycle) -> string,
	[string]: string | Instance | { any },
}

export type SportsCarProperties = {
	Color: string,
	TopSpeed: number,
} & CarProperties

export type SportsCarMethods = {
	Boost: (self: SportsCar) -> string,
	Drive: (self: SportsCar, distance: number) -> string,
} & CarMethods

export type SportsCarClientMethods = {
} & CarClientMethods

export type SportsCarServerMethods = {
} & CarServerMethods

export type SportsCar = SportsCarProperties & SportsCarMethods & Model

export type SportsCarClient = SportsCar & SportsCarClientMethods

export type SportsCarServer = SportsCar & SportsCarServerMethods

export type SportsCarConfig = {
	Color: any,
	TopSpeed: any,
	Boost: (self: SportsCar) -> string,
	Drive: (self: SportsCar, distance: number) -> string,
	[string]: string | Instance | { any },
}

export type BoatProperties = {
	Color: string,
	Wheels: number,
	TopSpeed: number,
	HasHull: boolean,
} & VehicleProperties

export type BoatMethods = {
	Sail: (self: Boat, distance: number) -> string,
	Stop: (self: Boat) -> string,
} & VehicleMethods

export type BoatClientMethods = {
} & VehicleClientMethods

export type BoatServerMethods = {
	DropAnchor: (self: BoatServer) -> string,
} & VehicleServerMethods

export type Boat = BoatProperties & BoatMethods & Model

export type BoatClient = Boat & BoatClientMethods

export type BoatServer = Boat & BoatServerMethods

export type BoatConfig = {
	Color: any,
	Wheels: any,
	TopSpeed: any,
	HasHull: any,
	Sail: (self: Boat, distance: number) -> string,
	Stop: (self: Boat) -> string,
	Server_DropAnchor: (self: BoatServer) -> string,
	[string]: string | Instance | { any },
}

export type AmphibiousCarProperties = {
	Mode: AmphibiousCarMode,
} & CarProperties & BoatProperties

export type AmphibiousCarMethods = {
	SwitchMode: (self: AmphibiousCar, mode: AmphibiousCarMode) -> string,
} & CarMethods & BoatMethods

export type AmphibiousCarClientMethods = {
} & CarClientMethods & BoatClientMethods

export type AmphibiousCarServerMethods = {
} & CarServerMethods & BoatServerMethods

export type AmphibiousCar = AmphibiousCarProperties & AmphibiousCarMethods & Model

export type AmphibiousCarClient = AmphibiousCar & AmphibiousCarClientMethods

export type AmphibiousCarServer = AmphibiousCar & AmphibiousCarServerMethods

export type AmphibiousCarConfig = {
	Mode: any,
	SwitchMode: (self: AmphibiousCar, mode: AmphibiousCarMode) -> string,
	[string]: string | Instance | { any },
}

export type D = {
	Nil: any,
	Name: string,
	Container: string,
	Extends: string,
	fine:
		((config: AmphibiousCarConfig) -> AmphibiousCarConfig)
		& ((config: BoatConfig) -> BoatConfig)
		& ((config: SportsCarConfig) -> SportsCarConfig)
		& ((config: MotorcycleConfig) -> MotorcycleConfig)
		& ((config: CarConfig) -> CarConfig)
		& ((config: VehicleConfig) -> VehicleConfig),
	new:
		((config: AmphibiousCarConfig) -> AmphibiousCar & AmphibiousCarClient & AmphibiousCarServer)
		& ((config: BoatConfig) -> Boat & BoatClient & BoatServer)
		& ((config: SportsCarConfig) -> SportsCar & SportsCarClient & SportsCarServer)
		& ((config: MotorcycleConfig) -> Motorcycle & MotorcycleClient & MotorcycleServer)
		& ((config: CarConfig) -> Car & CarClient & CarServer)
		& ((config: VehicleConfig) -> Vehicle & VehicleClient & VehicleServer),
}

-- End Types

return (D :: any) :: D
