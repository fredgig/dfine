local Types = require("@types")
const Defin, TestClass = require("@defin")()

TestClass.ContainerClassName = "Model"

TestClass.Components = {
	"TestComponentA",
	"TestComponentB",
	"TestComponentC"
}

TestClass.Constants = {
	ClassConstant1 = "Hello",
	ClassConstant2 = 123,
	ClassConstant3 = true,
	ClassConstant4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	}
}

TestClass.Properties = {
	ClassProperty1 = "World",
	ClassProperty2 = 456,
	ClassProperty3 = false,
	ClassProperty4 = Defin.Nil :: Player?
}

function TestClass.Server:Initialized(self: Types.TestClassServer)
	print("Initialized TestClass on the server!")
end

function TestClass.Client:Initialized(self: Types.TestClassClient)
	print("Initialized TestClass on the client!")
end

function TestClass.Server:ClassServerMethod(self: Types.TestClassServer, arg1: string, arg2: number)
	print("Called ClassServerMethod on the server with arguments:", arg1, arg2)
end

function TestClass.Client:ClassClientMethod(self: Types.TestClassClient, arg1: string)
	print("Called ClassClientMethod on the client with argument:", arg1)
end

function TestClass:ClassMethod(self: Types.TestClass, arg1: string, arg2: number): Player?
	print("Called ClassMethod on both server and client with arguments:", arg1, arg2)

	return nil
end

function TestClass.Server.Request:ClassServerMethod(self: Types.TestClassServer, player: Player)
	print("Player", player.Name, "requested ClassServerMethod on the server!")
end

function TestClass.Client.Replicate:ClassClientMethod(self: Types.TestClassClient, arg1: string)
	print("Called ClassClientMethod on the client with argument:", arg1)
end

function TestClass.Server.Changed:Property1(self: Types.TestClassServer, newValue: string, oldValue: string)
	print("Property1 changed on the server from", oldValue, "to", newValue)
end

function TestClass.Client.Changed:Property1(self: Types.TestClassClient, newValue: string, oldValue: string)
	print("Property1 changed on the client from", oldValue, "to", newValue)
end

return TestClass