--!strict

local fs = require("@lune/fs")

local function getRootName(source: string): string?
	local rootName = source:match("([%a_][%w_]*)%.Constants%s*=")
	if rootName then
		return rootName
	end

	return source:match("([%a_][%w_]*)%.Properties%s*=")
end

local function getLiteralForField(source: string, rootName: string, fieldName: string): string?
	local pattern = rootName .. "%." .. fieldName .. "%s*=%s*(%b{})"
	return source:match(pattern)
end

local function getContainerTypeName(source: string, rootName: string): string
	local pattern = rootName .. "%\.ContainerClassName%s*=%s*[\"']([%a_][%w_]*)[\"']"
	local className = source:match(pattern)

	if className and className ~= "" then
		return className
	end

	return "Folder"
end

local function normalizeLiteral(literal: string): string
	return (literal:gsub("Defin%.Nil", "nil"))
end

local function getExtendedComponentNames(source: string, rootName: string): { string }
	local names = {}
	local seen: { [string]: boolean } = {}
	local pattern = rootName .. "%.Components%s*=%s*(%b{})"
	local literal = source:match(pattern)

	if not literal then
		return names
	end

	for componentName in literal:gmatch("[\"']([%a_][%w_]*)[\"']") do
		if not seen[componentName] then
			seen[componentName] = true
			table.insert(names, componentName)
		end
	end

	return names
end

local function buildTypeBlock(rootName: string, fieldName: string, literal: string, extendsTypeNames: { string }): { string }
	local aliasName = rootName .. fieldName
	local typeExpression = "typeof(" .. aliasName .. ")"

	for _, extendsTypeName in ipairs(extendsTypeNames) do
		typeExpression ..= " & " .. extendsTypeName
	end

	return {
		"local " .. aliasName .. " = " .. literal,
		"",
		"export type " .. aliasName .. " = " .. typeExpression,
		"",
	}
end

local function trim(text: string): string
	return text:match("^%s*(.-)%s*$") or ""
end

local function splitParams(params: string): { string }
	local result = {}
	for param in params:gmatch("[^,]+") do
		table.insert(result, trim(param))
	end
	return result
end

local function isSelfParam(param: string): boolean
	local name = trim(param:match("^([^:]+)") or param)
	return name == "self"
end

local function toFunctionTypeParams(selfTypeName: string, params: string, omitFirstParam: boolean?, prependParam: string?): string
	local functionParams = { "self: " .. selfTypeName }
	if prependParam then
		table.insert(functionParams, prependParam)
	end
	local split = splitParams(params)
	if #split > 0 and isSelfParam(split[1]) then
		table.remove(split, 1)
	end
	local startIndex = (omitFirstParam and 2) or 1

	for index = startIndex, #split do
		local param = split[index]
		if param ~= "" then
			if param == "..." then
				table.insert(functionParams, "...any")
			elseif param:find(":", 1, true) then
				table.insert(functionParams, param)
			else
				table.insert(functionParams, param .. ": any")
			end
		end
	end

	return table.concat(functionParams, ", ")
end

