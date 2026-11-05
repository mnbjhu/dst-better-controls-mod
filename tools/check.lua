-- Syntax check for every Lua file in the mod. Run from the mod folder:
--
--     luajit tools/check.lua
--
-- LuaJIT matches the Lua 5.1 the game runs. This only compiles the files (it
-- doesn't run them), so it catches typos and syntax errors, not logic bugs.

local function ListFiles()
    local files = {}
    local pipe = io.popen('git ls-files --cached --others --exclude-standard "*.lua"')
    if pipe == nil then
        error("couldn't run git ls-files; run this from the mod folder")
    end
    for line in pipe:lines() do
        table.insert(files, line)
    end
    pipe:close()
    return files
end

local files = ListFiles()
local failed = 0
for _, path in ipairs(files) do
    local chunk, err = loadfile(path)
    if chunk == nil then
        failed = failed + 1
        print("FAIL " .. err)
    end
end

print(string.format("%d files checked, %d with errors", #files, failed))
os.exit(failed == 0 and 0 or 1)
