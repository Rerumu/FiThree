local fithree = require("Source")
local usage = "usage: luajit FiThree.lua <Lua53BytecodeFile>"

if #arg < 1 then
	print(usage)
	return
end

local file = io.open(arg[1], "rb")

if not file then
	print("error: file not found")
	return 
end

local bytecode = file:read("*a")
file:close()

fithree.luaF_dispatch(bytecode, getfenv(0))()
