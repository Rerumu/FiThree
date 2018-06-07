-- Lua 5.3 Test File

local function closure(a, b, c)
	print(a ~ b ~ c)
	return a 
end

print(closure(1, 2, 3))

print"???"