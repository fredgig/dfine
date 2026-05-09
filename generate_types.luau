-- Vibecoded

local fs = require("@lune/fs")

local function trim(text: string): string
	return text:match("^%s*(.-)%s*$") or ""
end

type DFineBlock = {
	varName: string?,
	block: string,
}

-- Returns every D.fine({…}) call in source, with the assigned variable name if any.
local function extractDFineBlocks(source: string): { DFineBlock }
	local blocks: { DFineBlock } = {}
	local lines: { string } = {}
	for line in source:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local i = 1
	while i <= #lines do
		local line = lines[i]
		-- Capture optional: local VarName = D.fine<<Type>>({ or D.fine({
		local varName = line:match("local%s+([%a_][%w_]*)%s*=.*D%.fine")
		if line:match("D%.fine%s*%b<>%s*%(") or line:match("D%.fine%s*%(") or line:match("D%.fine%s*<[^>]*>%s*%(") or line:match("D%.fine%s*%b<>%s*{") or line:match("D%.fine%s*{") then
			local collecting = false
			local depth = 0
			local collected: { string } = {}

			for j = i, #lines do
				local l = lines[j]
				if not collecting then
					if l:find("{") then
						collecting = true
						for _ in l:gmatch("{") do
							depth += 1
						end
						for _ in l:gmatch("}") do
							depth -= 1
						end
						table.insert(collected, l)
						if depth <= 0 then
							i = j + 1
							break
						end
					end
				else
					for _ in l:gmatch("{") do
						depth += 1
					end
					for _ in l:gmatch("}") do
						depth -= 1
					end
					table.insert(collected, l)
					if depth <= 0 then
						i = j + 1
						break
					end
				end
			end

			if #collected > 0 then
				local blockStr = table.concat(collected, "\n")
				local inner = blockStr:match("(%b{})")
				if inner then
					table.insert(blocks, { varName = varName, block = inner })
				end
			end
		else
			i += 1
		end
	end

	return blocks
end

local function getRootName(block: string): string?
	return block:match("%[D%.Name%]%s*=%s*[\"']([%a_][%w_]*)[\"']")
end

type TypeDecl = { name: string, body: string }

-- Captures top-level `type X = ...` (or `local type X = ...`) declarations so
-- they can be hoisted into the generated Dfine.luau alongside entity types.
-- Single-line bodies are taken as-is. Multi-line bodies are supported when
-- they open `{` or `(` that closes on a later line.
local function extractTypeDeclarations(source: string): { TypeDecl }
	local lines: { string } = {}
	for line in source:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local decls: { TypeDecl } = {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local name, bodyStart = line:match("^%s*type%s+([%a_][%w_]*)%s*=%s*(.*)$")
		if not name then
			name, bodyStart = line:match("^%s*local%s+type%s+([%a_][%w_]*)%s*=%s*(.*)$")
		end

		if name then
			local opens, closes = 0, 0
			for _ in bodyStart:gmatch("[{(]") do opens += 1 end
			for _ in bodyStart:gmatch("[)}]") do closes += 1 end
			local depth = opens - closes

			local collected: { string } = { bodyStart }
			i += 1
			while i <= #lines and depth > 0 do
				local l = lines[i]
				table.insert(collected, l)
				for _ in l:gmatch("[{(]") do depth += 1 end
				for _ in l:gmatch("[)}]") do depth -= 1 end
				i += 1
			end

			local body = trim(table.concat(collected, "\n"))
			if body ~= "" then
				table.insert(decls, { name = name, body = body })
			end
		else
			i += 1
		end
	end

	return decls
end

-- Extracts the { ... } literal for a given top-level field inside a D.fine({...}) call.
-- fieldPattern is a Lua pattern matching the key (e.g., "%[D%.Extends%]").
-- Handles nested braces correctly using line-by-line depth tracking.
local function extractFieldBlock(source: string, fieldPattern: string): string?
	local lines = {}
	for line in source:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local collecting = false
	local depth = 0
	local collected: { string } = {}

	for _, line in ipairs(lines) do
		if not collecting then
			if line:match("^%s*" .. fieldPattern .. "%s*=%s*{") then
				collecting = true
				depth = 0
				for _ in line:gmatch("{") do
					depth += 1
				end
				for _ in line:gmatch("}") do
					depth -= 1
				end
				table.insert(collected, line)
				if depth <= 0 then
					collecting = false
				end
			end
		else
			for _ in line:gmatch("{") do
				depth += 1
			end
			for _ in line:gmatch("}") do
				depth -= 1
			end
			table.insert(collected, line)
			if depth <= 0 then
				collecting = false
				break
			end
		end
	end

	if #collected == 0 then
		return nil
	end

	local joined = table.concat(collected, "\n")
	return joined:match("(%b{})")
end

local SKIP_KEYS: { [string]: boolean } = {
	Name = true,
	Container = true,
	Extends = true,
}

local function isSelfParam(param: string): boolean
	return trim(param:match("^([^:]+)") or param) == "self"
end

-- Builds a typed param list, replacing bare param names with `: any` and
-- replacing the leading `self` with `self: <selfType>`.
local function buildTypedParams(selfType: string, rawParams: string): string
	local parts = { "self: " .. selfType }
	for param in rawParams:gmatch("[^,]+") do
		local p = trim(param)
		if p == "" or isSelfParam(p) then
			continue
		elseif p == "..." then
			table.insert(parts, "...any")
		elseif p:find(":", 1, true) then
			table.insert(parts, p)
		else
			table.insert(parts, p .. ": any")
		end
	end
	return table.concat(parts, ", ")
end

type MethodBuckets = {
	shared: { [string]: MethodInfo },
	server: { [string]: MethodInfo },
	client: { [string]: MethodInfo },
}

-- Splits methods into shared (no prefix), Server_ and Client_ buckets.
-- Shared methods are included in all three scopes.
local function extractMethods(source: string): MethodBuckets
	local shared: { [string]: MethodInfo } = {}
	local server: { [string]: MethodInfo } = {}
	local client: { [string]: MethodInfo } = {}

	for line in source:gmatch("[^\r\n]+") do
		local name, params, ret = line:match("^%s*([%a_][%w_]*)%s*=%s*function%s*%((.-)%)%s*:%s*(.-)%s*$")
		if not name then
			name, params = line:match("^%s*([%a_][%w_]*)%s*=%s*function%s*%((.-)%)%s*$")
			ret = nil
		end

		if name and params and not SKIP_KEYS[name] then
			local returnType = (ret and trim(ret) ~= "") and trim(ret) or "()"
			local serverName = name:match("^Server_(.+)$")
			local clientName = name:match("^Client_(.+)$")
			if serverName then
				server[serverName] = { params = params, returnType = returnType }
			elseif clientName then
				client[clientName] = { params = params, returnType = returnType }
			else
				-- Shared: only in shared bucket; Client/Server inherit via composite type
				shared[name] = { params = params, returnType = returnType }
			end
		end
	end

	return { shared = shared, server = server, client = client }
end

-- Parses the variable names listed in [D.Extends] = { VarA, VarB }
local function extractExtendsVarNames(block: string): { string }
	local varNames: { string } = {}
	local extendsBlock = extractFieldBlock(block, "%[D%.Extends%]")
	if not extendsBlock then
		return varNames
	end
	for varName in extendsBlock:gmatch("[%a_][%w_]*") do
		table.insert(varNames, varName)
	end
	return varNames
end

-- Returns the names of keys at depth-1 of a table literal (non-recursive).
local function getTopLevelKeys(literal: string): { string }
	local keys: { string } = {}
	local depth = 0
	for line in literal:gmatch("[^\r\n]+") do
		if depth == 1 then
			local key = line:match("^%s*([%a_][%w_]*)%s*=")
			if key then
				table.insert(keys, key)
			end
		end
		for _ in line:gmatch("{") do
			depth += 1
		end
		for _ in line:gmatch("}") do
			depth -= 1
		end
	end
	return keys
end

-- Extracts root-level non-function, non-reserved fields from a D.fine block as a { ... } literal.
local function extractRootPropertyLiteral(block: string): string
	local lines: { string } = {}
	for line in block:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local propLines: { string } = {}
	local i = 2 -- skip first line (opening `{`)

	while i <= #lines - 1 do -- skip last line (closing `}`)
		local line = lines[i]
		local key = line:match("^%s*([%a_][%w_]*)%s*=")

		if not key then
			i += 1
			continue
		end

		local isReserved = SKIP_KEYS[key]
		local isFunc = line:match("^%s*[%a_][%w_]*%s*=%s*function")

		if isFunc then
			-- Skip function body by tracking block keyword depth
			local depth = 1
			i += 1
			while i <= #lines and depth > 0 do
				local l = lines[i]
				for _ in l:gmatch("%f[%a]function%f[%A]") do
					depth += 1
				end
				for _ in l:gmatch("%f[%a]if%f[%A]") do
					depth += 1
				end
				for _ in l:gmatch("%f[%a]for%f[%A]") do
					depth += 1
				end
				for _ in l:gmatch("%f[%a]while%f[%A]") do
					depth += 1
				end
				for _ in l:gmatch("%f[%a]do%f[%A]") do
					depth += 1
				end
				for _ in l:gmatch("%f[%a]end%f[%A]") do
					depth -= 1
				end
				i += 1
			end
		elseif isReserved then
			-- Skip reserved entry (handles multi-line table values via brace tracking)
			local braces = 0
			for _ in line:gmatch("{") do
				braces += 1
			end
			for _ in line:gmatch("}") do
				braces -= 1
			end
			i += 1
			while i <= #lines and braces > 0 do
				local l = lines[i]
				for _ in l:gmatch("{") do
					braces += 1
				end
				for _ in l:gmatch("}") do
					braces -= 1
				end
				i += 1
			end
		else
			-- Property: collect full entry (multi-line table values via brace tracking)
			local entryLines: { string } = { line }
			local braces = 0
			for _ in line:gmatch("{") do
				braces += 1
			end
			for _ in line:gmatch("}") do
				braces -= 1
			end
			i += 1
			while i <= #lines and braces > 0 do
				local l = lines[i]
				table.insert(entryLines, l)
				for _ in l:gmatch("{") do
					braces += 1
				end
				for _ in l:gmatch("}") do
					braces -= 1
				end
				i += 1
			end
			for _, el in ipairs(entryLines) do
				table.insert(propLines, el)
			end
		end
	end

	return #propLines > 0 and ("{\n" .. table.concat(propLines, "\n") .. "\n}") or "{}"
end

-- Counts net `{` minus `}` in a string. Naive (does not handle braces inside strings).
local function netBraceDelta(s: string): number
	local opens = 0
	local closes = 0
	for _ in s:gmatch("{") do opens += 1 end
	for _ in s:gmatch("}") do closes += 1 end
	return opens - closes
end

-- Maps a single-line value expression to its widened Luau type.
-- Honors `expr :: SomeType` assertions by returning `SomeType`.
local function widenScalarType(value: string): string
	value = trim(value)
	value = trim((value:gsub("[,;]%s*$", "")))

	-- `expr :: Type` — take the rightmost assertion as the type.
	local _, asserted = value:match("^(.+)::%s*(.+)$")
	if asserted then
		return trim(asserted)
	end

	local first = value:sub(1, 1)
	if first == '"' or first == "'" or value:sub(1, 2) == "[[" or value:sub(1, 2) == "[=" then
		return "string"
	end

	if value == "true" or value == "false" then
		return "boolean"
	end

	if value:match("^%-?%d") or value:match("^%-?%.%d") then
		return "number"
	end

	if value == "nil" then
		return "nil"
	end

	return "any"
end

type LiteralEntry = { key: string, value: string, isTable: boolean }

-- Parses depth-1 entries from a `{...}` literal. Values that are tables
-- are returned as their raw `{...}` substring for recursion.
local function parseTopLevelEntries(literal: string): { LiteralEntry }
	local inner = literal:match("^%s*{(.*)}%s*$")
	if not inner then
		return {}
	end

	local lines: { string } = {}
	for line in inner:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	local entries: { LiteralEntry } = {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local keyName, valueStart = line:match("^%s*([%a_][%w_]*)%s*=%s*(.*)$")

		if not keyName then
			i += 1
			continue
		end

		local delta = netBraceDelta(valueStart)
		if delta > 0 then
			local collected: { string } = { valueStart }
			local depth = delta
			i += 1
			while i <= #lines and depth > 0 do
				local l = lines[i]
				table.insert(collected, l)
				depth += netBraceDelta(l)
				i += 1
			end
			local raw = table.concat(collected, "\n")
			local block = raw:match("(%b{})") or "{}"
			table.insert(entries, { key = keyName, value = block, isTable = true })
		else
			local clean = trim((trim(valueStart):gsub("[,;]%s*$", "")))
			if clean:sub(1, 1) == "{" and clean:sub(-1) == "}" then
				table.insert(entries, { key = keyName, value = clean, isTable = true })
			else
				table.insert(entries, { key = keyName, value = clean, isTable = false })
			end
			i += 1
		end
	end

	return entries
end

-- Converts a `{...}` literal into a Luau type literal at the given indent depth.
-- Tables recurse; scalars use widenScalarType. Nested tables on a single line
-- get reformatted onto multiple lines for readability.
local function literalToTypeAt(literal: string, depth: number): string
	local entries = parseTopLevelEntries(literal)
	if #entries == 0 then
		return "{}"
	end

	local outerIndent = string.rep("\t", depth)
	local innerIndent = string.rep("\t", depth + 1)

	local out: { string } = { "{" }
	for _, entry in ipairs(entries) do
		if entry.isTable then
			local nested = literalToTypeAt(entry.value, depth + 1)
			table.insert(out, innerIndent .. entry.key .. ": " .. nested .. ",")
		else
			table.insert(out, innerIndent .. entry.key .. ": " .. widenScalarType(entry.value) .. ",")
		end
	end
	table.insert(out, outerIndent .. "}")
	return table.concat(out, "\n")
end

local function literalToType(literal: string): string
	return literalToTypeAt(literal, 0)
end

local function buildTypeBlock(rootName: string, fieldName: string, literal: string, extendsSuffix: string?): { string }
	local aliasName = rootName .. fieldName
	local typeExpr = literalToType(literal)
	if extendsSuffix and extendsSuffix ~= "" then
		typeExpr ..= " & " .. extendsSuffix
	end
	return {
		"export type " .. aliasName .. " = " .. typeExpr,
		"",
	}
end

local function buildMethodsTypeBlock(typeName: string, selfType: string, methods: { [string]: MethodInfo }, extendsSuffix: string?): { string }
	local lines = { "export type " .. typeName .. " = {" }

	local names: { string } = {}
	for name in pairs(methods) do
		table.insert(names, name)
	end
	table.sort(names)

	for _, name in ipairs(names) do
		local info = methods[name]
		local typedParams = buildTypedParams(selfType, info.params)
		table.insert(lines, "\t" .. name .. ": (" .. typedParams .. ") -> " .. info.returnType .. ",")
	end

	local suffix = (extendsSuffix and extendsSuffix ~= "") and (" & " .. extendsSuffix) or ""
	table.insert(lines, "}" .. suffix)
	table.insert(lines, "")
	return lines
end

local function buildConfigTypeBlock(rootName: string, buckets: MethodBuckets, propNames: { string }): { string }
	local lines = {
		"export type " .. rootName .. "Config = {",
	}
	for _, propName in ipairs(propNames) do
		table.insert(lines, "\t" .. propName .. ": any,")
	end

	type ConfigMethod = { key: string, selfType: string, info: MethodInfo }
	local configMethods: { ConfigMethod } = {}

	local sharedNames: { string } = {}
	for name in pairs(buckets.shared) do
		table.insert(sharedNames, name)
	end
	table.sort(sharedNames)
	for _, name in ipairs(sharedNames) do
		table.insert(configMethods, { key = name, selfType = rootName, info = buckets.shared[name] })
	end

	local serverNames: { string } = {}
	for name in pairs(buckets.server) do
		table.insert(serverNames, name)
	end
	table.sort(serverNames)
	for _, name in ipairs(serverNames) do
		table.insert(configMethods, { key = "Server_" .. name, selfType = rootName .. "Server", info = buckets.server[name] })
	end

	local clientNames: { string } = {}
	for name in pairs(buckets.client) do
		table.insert(clientNames, name)
	end
	table.sort(clientNames)
	for _, name in ipairs(clientNames) do
		table.insert(configMethods, { key = "Client_" .. name, selfType = rootName .. "Client", info = buckets.client[name] })
	end

	for _, entry in ipairs(configMethods) do
		local typedParams = buildTypedParams(entry.selfType, entry.info.params)
		table.insert(lines, "\t" .. entry.key .. ": (" .. typedParams .. ") -> " .. entry.info.returnType .. ",")
	end

	table.insert(lines, "\t[string]: string | Instance | { any },")
	table.insert(lines, "}")
	table.insert(lines, "")
	return lines
end

local function getContainerTypeName(block: string): string
	-- Inline: [D.Container] = Instance.new("Model")
	local className = block:match("%[D%.Container%]%s*=%s*Instance%.new%(%s*[\"']([%a_][%w_]*)[\"']%s*%)")
	return (className and className ~= "") and className or "Folder"
end

local function generateTypesForEntity(block: string, varToEntity: { [string]: string }): ({ string }?, string)
	local rootName = getRootName(block)
	if not rootName then
		return nil, "Could not find `[D.Name] = '...'`"
	end

	local propertiesLiteral = extractRootPropertyLiteral(block)
	local buckets = extractMethods(block)

	-- Skip entities with no meaningful content
	local hasProperties = propertiesLiteral ~= "{}"
	local hasMethods = next(buckets.shared) ~= nil or next(buckets.server) ~= nil or next(buckets.client) ~= nil
	if not hasProperties and not hasMethods then
		local extendsVars = extractExtendsVarNames(block)
		if #extendsVars == 0 then
			return nil, "No Properties or Methods found for " .. rootName
		end
	end

	-- Resolve Extends var names to entity names
	local extendsEntityNames: { string } = {}
	for _, varName in ipairs(extractExtendsVarNames(block)) do
		local entityName = varToEntity[varName]
		if entityName and entityName ~= rootName then
			table.insert(extendsEntityNames, entityName)
		end
	end

	local function joinSuffix(suffix: string): string?
		if #extendsEntityNames == 0 then
			return nil
		end
		local parts: { string } = {}
		for _, name in ipairs(extendsEntityNames) do
			table.insert(parts, name .. suffix)
		end
		return table.concat(parts, " & ")
	end

	local containerType = getContainerTypeName(block)
	local propNames = getTopLevelKeys(propertiesLiteral)

	local generatedLines: { string } = {}

	for _, line in ipairs(buildTypeBlock(rootName, "Properties", propertiesLiteral, joinSuffix("Properties"))) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildMethodsTypeBlock(rootName .. "Methods", rootName, buckets.shared, joinSuffix("Methods"))) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildMethodsTypeBlock(rootName .. "ClientMethods", rootName .. "Client", buckets.client, joinSuffix("ClientMethods"))) do
		table.insert(generatedLines, line)
	end

	for _, line in ipairs(buildMethodsTypeBlock(rootName .. "ServerMethods", rootName .. "Server", buckets.server, joinSuffix("ServerMethods"))) do
		table.insert(generatedLines, line)
	end

	table.insert(generatedLines, "export type " .. rootName .. " = " .. rootName .. "Properties & " .. rootName .. "Methods & " .. containerType)
	table.insert(generatedLines, "")
	table.insert(generatedLines, "export type " .. rootName .. "Client = " .. rootName .. " & " .. rootName .. "ClientMethods")
	table.insert(generatedLines, "")
	table.insert(generatedLines, "export type " .. rootName .. "Server = " .. rootName .. " & " .. rootName .. "ServerMethods")
	table.insert(generatedLines, "")

	for _, line in ipairs(buildConfigTypeBlock(rootName, buckets, propNames)) do
		table.insert(generatedLines, line)
	end

	return generatedLines, rootName
end

local function generateTypesForFile(inputPath: string): ({ string }?, string)
	local source = fs.readFile(inputPath)
	local dfineBlocks = extractDFineBlocks(source)

	if #dfineBlocks == 0 then
		return nil, "No D.fine({...}) calls found in " .. inputPath
	end

	-- Build varName -> entityName map for this file
	local varToEntity: { [string]: string } = {}
	for _, entry in ipairs(dfineBlocks) do
		local entityName = getRootName(entry.block)
		if entry.varName and entityName then
			varToEntity[entry.varName] = entityName
		end
	end

	local allLines: { string } = {}
	local names: { string } = {}

	for _, entry in ipairs(dfineBlocks) do
		local entityLines, nameOrErr = generateTypesForEntity(entry.block, varToEntity)
		if entityLines then
			table.insert(names, nameOrErr)
			for _, line in ipairs(entityLines) do
				table.insert(allLines, line)
			end
		else
			print("  Skipped entity in " .. inputPath .. ": " .. nameOrErr)
		end
	end

	if #names == 0 then
		return nil, "No valid entities found in " .. inputPath
	end

	return allLines, table.concat(names, ", ")
end

local function buildDTypeLines(entityNames: { string }): { string }
	local header: { string } = {
		"export type D = {",
		"\tNil: any,",
		"\tName: string,",
		"\tContainer: string,",
		"\tExtends: string,",
	}

	if #entityNames == 0 then
		table.insert(header, "}")
		table.insert(header, "")
		return header
	end

	-- Most-derived first: codegen visits parents before children, so reverse.
	local ordered: { string } = {}
	for i = #entityNames, 1, -1 do
		table.insert(ordered, entityNames[i])
	end

	local function buildOverloadField(fieldName: string, returnFor: (string) -> string): { string }
		local fieldLines = { "\t" .. fieldName .. ":" }
		for i, name in ipairs(ordered) do
			local prefix = i == 1 and "\t\t" or "\t\t& "
			local suffix = i == #ordered and "," or ""
			table.insert(fieldLines, prefix .. "((config: " .. name .. "Config) -> " .. returnFor(name) .. ")" .. suffix)
		end
		return fieldLines
	end

	for _, line in ipairs(buildOverloadField("fine", function(name) return name .. "Config" end)) do
		table.insert(header, line)
	end

	for _, line in ipairs(buildOverloadField("new", function(name)
		return name .. " & " .. name .. "Client & " .. name .. "Server"
	end)) do
		table.insert(header, line)
	end

	table.insert(header, "}")
	table.insert(header, "")
	return header
end

local function findLuauFiles(dir: string): { string }
	local files: { string } = {}

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

-- ============================================================
-- Main
-- ============================================================

local scriptsDir = "scripts"

if not fs.isDir(scriptsDir) then
	error("scripts folder not found")
end

local files = findLuauFiles(scriptsDir)

table.sort(files)

local allGeneratedLines: { string } = {}
local allEntityNames: { string } = {}

-- Hoist user `type X = ...` declarations from spec files so type assertions
-- like `:: AmphibiousCarMode` resolve when the generator references them
-- inside Dfine.luau. Same name from multiple files: first wins, others warn.
local hoistedTypeLines: { string } = {}
local seenTypes: { [string]: { body: string, source: string } } = {}

for _, inputPath in ipairs(files) do
	local source = fs.readFile(inputPath)
	for _, decl in ipairs(extractTypeDeclarations(source)) do
		local existing = seenTypes[decl.name]
		if existing then
			if existing.body ~= decl.body then
				print(`  Warning: type "{decl.name}" redeclared in {inputPath}; keeping definition from {existing.source}`)
			end
		else
			seenTypes[decl.name] = { body = decl.body, source = inputPath }
			table.insert(hoistedTypeLines, "export type " .. decl.name .. " = " .. decl.body)
			table.insert(hoistedTypeLines, "")
		end
	end
end

if #hoistedTypeLines > 0 then
	table.insert(allGeneratedLines, "-- ----------------------------------------")
	table.insert(allGeneratedLines, "-- User type aliases (hoisted from spec files)")
	table.insert(allGeneratedLines, "-- ----------------------------------------")
	table.insert(allGeneratedLines, "")
	for _, line in ipairs(hoistedTypeLines) do
		table.insert(allGeneratedLines, line)
	end
end

for _, inputPath in ipairs(files) do
	local generatedLines, rootNameOrError = generateTypesForFile(inputPath)

	if generatedLines then
		table.insert(allGeneratedLines, "-- ----------------------------------------")
		table.insert(allGeneratedLines, "-- Module: " .. rootNameOrError)
		table.insert(allGeneratedLines, "-- Source: " .. inputPath)
		table.insert(allGeneratedLines, "-- ----------------------------------------")
		table.insert(allGeneratedLines, "")

		for _, line in ipairs(generatedLines) do
			table.insert(allGeneratedLines, line)
		end

		for name in rootNameOrError:gmatch("[%a_][%w_]*") do
			table.insert(allEntityNames, name)
		end

		print("Included " .. inputPath .. " (" .. rootNameOrError .. ")")
	else
		print("Skipped " .. inputPath .. ": " .. rootNameOrError)
	end
end

for _, line in ipairs(buildDTypeLines(allEntityNames)) do
	table.insert(allGeneratedLines, line)
end

local outputPath = "Dfine.luau"
local existing = fs.readFile(outputPath)

local beginMarker = "-- Begin Types"
local endMarker = "-- End Types"

local before = existing:match("^(.-\n" .. beginMarker .. "\n)")
local after = existing:match("\n" .. endMarker .. "(\n.*)$")

if not before or not after then
	error("Could not find '-- Begin Types' / '-- End Types' markers (each on its own line) in " .. outputPath)
end

local generated = table.concat(allGeneratedLines, "\n")
fs.writeFile(outputPath, before .. "\n" .. generated .. "\n" .. endMarker .. after)
print("Wrote types into " .. outputPath)
