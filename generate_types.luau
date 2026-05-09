-- Vibecoded

local fs = require("@lune/fs")

-- ============================================================
-- Helpers
-- ============================================================

local function trim(text: string): string
	return text:match("^%s*(.-)%s*$") or ""
end

local function splitLines(s: string): { string }
	local lines: { string } = {}
	for line in s:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	return lines
end

-- Net `{` minus `}` count. Naive — does not look inside strings or comments.
local function netBraceDelta(s: string): number
	local delta = 0
	for _ in s:gmatch("{") do delta += 1 end
	for _ in s:gmatch("}") do delta -= 1 end
	return delta
end

-- Net `{`+`(` minus `}`+`)` count.
local function netBracketDelta(s: string): number
	local delta = 0
	for _ in s:gmatch("[{(]") do delta += 1 end
	for _ in s:gmatch("[)}]") do delta -= 1 end
	return delta
end

local function sortedKeys<V>(t: { [string]: V }): { string }
	local keys: { string } = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- ============================================================
-- Types and constants
-- ============================================================

type DFineBlock = {
	varName: string?,
	block: string,
}

type TypeDecl = {
	name: string,
	body: string,
}

type MethodInfo = {
	params: string,
	returnType: string,
}

type MethodBuckets = {
	shared: { [string]: MethodInfo },
	server: { [string]: MethodInfo },
	client: { [string]: MethodInfo },
}

type LiteralEntry = {
	key: string,
	value: string,
	isTable: boolean,
}

local SKIP_KEYS: { [string]: boolean } = {
	Name = true,
	Container = true,
	Extends = true,
}

-- ============================================================
-- Source extraction
-- ============================================================

-- Returns every D.fine({...}) call in source, with the assigned variable name if any.
local function extractDFineBlocks(source: string): { DFineBlock }
	local lines = splitLines(source)
	local blocks: { DFineBlock } = {}

	local i = 1
	while i <= #lines do
		local line = lines[i]
		local varName = line:match("local%s+([%a_][%w_]*)%s*=.*D%.fine")
		local startsCall = line:match("D%.fine.-[%({]") ~= nil

		if startsCall then
			local depth = 0
			local started = false
			local collected: { string } = {}

			for j = i, #lines do
				local l = lines[j]
				if not started and l:find("{") then
					started = true
				end
				if started then
					depth += netBraceDelta(l)
					table.insert(collected, l)
					if depth <= 0 then
						i = j + 1
						break
					end
				end
			end

			local inner = table.concat(collected, "\n"):match("(%b{})")
			if inner then
				table.insert(blocks, { varName = varName, block = inner })
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

-- Captures top-level `type X = ...` (or `local type X = ...`) declarations so
-- they can be hoisted into Dfine.luau alongside generated entity types.
-- Single-line bodies are taken as-is. Multi-line bodies are supported when
-- they open `{` or `(` that closes on a later line.
local function extractTypeDeclarations(source: string): { TypeDecl }
	local lines = splitLines(source)
	local decls: { TypeDecl } = {}

	local i = 1
	while i <= #lines do
		local line = lines[i]
		local name, bodyStart = line:match("^%s*type%s+([%a_][%w_]*)%s*=%s*(.*)$")
		if not name then
			name, bodyStart = line:match("^%s*local%s+type%s+([%a_][%w_]*)%s*=%s*(.*)$")
		end

		if name then
			local depth = netBracketDelta(bodyStart)
			local collected: { string } = { bodyStart }
			i += 1
			while i <= #lines and depth > 0 do
				local l = lines[i]
				table.insert(collected, l)
				depth += netBracketDelta(l)
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

-- Extracts the { ... } literal for a given top-level field inside a D.fine block.
-- fieldPattern is a Lua pattern matching the key (e.g. "%[D%.Extends%]").
local function extractFieldBlock(source: string, fieldPattern: string): string?
	local collecting = false
	local depth = 0
	local collected: { string } = {}

	for _, line in ipairs(splitLines(source)) do
		if not collecting then
			if line:match("^%s*" .. fieldPattern .. "%s*=%s*{") then
				collecting = true
				depth = netBraceDelta(line)
				table.insert(collected, line)
				if depth <= 0 then collecting = false end
			end
		else
			depth += netBraceDelta(line)
			table.insert(collected, line)
			if depth <= 0 then break end
		end
	end

	if #collected == 0 then
		return nil
	end
	return table.concat(collected, "\n"):match("(%b{})")