local function startsWith(value: string, prefix: string): boolean
	return value:sub(1, #prefix) == prefix
end

local function getReturnTypeOrAny(returnTypeText: string?): string
	if not returnTypeText then
		return "any"
	end

	local withoutComment = (returnTypeText:match("^(.-)%s*%-%-") or returnTypeText)
	local returnType = trim(withoutComment)

	if returnType == "" then
		return "any"
	end

	return returnType
end

local function addMethodSignature(methodSignatures: { [string]: { string } }, methodName: string, signature: string)
	local signatures = methodSignatures[methodName]
	if not signatures then
		signatures = {}
		methodSignatures[methodName] = signatures
	end

	if not table.find(signatures, signature) then
		table.insert(signatures, signature)
	end
end

local function getGeneratedMethodName(rootName: string, scopedRoot: string, methodName: string): string
	if scopedRoot == rootName .. ".Server.Request" then
		return "Request" .. methodName
	end

	return methodName
end

local function isClientScope(rootName: string, scopedRoot: string): boolean
	return scopedRoot == rootName .. ".Client" or startsWith(scopedRoot, rootName .. ".Client.")
end

local function isServerScope(rootName: string, scopedRoot: string): boolean
	return scopedRoot == rootName .. ".Server" or startsWith(scopedRoot, rootName .. ".Server.")
end

local function extractMethodSignatures(source: string, rootName: string): ({ [string]: { string } }, { [string]: { string } }, { [string]: { string } })
	local rootMethods: { [string]: { string } } = {}
	local clientMethods: { [string]: { string } } = {}
	local serverMethods: { [string]: { string } } = {}
	local rootSelfType = rootName
	local clientSelfType = rootName .. "Client"
	local serverSelfType = rootName .. "Server"

	for line in source:gmatch("[^\r\n]+") do
		local scopedRoot, methodName, params, returnTypeText =
			line:match("^%s*function%s+([%a_][%w_%.]*):([%a_][%w_]*)%s*%((.-)%)%s*:%s*(.-)%s*$")

		if not scopedRoot then
			scopedRoot, methodName, params =
				line:match("^%s*function%s+([%a_][%w_%.]*):([%a_][%w_]*)%s*%((.-)%)%s*$")
			returnTypeText = nil
		end

		if scopedRoot and methodName and params and (scopedRoot == rootName or startsWith(scopedRoot, rootName .. ".")) then
			local isChangedScope = scopedRoot == rootName .. ".Changed"
				or scopedRoot == rootName .. ".Client.Changed"
				or scopedRoot == rootName .. ".Server.Changed"

			if isChangedScope then
				continue
			end

			local returnType = getReturnTypeOrAny(returnTypeText)
			local inClientScope = isClientScope(rootName, scopedRoot)
			local inServerScope = isServerScope(rootName, scopedRoot)
			local inSharedScope = scopedRoot == rootName

			if scopedRoot == rootName .. ".Client.Replicate" then
				local replicateSignature = "(" .. toFunctionTypeParams(serverSelfType, params, false) .. ") -> " .. returnType
				addMethodSignature(serverMethods, "Replicate" .. methodName, replicateSignature)

				local replicatePlayerSignature = "(" .. toFunctionTypeParams(serverSelfType, params, false, "player: Player") .. ") -> " .. returnType
				addMethodSignature(serverMethods, "ReplicatePlayer" .. methodName, replicatePlayerSignature)
			else
				local omitFirstParam = scopedRoot == rootName .. ".Server.Request"
				local generatedName = getGeneratedMethodName(rootName, scopedRoot, methodName)

				if inSharedScope then
					local rootSignature = "(" .. toFunctionTypeParams(rootSelfType, params, omitFirstParam) .. ") -> " .. returnType
					addMethodSignature(rootMethods, generatedName, rootSignature)
				end

				if scopedRoot == rootName .. ".Server.Request" then
					local clientSignature = "(" .. toFunctionTypeParams(clientSelfType, params, true) .. ") -> " .. returnType
					addMethodSignature(clientMethods, generatedName, clientSignature)
				elseif inClientScope or inSharedScope then
					local clientSignature = "(" .. toFunctionTypeParams(clientSelfType, params, omitFirstParam) .. ") -> " .. returnType
					addMethodSignature(clientMethods, generatedName, clientSignature)
				end

				if scopedRoot ~= rootName .. ".Server.Request" and (inServerScope or inSharedScope) then
					local serverSignature = "(" .. toFunctionTypeParams(serverSelfType, params, omitFirstParam) .. ") -> " .. returnType
					addMethodSignature(serverMethods, generatedName, serverSignature)
				end
			end
		end
	end

	return rootMethods, clientMethods, serverMethods
end

local function buildMethodsTypeBlock(typeName: string, methodSignatures: { [string]: { string } }, extendsTypeNames: { string }): { string }
	local lines = {
		"export type " .. typeName .. " = {",
	}

	local names = {}
	for methodName in pairs(methodSignatures) do
		table.insert(names, methodName)
	end
	table.sort(names)

	for _, methodName in ipairs(names) do
		local signatures = methodSignatures[methodName]
		for index, signature in ipairs(signatures) do
			signatures[index] = "(" .. signature .. ")"
		end
		local combined = table.concat(signatures, " & ")
		table.insert(lines, "\t" .. methodName .. ": " .. combined .. ",")
	end

	local suffix = ""
	for _, extendsTypeName in ipairs(extendsTypeNames) do
		suffix ..= " & " .. extendsTypeName
	end

	table.insert(lines, "}" .. suffix)
	table.insert(lines, "")

	return lines
end

local function getBalanceDelta(text: string): number
	local opens = 0
	local closes = 0

	for _ in text:gmatch("{") do
		opens += 1
	end
	for _ in text:gmatch("%(") do
		opens += 1
	end
	for _ in text:gmatch("%[") do
		opens += 1
	end

	for _ in text:gmatch("}") do
		closes += 1
	end
	for _ in text:gmatch("%)") do
		closes += 1
	end
	for _ in text:gmatch("%]") do
		closes += 1
	end

	return opens - closes
end

local function extractDeclaredTypes(source: string): { [string]: string }
	local declared: { [string]: string } = {}
	local lines = {}

	for line in source:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local index = 1
	while index <= #lines do
		local line = lines[index]
		local name, rhs = line:match("^%s*export%s+type%s+([%a_][%w_]*)%s*=%s*(.*)%s*$")
		if not name then
			name, rhs = line:match("^%s*type%s+([%a_][%w_]*)%s*=%s*(.*)%s*$")
		end

		if name and rhs ~= nil then
			local parts = { rhs }
			local balance = getBalanceDelta(rhs)
			local nextIndex = index + 1

			while nextIndex <= #lines and (balance > 0 or trim(parts[#parts]) == "") do
				local nextLine = lines[nextIndex]
				table.insert(parts, nextLine)
				balance += getBalanceDelta(nextLine)
				nextIndex += 1
			end

			if balance <= 0 then
				declared[name] = trim(table.concat(parts, "\n"))
			end

			index = nextIndex
		else
			index += 1
		end
	end

	return declared
end

local function generateTypesForFile(inputPath: string, knownRootNames: { [string]: boolean }): ({ string }?, string)
	local source = fs.readFile(inputPath)

	local rootName = getRootName(source)
	if not rootName then
		return nil, "Could not find `<Name>.Constants` or `<Name>.Properties` in " .. inputPath
	end

	local constantsLiteral = getLiteralForField(source, rootName, "Constants")
	local propertiesLiteral = getLiteralForField(source, rootName, "Properties")
	local containerTypeName = getContainerTypeName(source, rootName)
	local extendedComponentNames = getExtendedComponentNames(source, rootName)
	local resolvedExtendedComponents = {}

	for _, componentName in ipairs(extendedComponentNames) do
		if componentName ~= rootName and knownRootNames[componentName] then
			table.insert(resolvedExtendedComponents, componentName)
		end
	end

	table.sort(resolvedExtendedComponents)

	local extendedConstants = {}
	local extendedProperties = {}
	local extendedMethods = {}
	local extendedClientMethods = {}
	local extendedServerMethods = {}

	for _, componentName in ipairs(resolvedExtendedComponents) do
		table.insert(extendedConstants, componentName .. "Constants")
		table.insert(extendedProperties, componentName .. "Properties")
		table.insert(extendedMethods, componentName .. "Methods")
		table.insert(extendedClientMethods, componentName .. "ClientMethods")
		table.insert(extendedServerMethods, componentName .. "ServerMethods")
	end

	if not constantsLiteral then
		return nil, "Could not find `" .. rootName .. ".Constants = { ... }` in " .. inputPath
	end

	if not propertiesLiteral then
		return nil, "Could not find `" .. rootName .. ".Properties = { ... }` in " .. inputPath
	end

	constantsLiteral = normalizeLiteral(constantsLiteral)
	propertiesLiteral = normalizeLiteral(propertiesLiteral)
	local methodSignatures, clientMethodSignatures, serverMethodSignatures = extractMethodSignatures(source, rootName)
	local declaredTypes = extractDeclaredTypes(source)

	local generatedLines = {}

	for _, line in ipairs(buildTypeBlock(rootName, "Constants", constantsLiteral, extendedConstants)) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildTypeBlock(rootName, "Properties", propertiesLiteral, extendedProperties)) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildMethodsTypeBlock(rootName .. "Methods", methodSignatures, extendedMethods)) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildMethodsTypeBlock(rootName .. "ClientMethods", clientMethodSignatures, extendedClientMethods)) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildMethodsTypeBlock(rootName .. "ServerMethods", serverMethodSignatures, extendedServerMethods)) do
		table.insert(generatedLines, line)
	end

	local declaredTypeNames = {}
	for typeName in pairs(declaredTypes) do
		if typeName ~= (rootName .. "Constants") and typeName ~= (rootName .. "Properties") and typeName ~= (rootName .. "Methods") and typeName ~= (rootName .. "ClientMethods") and typeName ~= (rootName .. "ServerMethods") and typeName ~= rootName then
			table.insert(declaredTypeNames, typeName)
		end
	end
	table.sort(declaredTypeNames)

	for _, typeName in ipairs(declaredTypeNames) do
		table.insert(generatedLines, "export type " .. typeName .. " = " .. declaredTypes[typeName])
		table.insert(generatedLines, "")
	end

	table.insert(generatedLines, "export type " .. rootName .. " = " .. rootName .. "Constants & " .. rootName .. "Properties & " .. rootName .. "Methods & " .. containerTypeName)
	table.insert(generatedLines, "")
	table.insert(generatedLines, "export type " .. rootName .. "Client = " .. rootName .. " & " .. rootName .. "ClientMethods")
	table.insert(generatedLines, "")
	table.insert(generatedLines, "export type " .. rootName .. "Server = " .. rootName .. " & " .. rootName .. "ServerMethods")
	table.insert(generatedLines, "")

	return generatedLines, rootName
