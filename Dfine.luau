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
-- Module: Entity0, Entity1, Entity2
-- Source: scripts/Tests.luau
-- ----------------------------------------

export type Entity0Properties = {}

export type Entity0Methods = {
}

export type Entity0ClientMethods = {
	SomeDeepClientMethod: (self: Entity0Client) -> string,
}

export type Entity0ServerMethods = {
}

export type Entity0 = Entity0Properties & Entity0Methods & Folder

export type Entity0Client = Entity0 & Entity0ClientMethods

export type Entity0Server = Entity0 & Entity0ServerMethods

export type Entity0Config = {
	Client_SomeDeepClientMethod: (self: Entity0Client) -> string,
	[string]: string | Instance | { any },
}

export type Entity1Properties = {
	Property5: Player?,
	Property6: string,
} & Entity0Properties

export type Entity1Methods = {
} & Entity0Methods

export type Entity1ClientMethods = {
} & Entity0ClientMethods

export type Entity1ServerMethods = {
} & Entity0ServerMethods

export type Entity1 = Entity1Properties & Entity1Methods & Folder

export type Entity1Client = Entity1 & Entity1ClientMethods

export type Entity1Server = Entity1 & Entity1ServerMethods

export type Entity1Config = {
	Property5: any,
	Property6: any,
	[string]: string | Instance | { any },
}

export type Entity2Properties = {
	Property1: string,
	Property2: number,
	Property3: boolean,
	Property4: {
		Foo: string,
		Baz: number,
		Qux: boolean,
	},
} & Entity1Properties

export type Entity2Methods = {
	SomeMethod: (self: Entity2, arg1: number, arg2: string) -> string,
} & Entity1Methods

export type Entity2ClientMethods = {
	SomeClientMethod: (self: Entity2Client) -> (),
} & Entity1ClientMethods

export type Entity2ServerMethods = {
	SomeServerMethod: (self: Entity2Server) -> (),
} & Entity1ServerMethods

export type Entity2 = Entity2Properties & Entity2Methods & Model

export type Entity2Client = Entity2 & Entity2ClientMethods

export type Entity2Server = Entity2 & Entity2ServerMethods

export type Entity2Config = {
	Property1: any,
	Property2: any,
	Property3: any,
	Property4: any,
	SomeMethod: (self: Entity2, arg1: number, arg2: string) -> string,
	Server_SomeServerMethod: (self: Entity2Server) -> (),
	Client_SomeClientMethod: (self: Entity2Client) -> (),
	[string]: string | Instance | { any },
}

export type D = {
	Nil: any,
	Name: string,
	Container: string,
	Extends: string,
	fine:
		((config: Entity2Config) -> Entity2Config)
		& ((config: Entity1Config) -> Entity1Config)
		& ((config: Entity0Config) -> Entity0Config),
	new:
		((config: Entity2Config) -> Entity2 & Entity2Client & Entity2Server)
		& ((config: Entity1Config) -> Entity1 & Entity1Client & Entity1Server)
		& ((config: Entity0Config) -> Entity0 & Entity0Client & Entity0Server),
}

-- End Types

return (D :: any) :: D