end

-- Parses the variable names listed in [D.Extends] = { VarA, VarB }
local function extractExtendsVarNames(block: string): { string }
	local extendsBlock = extractFieldBlock(block, "%[D%.Extends%]")
	if not extendsBlock then return {} end

	local varNames: { string } = {}
	for varName in extendsBlock:gmatch("[%a_][%w_]*") do
		table.insert(varNames, varName)
	end
	return varNames
end

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

-- Splits methods into shared (no prefix), Server_ and Client_ buckets.
local function extractMethods(source: string): MethodBuckets
	local buckets: MethodBuckets = { shared = {}, server = {}, client = {} }

	for line in source:gmatch("[^\r\n]+") do
		local name, params, ret = line:match("^%s*([%a_][%w_]*)%s*=%s*function%s*%((.-)%)%s*:%s*(.-)%s*$")
		if not name then
			name, params = line:match("^%s*([%a_][%w_]*)%s*=%s*function%s*%((.-)%)%s*$")
			ret = nil
		end

		if name and params and not SKIP_KEYS[name] then
			local info: MethodInfo = {
				params = params,
				returnType = (ret and trim(ret) ~= "") and trim(ret) or "()",
			}
			local serverName = name:match("^Server_(.+)$")
			local clientName = name:match("^Client_(.+)$")
			if serverName then
				buckets.server[serverName] = info
			elseif clientName then
				buckets.client[clientName] = info
			else
				buckets.shared[name] = info
			end
		end
	end

	return buckets
end

-- Returns the names of keys at depth-1 of a table literal (non-recursive).
local function getTopLevelKeys(literal: string): { string }
	local keys: { string } = {}
	local depth = 0
	for _, line in ipairs(splitLines(literal)) do
		if depth == 1 then
			local key = line:match("^%s*([%a_][%w_]*)%s*=")
			if key then
				table.insert(keys, key)
			end
		end
		depth += netBraceDelta(line)
	end
	return keys
end

-- Finds the matching `end` for a function body by tracking Luau block keywords.
-- Starts at line index `from` with depth = 1 already counted for the opening
-- `function`. Returns the index just past the closing `end`.
local function skipFunctionBody(lines: { string }, from: number): number
	local BLOCK_OPENERS = { "function", "if", "for", "while", "do" }
	local depth = 1
	local i = from
	while i <= #lines and depth > 0 do
		local l = lines[i]
		for _, kw in ipairs(BLOCK_OPENERS) do
			for _ in l:gmatch("%f[%a]" .. kw .. "%f[%A]") do
				depth += 1
			end
		end
		for _ in l:gmatch("%f[%a]end%f[%A]") do
			depth -= 1
		end
		i += 1
	end
	return i
end

-- Collects `from` lines onward while braces remain open. Returns (collected, i)
-- where i is the next index to read.
local function collectBracedLines(lines: { string }, from: number, append: ((string) -> ())?): number
	local depth = netBraceDelta(lines[from])
	if append then append(lines[from]) end
	local i = from + 1
	while i <= #lines and depth > 0 do
		local l = lines[i]
		if append then append(l) end
		depth += netBraceDelta(l)
		i += 1
	end
	return i
end