end

local function findLuauFiles(dir: string): { string }
	local files = {}
	
	if not fs.isDir(dir) then
		return files
	end

	for _, name in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			for _, file in ipairs(findLuauFiles(path)) do
				table.insert(files, file)
			end
		elseif name:match("%.luau$") and not name:match("%.types%.luau$") then
			table.insert(files, path)
		end
	end

	return files
end

-- Main execution
local scriptsDir = "scripts"

if not fs.isDir(scriptsDir) then
	error("scripts folder not found")
end

local componentFiles = findLuauFiles(scriptsDir .. "/Components")
local classFiles = findLuauFiles(scriptsDir .. "/Classes")

if #componentFiles == 0 and #classFiles == 0 then
	error("No .luau files found in scripts/Components or scripts/Classes")
end

table.sort(componentFiles)
table.sort(classFiles)

local knownRootNames: { [string]: boolean } = {}
for _, inputPath in ipairs(componentFiles) do
	local source = fs.readFile(inputPath)
	local rootName = getRootName(source)
	if rootName then
		knownRootNames[rootName] = true
	end
end
for _, inputPath in ipairs(classFiles) do
	local source = fs.readFile(inputPath)
	local rootName = getRootName(source)
	if rootName then
		knownRootNames[rootName] = true
	end
