local D = require("@defin")

D.Components.TestComponentA.Constants = {
	ComponentConstant1 = "Hello",
	ComponentConstant2 = 123,
	ComponentConstant3 = true,
	ComponentConstant4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	}
}

D.Components.TestComponentA.Properties = {
	ComponentProperty1 = "World",
	ComponentProperty2 = 456,
	ComponentProperty3 = false,
	ComponentProperty4 = D.Nil :: Player?
}

function D.Components.TestComponentA.Server:Initialized(self: D.TestComponentAServer)
	print("Initialized TestComponentA on the server!")
end

function D.Components.TestComponentA.Client:Initialized(self: D.TestComponentAClient)
	print("Initialized TestComponentA on the client!")
end

function D.Components.TestComponentA.Server:ComponentAServerMethod(self: D.TestComponentAServer, arg1: string, arg2: number)
	print("Called ComponentAServerMethod on the server with arguments:", arg1, arg2)
end

function D.Components.TestComponentA.Client:ComponentAClientMethod(self: D.TestComponentAClient, arg1: string)
	print("Called ComponentAClientMethod on the client with argument:", arg1)
end

function D.Components.TestComponentA:ComponentAMethod(self: D.TestComponentA, arg1: string, arg2: number): Player?
	print("Called ComponentAMethod on both server and client with arguments:", arg1, arg2)
	return nil
end

function D.Components.TestComponentA.Server.Request:ComponentAServerMethod(self: D.TestComponentAServer, player: Player)
	print("Player", player.Name, "requested ComponentAServerMethod on the server!")
end

function D.Components.TestComponentA.Client.Replicate:ComponentAClientMethod(self: D.TestComponentAClient, arg1: string)
	print("Called ComponentAClientMethod on the client with argument:", arg1)
end

function D.Components.TestComponentA.Server.Changed:Property1(self: D.TestComponentAServer, newValue: string, oldValue: string)
	print("Property1 changed on the server from", oldValue, "to", newValue)
end

function D.Components.TestComponentA.Client.Changed:Property1(self: D.TestComponentAClient, newValue: string, oldValue: string)
	print("Property1 changed on the client from", oldValue, "to", newValue)
end