-- Extracts root-level non-function, non-reserved fields from a D.fine block as a `{...}` literal.
local function extractRootPropertyLiteral(block: string): string
	local lines = splitLines(block)
	local propLines: { string } = {}
	local i = 2 -- skip first line (opening `{`)

	while i <= #lines - 1 do -- skip last line (closing `}`)
		local line = lines[i]
		local key = line:match("^%s*([%a_][%w_]*)%s*=")

		if not key then
			i += 1
			continue
		end

		if line:match("^%s*[%a_][%w_]*%s*=%s*function") then
			i = skipFunctionBody(lines, i + 1)
		elseif SKIP_KEYS[key] then
			i = collectBracedLines(lines, i)
		else
			i = collectBracedLines(lines, i, function(l)
				table.insert(propLines, l)
			end)
		end
	end

	if #propLines == 0 then return "{}" end
	return "{\n" .. table.concat(propLines, "\n") .. "\n}"
end

-- ============================================================
-- Literal -> Luau type
-- ============================================================

-- Maps a single-line value expression to its widened Luau type.
-- Honors `expr :: SomeType` assertions by returning `SomeType`.
local function widenScalarType(value: string): string
	value = trim((trim(value):gsub("[,;]%s*$", "")))

	-- `expr :: Type` — take the rightmost assertion as the type.
	local _, asserted = value:match("^(.+)::%s*(.+)$")
	if asserted then return trim(asserted) end

	local first = value:sub(1, 1)
	if first == '"' or first == "'" or value:sub(1, 2) == "[[" or value:sub(1, 2) == "[=" then
		return "string"
	end
	if value == "true" or value == "false" then return "boolean" end
	if value:match("^%-?%d") or value:match("^%-?%.%d") then return "number" end
	if value == "nil" then return "nil" end
	return "any"
end

-- Parses depth-1 entries from a `{...}` literal. Table values are returned
-- as their raw `{...}` substring for recursion.
local function parseTopLevelEntries(literal: string): { LiteralEntry }
	local inner = literal:match("^%s*{(.*)}%s*$")
	if not inner then return {} end

	local lines = splitLines(inner)
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
			local block = table.concat(collected, "\n"):match("(%b{})") or "{}"
			table.insert(entries, { key = keyName, value = block, isTable = true })
		else
			local clean = trim((trim(valueStart):gsub("[,;]%s*$", "")))
			local isTable = clean:sub(1, 1) == "{" and clean:sub(-1) == "}"
			table.insert(entries, { key = keyName, value = clean, isTable = isTable })
			i += 1
		end
	end

	return entries
end

-- Converts a `{...}` literal into a Luau type literal at the given indent depth.
local function literalToTypeAt(literal: string, depth: number): string
	local entries = parseTopLevelEntries(literal)
	if #entries == 0 then return "{}" end

	local outerIndent = string.rep("\t", depth)
	local innerIndent = string.rep("\t", depth + 1)

	local out: { string } = { "{" }
	for _, entry in ipairs(entries) do
		local typeStr = if entry.isTable
			then literalToTypeAt(entry.value, depth + 1)
			else widenScalarType(entry.value)
		table.insert(out, innerIndent .. entry.key .. ": " .. typeStr .. ",")
	end
	table.insert(out, outerIndent .. "}")
	return table.concat(out, "\n")
end

local function literalToType(literal: string): string
	return literalToTypeAt(literal, 0)
end

-- ============================================================
-- Type-block builders
-- ============================================================

local function withSuffix(expr: string, extendsSuffix: string?): string
	if extendsSuffix and extendsSuffix ~= "" then
		return expr .. " & " .. extendsSuffix
	end
	return expr
end

local function buildPropertiesBlock(rootName: string, literal: string, extendsSuffix: string?): { string }
	return {
		"export type " .. rootName .. "Properties = " .. withSuffix(literalToType(literal), extendsSuffix),
		"",
	}
end

local function buildMethodsBlock(typeName: string, selfType: string, methods: { [string]: MethodInfo }, extendsSuffix: string?): { string }
	local lines = { "export type " .. typeName .. " = {" }
	for _, name in ipairs(sortedKeys(methods)) do
		local info = methods[name]
		local typedParams = buildTypedParams(selfType, info.params)
		table.insert(lines, "\t" .. name .. ": (" .. typedParams .. ") -> " .. info.returnType .. ",")
	end
	table.insert(lines, withSuffix("}", extendsSuffix))
	table.insert(lines, "")
	return lines
end

