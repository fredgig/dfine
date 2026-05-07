--!strict

local Types = require("../../Types.luau")
const Defin, TestComponentA = require("../../Defin.luau")()

TestComponentA.Constants = {
	ComponentConstant1 = "Hello",
	ComponentConstant2 = 123,
	ComponentConstant3 = true,
	ComponentConstant4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	}
}

TestComponentA.Properties = {
	ComponentProperty1 = "World",
	ComponentProperty2 = 456,
	ComponentProperty3 = false,
	ComponentProperty4 = Defin.Nil :: Player?
}

function TestComponentA.Server:Initialized(self: Types.TestComponentAServer)
	print("Initialized TestComponentA on the server!")
end

function TestComponentA.Client:Initialized(self: Types.TestComponentAClient)
	print("Initialized TestComponentA on the client!")
end

function TestComponentA.Server:ComponentAServerMethod(self: Types.TestComponentAServer, arg1: string, arg2: number)
	print("Called ComponentAServerMethod on the server with arguments:", arg1, arg2)
end

function TestComponentA.Client:ComponentAClientMethod(self: Types.TestComponentAClient, arg1: string)
	print("Called ComponentAClientMethod on the client with argument:", arg1)
end

function TestComponentA:ComponentAMethod(self: Types.TestComponentA, arg1: string, arg2: number): Player?
	print("Called ComponentAMethod on both server and client with arguments:", arg1, arg2)
	return nil
end

function TestComponentA.Server.Request:ComponentAServerMethod(self: Types.TestComponentAServer, player: Player)
	print("Player", player.Name, "requested ComponentAServerMethod on the server!")
end

function TestComponentA.Client.Replicate:ComponentAClientMethod(self: Types.TestComponentAClient, arg1: string)
	print("Called ComponentAClientMethod on the client with argument:", arg1)
end

function TestComponentA.Server.Changed:Property1(self: Types.TestComponentAServer, newValue: string, oldValue: string)
	print("Property1 changed on the server from", oldValue, "to", newValue)
end

function TestComponentA.Client.Changed:Property1(self: Types.TestComponentAClient, newValue: string, oldValue: string)
	print("Property1 changed on the client from", oldValue, "to", newValue)
end

return TestComponentA