type EntityConfigBase = {
	Name: string,
	Container: Instance?,
	Extends: { EntityConfigBase }?,
	[string]: any,
}

local D = {
	Nil = "DEFIN_NIL",

	fine = function<T>(config: T): T
		return config
	end,
}

-- Begin Types

-- ----------------------------------------
-- Module: Entity0, Entity1, Entity2
-- Source: scripts/Tests.luau
-- ----------------------------------------

local Entity0Properties = {}

export type Entity0Properties = typeof(Entity0Properties)

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
	Name: string,
	Container: Instance?,
	Extends: { any }?,
	Client_SomeDeepClientMethod: ((self: Entity0Client) -> string)?,
}

local Entity1Properties = {
	Property5 = D.Nil :: Player?,
}

export type Entity1Properties = typeof(Entity1Properties) & Entity0Properties

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
	Name: string,
	Container: Instance?,
	Extends: { any }?,
	Property5: any?,
}

local Entity2Properties = {
	Property1 = "Hello",
	Property2 = 123,
	Property3 = true,
	Property4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	},
}

export type Entity2Properties = typeof(Entity2Properties) & Entity1Properties

export type Entity2Methods = {
	SomeMethod: (self: Entity2, arg1: number, arg2: string) -> boolean,
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
	Name: string,
	Container: Instance?,
	Extends: { any }?,
	Property1: any?,
	Property2: any?,
	Property3: any?,
	Property4: any?,
	SomeMethod: ((self: Entity2, arg1: number, arg2: string) -> boolean)?,
	Server_SomeServerMethod: ((self: Entity2Server) -> ())?,
	Client_SomeClientMethod: ((self: Entity2Client) -> ())?,
}

-- End Types

return D
