local D = require("@defin")

D.Classes.TestClass.ContainerClassName = "Model"

D.Classes.TestClass.Components = {
	"TestComponentA",
	"TestComponentB",
	"TestComponentC"
}

D.Classes.TestClass.Constants = {
	ClassConstant1 = "Hello",
	ClassConstant2 = 123,
	ClassConstant3 = true,
	ClassConstant4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	}
}

D.Classes.TestClass.Properties = {
	ClassProperty1 = "World",
	ClassProperty2 = 456,
	ClassProperty3 = false,
	ClassProperty4 = D.Nil :: Player?
}

function D.Classes.TestClass.Server:Initialized(self: D.TestClassServer)
	print("Initialized TestClass on the server!")
end

function D.Classes.TestClass.Client:Initialized(self: D.TestClassClient)
	print("Initialized TestClass on the client!")
end

function D.Classes.TestClass.Server:ClassServerMethod(self: D.TestClassServer, arg1: string, arg2: number)
	print("Called ClassServerMethod on the server with arguments:", arg1, arg2)
end

function D.Classes.TestClass.Client:ClassClientMethod(self: D.TestClassClient, arg1: string)
	print("Called ClassClientMethod on the client with argument:", arg1)
end

function D.Classes.TestClass:ClassMethod(self: D.TestClass, arg1: string, arg2: number): Player?
	print("Called ClassMethod on both server and client with arguments:", arg1, arg2)

	return nil
end

function D.Classes.TestClass.Server.Request:ClassServerMethod(self: D.TestClassServer, player: Player)
	print("Player", player.Name, "requested ClassServerMethod on the server!")
end

function D.Classes.TestClass.Client.Replicate:ClassClientMethod(self: D.TestClassClient, arg1: string)
	print("Called ClassClientMethod on the client with argument:", arg1)
end

function D.Classes.TestClass.Server.Changed:Property1(self: D.TestClassServer, newValue: string, oldValue: string)
	print("Property1 changed on the server from", oldValue, "to", newValue)
end

function D.Classes.TestClass.Client.Changed:Property1(self: D.TestClassClient, newValue: string, oldValue: string)
	print("Property1 changed on the client from", oldValue, "to", newValue)
end