end

local allGeneratedLines = {
	"--!strict",
	"-- generated programmatically",
	"",
}

local function appendGroup(groupTitle: string, groupFiles: { string })
	if #groupFiles == 0 then
		return
	end

	table.insert(allGeneratedLines, "-- ========================================")
	table.insert(allGeneratedLines, "-- " .. groupTitle)
	table.insert(allGeneratedLines, "-- ========================================")
	table.insert(allGeneratedLines, "")

	for _, inputPath in ipairs(groupFiles) do
		local generatedLines, rootNameOrError = generateTypesForFile(inputPath, knownRootNames)

		if generatedLines then
			table.insert(allGeneratedLines, "-- ----------------------------------------")
			table.insert(allGeneratedLines, "-- Module: " .. rootNameOrError)
			table.insert(allGeneratedLines, "-- Source: " .. inputPath)
			table.insert(allGeneratedLines, "-- ----------------------------------------")
			table.insert(allGeneratedLines, "")

			for _, line in ipairs(generatedLines) do
				table.insert(allGeneratedLines, line)
			end

			print("Included " .. inputPath .. " from " .. rootNameOrError)
		else
			print("Skipped " .. inputPath .. ": " .. rootNameOrError)
		end
	end
end

appendGroup("COMPONENTS", componentFiles)
appendGroup("CLASSES", classFiles)

table.insert(allGeneratedLines, "return nil")
table.insert(allGeneratedLines, "")

local outputPath = "Types.luau"
fs.writeFile(outputPath, table.concat(allGeneratedLines, "\n"))
print("Wrote " .. outputPath)
