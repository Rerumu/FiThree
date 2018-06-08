local f = {};
local m = 5;

while true do
	for x, y in ipairs{1, 2, 3, 4, 0} do
		if (x > y) then
			goto out;
		else
			table.insert(f, function()
				m = m + 1;
			end);
		end
	end
end

::out::
for i = 1, #f do
	f[i]();
end
print(m)