local function buildConfigBlock(rootName: string, buckets: MethodBuckets, propNames: { string }): { string }
	local lines = { "export type " .. rootName .. "Config = {" }
	for _, propName in ipairs(propNames) do
		table.insert(lines, "\t" .. propName .. ": any,")
	end

	local function emitBucket(prefix: string, selfType: string, methods: { [string]: MethodInfo })
		for _, name in ipairs(sortedKeys(methods)) do
			local info = methods[name]
			local typedParams = buildTypedParams(selfType, info.params)
			table.insert(lines, "\t" .. prefix .. name .. ": (" .. typedParams .. ") -> " .. info.returnType .. ",")
		end
	end

	emitBucket("", rootName, buckets.shared)
	emitBucket("Server_", rootName .. "Server", buckets.server)
	emitBucket("Client_", rootName .. "Client", buckets.client)

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

-- ============================================================
-- Per-entity / per-file generation
-- ============================================================

local function generateTypesForEntity(block: string, varToEntity: { [string]: string }): ({ string }?, string)
	local rootName = getRootName(block)
	if not rootName then
		return nil, "Could not find `[D.Name] = '...'`"
	end

	local propertiesLiteral = extractRootPropertyLiteral(block)
	local buckets = extractMethods(block)
	local extendsVars = extractExtendsVarNames(block)

	local hasProperties = propertiesLiteral ~= "{}"
	local hasMethods = next(buckets.shared) or next(buckets.server) or next(buckets.client)
	if not hasProperties and not hasMethods and #extendsVars == 0 then
		return nil, "No Properties or Methods found for " .. rootName
	end

	local extendsEntityNames: { string } = {}
	for _, varName in ipairs(extendsVars) do
		local entityName = varToEntity[varName]
		if entityName and entityName ~= rootName then
			table.insert(extendsEntityNames, entityName)
		end
	end

	local function joinSuffix(suffix: string): string?
		if #extendsEntityNames == 0 then return nil end
		local parts: { string } = {}
		for _, name in ipairs(extendsEntityNames) do
			table.insert(parts, name .. suffix)
		end
		return table.concat(parts, " & ")
	end

	local containerType = getContainerTypeName(block)
	local propNames = getTopLevelKeys(propertiesLiteral)

	local out: { string } = {}
	local function append(lines: { string })
		for _, line in ipairs(lines) do
			table.insert(out, line)
		end
	end

	append(buildPropertiesBlock(rootName, propertiesLiteral, joinSuffix("Properties")))
	append(buildMethodsBlock(rootName .. "Methods", rootName, buckets.shared, joinSuffix("Methods")))
	append(buildMethodsBlock(rootName .. "ClientMethods", rootName .. "Client", buckets.client, joinSuffix("ClientMethods")))
	append(buildMethodsBlock(rootName .. "ServerMethods", rootName .. "Server", buckets.server, joinSuffix("ServerMethods")))

	table.insert(out, "export type " .. rootName .. " = " .. rootName .. "Properties & " .. rootName .. "Methods & " .. containerType)
	table.insert(out, "")
	table.insert(out, "export type " .. rootName .. "Client = " .. rootName .. " & " .. rootName .. "ClientMethods")
	table.insert(out, "")
	table.insert(out, "export type " .. rootName .. "Server = " .. rootName .. " & " .. rootName .. "ServerMethods")
	table.insert(out, "")

	append(buildConfigBlock(rootName, buckets, propNames))

	return out, rootName
end

local function generateTypesForSource(inputPath: string, source: string): ({ string }?, string)
	local dfineBlocks = extractDFineBlocks(source)
	if #dfineBlocks == 0 then
		return nil, "No D.fine({...}) calls found in " .. inputPath
	end

	local varToEntity: { [string]: string } = {}
	for _, entry in ipairs(dfineBlocks) do
		local entityName = getRootName(entry.block)
		if entry.varName and entityName then
			varToEntity[entry.varName] = entityName
		end
	end

	local out: { string } = {}
	local names: { string } = {}

	for _, entry in ipairs(dfineBlocks) do
		local entityLines, nameOrErr = generateTypesForEntity(entry.block, varToEntity)
		if entityLines then
			table.insert(names, nameOrErr)
			for _, line in ipairs(entityLines) do
				table.insert(out, line)
			end
		else
			print("  Skipped entity in " .. inputPath .. ": " .. nameOrErr)
		end
	end

	if #names == 0 then
		return nil, "No valid entities found in " .. inputPath
	end

	return out, table.concat(names, ", ")
