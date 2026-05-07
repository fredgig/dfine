--!strict
-- generated programmatically

-- ========================================
-- COMPONENTS
-- ========================================

-- ----------------------------------------
-- Module: TestComponentA
-- Source: scripts/Components/TestComponentA.luau
-- ----------------------------------------

local TestComponentAConstants = {
	ComponentConstant1 = "Hello",
	ComponentConstant2 = 123,
	ComponentConstant3 = true,
	ComponentConstant4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	}
}

export type TestComponentAConstants = typeof(TestComponentAConstants)

local TestComponentAProperties = {
	ComponentProperty1 = "World",
	ComponentProperty2 = 456,
	ComponentProperty3 = false,
	ComponentProperty4 = nil :: Player?
}

export type TestComponentAProperties = typeof(TestComponentAProperties)

export type TestComponentAMethods = {
	ComponentAMethod: ((self: TestComponentA, arg1: string, arg2: number) -> Player?),
}

export type TestComponentAClientMethods = {
	ComponentAClientMethod: ((self: TestComponentAClient, arg1: string) -> any),
	ComponentAMethod: ((self: TestComponentAClient, arg1: string, arg2: number) -> Player?),
	Initialized: ((self: TestComponentAClient) -> any),
	RequestComponentAServerMethod: ((self: TestComponentAClient) -> any),
}

export type TestComponentAServerMethods = {
	ComponentAMethod: ((self: TestComponentAServer, arg1: string, arg2: number) -> Player?),
	ComponentAServerMethod: ((self: TestComponentAServer, arg1: string, arg2: number) -> any),
	Initialized: ((self: TestComponentAServer) -> any),
	ReplicateComponentAClientMethod: ((self: TestComponentAServer, arg1: string) -> any),
	ReplicatePlayerComponentAClientMethod: ((self: TestComponentAServer, player: Player, arg1: string) -> any),
}

export type TestComponentA = TestComponentAConstants & TestComponentAProperties & TestComponentAMethods & Folder

export type TestComponentAClient = TestComponentA & TestComponentAClientMethods

export type TestComponentAServer = TestComponentA & TestComponentAServerMethods

-- ========================================
-- CLASSES
-- ========================================

-- ----------------------------------------
-- Module: TestClass
-- Source: scripts/Classes/TestClass.luau
-- ----------------------------------------

local TestClassConstants = {
	ClassConstant1 = "Hello",
	ClassConstant2 = 123,
	ClassConstant3 = true,
	ClassConstant4 = {
		Foo = "Bar",
		Baz = 456,
		Qux = false,
	}
}

export type TestClassConstants = typeof(TestClassConstants) & TestComponentAConstants

local TestClassProperties = {
	ClassProperty1 = "World",
	ClassProperty2 = 456,
	ClassProperty3 = false,
	ClassProperty4 = nil :: Player?
}

export type TestClassProperties = typeof(TestClassProperties) & TestComponentAProperties

export type TestClassMethods = {
	ClassMethod: ((self: TestClass, arg1: string, arg2: number) -> Player?),
} & TestComponentAMethods

export type TestClassClientMethods = {
	ClassClientMethod: ((self: TestClassClient, arg1: string) -> any),
	ClassMethod: ((self: TestClassClient, arg1: string, arg2: number) -> Player?),
	Initialized: ((self: TestClassClient) -> any),
	RequestClassServerMethod: ((self: TestClassClient) -> any),
} & TestComponentAClientMethods

export type TestClassServerMethods = {
	ClassMethod: ((self: TestClassServer, arg1: string, arg2: number) -> Player?),
	ClassServerMethod: ((self: TestClassServer, arg1: string, arg2: number) -> any),
	Initialized: ((self: TestClassServer) -> any),
	ReplicateClassClientMethod: ((self: TestClassServer, arg1: string) -> any),
	ReplicatePlayerClassClientMethod: ((self: TestClassServer, player: Player, arg1: string) -> any),
} & TestComponentAServerMethods

export type TestClass = TestClassConstants & TestClassProperties & TestClassMethods & Model

export type TestClassClient = TestClass & TestClassClientMethods

export type TestClassServer = TestClass & TestClassServerMethods

return nil
