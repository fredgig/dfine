local Instance = require("@lune/roblox").Instance
local D = require("@dfine")

local assert: (boolean, string?) -> () = assert :: any

local TestEntity0 = D.fine {
	[D.Name] = "Entity0",

	Client_SomeDeepClientMethod = function(self): string
		return "Hello there"
	end,
}

local TestEntity1 = D.fine {
	[D.Name] = "Entity1",

	[D.Extends] = {
		TestEntity0,
	},

	Property5 = D.Nil :: Player?,
	Property6 = "Additional property in Entity1",
}

local TestEntity2 = D.fine {
	[D.Name] = "Entity2",

	[D.Container] = Instance.new("Model"),

	[D.Extends] = {
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

	SomeMethod = function(self, arg1: number, arg2: string) : string
		return tostring(arg1) .. " " .. arg2 .. " " .. tostring(self.Property3)
	end,

	Server_SomeServerMethod = function(self)
		return self:SomeMethod(1, "example") .. " Server"
	end,

	Client_SomeClientMethod = function(self)
		return self:SomeMethod(1, "example") .. " Client"
	end,
}

local entity2 = D.new(TestEntity2)

assert(entity2.Property1 == "Hello", `Expected Property1 to be "Hello", got {entity2.Property1}`)
assert(entity2.Property2 == 123, `Expected Property2 to be 123, got {entity2.Property2}`)
assert(entity2.Property3 == true, `Expected Property3 to be true, got {entity2.Property3}`)
assert(entity2.Property4.Foo == "Bar", `Expected Property4.Foo to be "Bar", got {entity2.Property4.Foo}`)
assert(entity2.Property4.Baz == 456, `Expected Property4.Baz to be 456, got {entity2.Property4.Baz}`)
assert(entity2.Property4.Qux == false, `Expected Property4.Qux to be false, got {entity2.Property4.Qux}`)
assert(entity2.Property5 == nil, `Expected Property5 to be nil, got {entity2.Property5}`)

assert(entity2:SomeMethod(1, "example") == "1 example true", `Expected SomeMethod to return "1 example true", got {entity2:SomeMethod(1, "example")}`)
assert(entity2:SomeServerMethod() == "1 example true Server", `Expected SomeServerMethod to return "1 example true Server", got {entity2:SomeServerMethod()}`)
assert(entity2:SomeClientMethod() == "1 example true Client", `Expected SomeClientMethod to return "1 example true Client", got {entity2:SomeClientMethod()}`)
assert(entity2:SomeDeepClientMethod() == "Hello there", `Expected SomeDeepClientMethod to return "Hello there", got {entity2:SomeDeepClientMethod()}`)

assert(entity2.Name == "Model", `Expected Name to be "Model", got {entity2.Name}`)
assert(#entity2:GetChildren() == 0, `Expected GetChildren() to return 0, got {#entity2:GetChildren()}`)

entity2.Property1 = "Hello World"

assert(entity2.Property1 == "Hello World", `Expected Property1 to be "Hello World", got {entity2.Property1}`)
assert(rawget(entity2, "Property1") == "Hello World", `Expected rawget(Property1) to be "Hello World", got {rawget(entity2, "Property1")}`)

entity2.Property1 = "Hello"

assert(entity2.Property1 == "Hello", `Expected Property1 to be "Hello", got {entity2.Property1}`)

entity2.Name ..= " Extended"

assert(entity2.Name == "Model Extended", `Expected Name to be "Model Extended", got {entity2.Name}`)
assert(rawget(entity2, "Name") == nil, `Expected rawget(Name) to be nil, got {rawget(entity2, "Name")}`)