end

local function buildDTypeLines(entityNames: { string }): { string }
	local out: { string } = {
		"export type D = {",
		"\tNil: any,",
		"\tName: string,",
		"\tContainer: string,",
		"\tExtends: string,",
	}

	if #entityNames == 0 then
		table.insert(out, "}")
		table.insert(out, "")
		return out
	end

	-- Most-derived first: codegen visits parents before children, so reverse.
	local ordered: { string } = {}
	for i = #entityNames, 1, -1 do
		table.insert(ordered, entityNames[i])
	end

	local function emitOverloadField(fieldName: string, returnFor: (string) -> string)
		table.insert(out, "\t" .. fieldName .. ":")
		for i, name in ipairs(ordered) do
			local prefix = i == 1 and "\t\t" or "\t\t& "
			local suffix = i == #ordered and "," or ""
			table.insert(out, prefix .. "((config: " .. name .. "Config) -> " .. returnFor(name) .. ")" .. suffix)
		end
	end

	emitOverloadField("fine", function(name) return name .. "Config" end)
	emitOverloadField("new", function(name)
		return name .. " & " .. name .. "Client & " .. name .. "Server"
	end)

	table.insert(out, "}")
	table.insert(out, "")
	return out
end

local function findLuauFiles(dir: string): { string }
	local files: { string } = {}
	if not fs.isDir(dir) then return files end

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

local paths = findLuauFiles(scriptsDir)
table.sort(paths)

-- Read each file once and reuse across the hoist + entity passes.
type SourceFile = { path: string, source: string }
local sources: { SourceFile } = {}
for _, path in ipairs(paths) do
	table.insert(sources, { path = path, source = fs.readFile(path) })
end

local allGeneratedLines: { string } = {}
local allEntityNames: { string } = {}

-- Hoist user `type X = ...` declarations from spec files so type assertions
-- like `:: AmphibiousCarMode` resolve when the generator references them
-- inside Dfine.luau. Same name from multiple files: first wins, others warn.
local hoistedTypeLines: { string } = {}
local seenTypes: { [string]: { body: string, source: string } } = {}

for _, file in ipairs(sources) do
	for _, decl in ipairs(extractTypeDeclarations(file.source)) do
		local existing = seenTypes[decl.name]
		if existing then
			if existing.body ~= decl.body then
				print(`  Warning: type "{decl.name}" redeclared in {file.path}; keeping definition from {existing.source}`)
			end
		else
			seenTypes[decl.name] = { body = decl.body, source = file.path }
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

for _, file in ipairs(sources) do
	local generatedLines, rootNameOrError = generateTypesForSource(file.path, file.source)

	if generatedLines then
		table.insert(allGeneratedLines, "-- ----------------------------------------")
		table.insert(allGeneratedLines, "-- Module: " .. rootNameOrError)
		table.insert(allGeneratedLines, "-- Source: " .. file.path)
		table.insert(allGeneratedLines, "-- ----------------------------------------")
		table.insert(allGeneratedLines, "")

		for _, line in ipairs(generatedLines) do
			table.insert(allGeneratedLines, line)
		end

		for name in rootNameOrError:gmatch("[%a_][%w_]*") do
			table.insert(allEntityNames, name)
		end

		print("Included " .. file.path .. " (" .. rootNameOrError .. ")")
	else
		print("Skipped " .. file.path .. ": " .. rootNameOrError)
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

fs.writeFile(outputPath, before .. "\n" .. table.concat(allGeneratedLines, "\n") .. "\n" .. endMarker .. after)
print("Wrote types into " .. outputPath)
