--!native
--!strict
local D = require("@defin")

local TestEntity0 = D.fine {
	Name = "Entity0",

	Client_SomeDeepClientMethod = function(self): string
		print("Hello from Client_SomeDeepClientMethod in TestEntity0")

		return "Hello there"
	end,
}

local TestEntity1 = D.fine {
	Name = "Entity1",

	Extends = {
		TestEntity0,
	},

	Property5 = D.Nil :: Player?,
}

local TestEntity2 = D.fine<<D.Entity2Config>> {
	Name = "Entity2",

	Container = Instance.new("Model"),

	Extends = {
		TestEntity1,
	},

	Property1 = "Hello",
	Property2 = 123,
	Property3 = true,
	Property4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	},

	SomeMethod = function(self, arg1: number, arg2: string) : boolean
		return true
	end,

	Server_SomeServerMethod = function(self)
		local asdf = self:SomeMethod(1, "example")

		print(asdf)
	end,

	Client_SomeClientMethod = function(self)
		print(self.Property5) -- nil or Player

		print(self:SomeDeepClientMethod()) -- "Hello there"
	end,
}

return TestEntity2