local luaF_newLclosure; -- makes a new closure
local luaF_dispatch; -- custom quick dispatching
local luaU_undump; -- gets closure from bytecode
local luaF_wrap; -- custom wrapping
local bit = bit32 or bit; -- MUST support a 32 bit bitlib
-- Note on the bit lib, it does not matter whether it's in C
-- or a Lua module, so long as it does what it's supposed to.
-- Report any bugs on the GitHub issues page for https://www.github.com/Rerumu/FiThree
do
	local op_list = {
		[0] = 'iABC', 'iABx', 'iABx', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iAsBx', 'iABC',
		'iABC', 'iABC', 'iABC', 'iABC',
		'iABC', 'iABC', 'iABC', 'iAsBx',
		'iAsBx', 'iABC', 'iAsBx', 'iABC',
		'iABx', 'iABC', 'iAx';
	};

	local function fail(msg)
		error(msg .. ' precompiled chunk', 0);
	end

	function luaF_newLclosure(nups)
		local c = {};
		c.nupvalues = nups;
		c.upvals = {};
		return c;
	end

	function luaU_undump(chunk)
		local specs = { -- static and dynamic specifications
			signature = '\27Lua';
			integrity = '\25\147\13\10\26\10';
			end_int = 0x5678;
			end_num = 370.5;
			version = 0x53;
			little = true;
			format = 0;
		};

		local band, rsh = bit.band, bit.rshift;
		local l_byte = string.byte;
		local l_sub = string.sub;
		local position = 1;
		local readproto;
		local lclosure;

		local function readbyte()
			position = position + 1;
			return l_byte(chunk, position - 1, position - 1);
		end

		local function readstring()
			local size = readbyte();
			local str;

			if (size == 0xFF) then
				size = specs.readsize_t();
			end

			if (size == 0) then
				str = '';
			else
				str = l_sub(chunk, position, position + size - 2);
				position = position + size - 1;
			end

			return str;
		end

		local function readcode()
			local sizecode = specs.readint();
			local codel = {};

			for i = 1, sizecode do
				local code = specs.readInstruction();
				local op = band(code, 0x3F);
				local type = op_list[op];
				local tab = {
					i = op;
					A = band(rsh(code, 6), 0xFF);
				};

				if (type == 'iABC') then
					tab.B = band(rsh(code, 23), 0x1FF);
					tab.C = band(rsh(code, 14), 0x1FF);
				elseif (type == 'iABx') then
					tab.Bx = band(rsh(code, 14), 0x3FFFF);
				elseif (type == 'iAsBx') then
					tab.sBx = band(rsh(code, 14), 0x3FFFF) - 131071;
				elseif (type == 'iAx') then
					tab.Ax = band(rsh(code, 6), 0x3FFFFFF);
				end

				codel[i - 1] = tab;
			end

			return sizecode, codel;
		end

		local function readconstants()
			local sizek = specs.readint();
			local kl = {};

			for i = 1, sizek do
				local type = readbyte();
				local kst;

				if (type == 0x1) then
					kst = readbyte() ~= 0;
				elseif (type == 0x3) then
					kst = specs.readlua_Number();
				elseif (type == 0x13) then
					kst = specs.readlua_Integer();
				elseif (type == 0x4) or (type == 0x14) then
					kst = readstring();
				end

				kl[i - 1] = kst;
			end

			return sizek, kl;
		end

		local function readupvalues()
			local sizeupvalues = specs.readint();
			local upvaluel = {};

			for i = 1, sizeupvalues do
				upvaluel[i - 1] = {
					onstack = readbyte() ~= 0,
					idx = readbyte()
				};
			end

			return sizeupvalues, upvaluel;
		end

		local function readprotos()
			local sizep = specs.readint();
			local pl = {};

			for i = 1, sizep do
				pl[i - 1] = readproto();
			end

			return sizep, pl;
		end

		-- Debug info
		local function readlineinfo()
			local info = specs.readint();
			local ll = {};

			for i = 1, info do
				ll[i - 1] = specs.readint();
			end

			return info, ll;
		end

		local function readlocvars()
			local locs = specs.readint();
			local lvl = {};

			for i = 1, locs do
				lvl[i - 1] = {
					varname = readstring(),
					startpc = specs.readint(),
					endpc = specs.readint()
				};
			end

			return locs, lvl;
		end

		local function readupnames()
			local ups = specs.readint();
			local ul = {};

			for i = 1, ups do
				ul[i] = readstring();
			end

			return ups, ul;
		end

		function readproto()
			local size, value;
			local lua_proto = {
				source = readstring();
				linedefined = specs.readint();
				lastlinedefined = specs.readint();
				numparams = readbyte();
				is_vararg = readbyte();
				maxstacksize = readbyte();
			};

			size, value = readcode(); -- code
			lua_proto.sizecode = size;
			lua_proto.code = value;

			size, value = readconstants(); -- k
			lua_proto.sizek = size;
			lua_proto.k = value;

			size, value = readupvalues(); -- upvalues
			lua_proto.sizeupvalues = size;
			lua_proto.upvalues = value;

			size, value = readprotos(); -- p
			lua_proto.sizep = size;
			lua_proto.p = value;

			size, value = readlineinfo(); -- lineinfo
			lua_proto.sizelineinfo = size;
			lua_proto.lineinfo = value;

			size, value = readlocvars(); -- locvars
			lua_proto.sizelocvars = size;
			lua_proto.locvars = value;

			size, value = readupnames(); -- upvalues.name
			for i = 1, size do
				lua_proto.upvalues[i - 1].name = value[i];
			end

			return lua_proto;
		end

		local function luaU_checkheader()
			local function luaU_checksize(name, short, long)
				local size = readbyte();

				if (size == 4) then
					specs['read' .. name] = short;
				elseif (size == 8) then
					specs['read' .. name] = long;
				else
					fail(name .. ' format not supported in');
				end
			end

			local function luaU_checkliteral(kstr, kmsg)
				for i = 1, #kstr do
					if (l_byte(kstr, i, i) ~= readbyte()) then
						fail(kmsg);
					end
				end
			end

			-- note that `band` should support the sign bit being
			-- the lowest 32 bit digit!!! (-2147483648)
			-- ie: h_tobit(-1) is essentially `2147483647 + -2147483648`
			local function h_tobit(n) -- for support
				return band(n, 0x7FFFFFFF) + band(n, 0x80000000);
			end

			local function readint()
				local a, b, c, d = l_byte(chunk, position, position + 3);
				position = position + 4;

				if specs.little then
					return d * (2 ^ 24) + c * (2 ^ 16) + b * (2 ^ 8) + a;
				else
					return a * (2 ^ 24) + b * (2 ^ 16) + c * (2 ^ 8) + d;
				end
			end

			local function readlong()
				local a, b = h_tobit(readint()), h_tobit(readint());

				if specs.little then
					return h_tobit(b * (2 ^ 32) + a);
				else
					return h_tobit(a * (2 ^ 32) + b);
				end
			end

			local function readfloat() -- I'll do this one eventually
				readint() -- not exactly a priority
				return 0; -- TODO
			end

			local function readdouble()
				-- thanks @Eternal for giving me this so I could mangle it in here and have it work
				local left = readint();
				local right = readint();
				local mantissa = (band(right, 0x7FFFF) * (2 ^ 32))
				+ left;
				local exponent = band(rsh(right, 20), 0x7FF);
				local sign = ((-1) ^ band(rsh(right, 31), 0x1));
				local normal = 1;
				if (exponent == 0) then
					if (mantissa == 0) then
						return sign * 0 -- +-0
					else
						exponent = 1
						normal = 0
					end
				elseif (exponent == 2047) then
					if (mantissa == 0) then
						return sign * (1 / 0) -- +-Inf
					else
						return sign * (0 / 0) -- +-Q/Nan
					end
				end
				return math.ldexp(sign, exponent - 1023) * (normal + (mantissa / (2 ^ 52)));
			end

			luaU_checkliteral(specs.signature, 'Not a');

			if (readbyte() ~= specs.version) then
				fail('Version mismatch in');
			elseif (readbyte() ~= specs.format) then
				fail('Format mismatch in');
			end

			luaU_checkliteral(specs.integrity, 'Corrupted');
			luaU_checksize('int', readint, readlong);
			luaU_checksize('size_t', readint, readlong);
			luaU_checksize('Instruction', readint, readlong);
			luaU_checksize('lua_Integer', readint, readlong);
			luaU_checksize('lua_Number', readfloat, readdouble);

			specs.little = specs.readlua_Integer() == specs.end_int;

			if (specs.readlua_Number() ~= specs.end_num) then
				fail('Float format mismatch in');
			end
		end

		luaU_checkheader();
		lclosure = luaF_newLclosure(readbyte());
		lclosure.p = readproto();

		return lclosure;
	end
end

do
	local select = select;
	local unpack = unpack or table.unpack;
	local function h_wrap(...)
		return select('#', ...), {...};
	end

	local function luaV_execute(frame)
		local cl = frame.lclosure;
		local stack = frame.stack;
		local upvals = cl.upvals;
		local code = cl.p.code;
		local k = cl.p.k;
		local top = 0;
		local pc = 0;

		local openupval = {};

		local function setobj(idx, val)
			if idx > top then
				top = idx;
			end
			stack[idx] = val;
		end

		local function luaF_close(n)
			local i = 1;
			while (i <= #openupval) do
				local u = openupval[i];
				if (u.idx >= n) then
					local len = #openupval;
					u.v = u.stk[u.idx];
					u.stk = u;
					u.idx = 'v';
					openupval[i] = openupval[len]; -- swap
					openupval[len] = nil;
				else
					i = i + 1;
				end
			end
		end

		local band = bit.band;
		local bnot = bit.bnot;
		local bor = bit.bor;
		local bxor = bit.bxor;
		local shl = bit.lshift;
		local shr = bit.rshift;

		while true do
			local dpc = code[pc];
			local op = dpc.i;
			frame.lastpc = pc; -- for debugging
			pc = pc + 1;

			if (op == 0) then -- MOVE
				setobj(dpc.A, stack[dpc.B]);
			elseif (op == 1) then -- LOADK
				setobj(dpc.A, k[dpc.Bx]);
			elseif (op == 2) then -- LOADKX
				local Ax = code[pc].Ax;
				pc = pc + 1;
				setobj(dpc.A, k[Ax]);
			elseif (op == 3) then -- LOADBOOL
				setobj(dpc.A, dpc.B ~= 0);
				if (dpc.C ~= 0) then
					pc = pc + 1;
				end
			elseif (op == 4) then -- LOADNIL
				local a = dpc.A;
				for i = a, a + dpc.B do
					setobj(i, nil);
				end
			elseif (op == 5) then -- GETUPVAL
				local u = upvals[dpc.B];
				setobj(dpc.A, u.stk[u.idx]);
			elseif (op == 6) then -- GETTABUP
				local u = upvals[dpc.B];
				local c = dpc.C;
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, u.stk[u.idx][c]);
			elseif (op == 7) then -- GETTABLE
				local c = dpc.C;
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, stack[dpc.B][c]);
			elseif (op == 8) then -- SETTABUP
				local u = upvals[dpc.A];
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				u.stk[u.idx][b] = c;
			elseif (op == 9) then -- SETUPVAL
				local u = upvals[dpc.B];
				u.stk[u.idx] = stack[dpc.A];
			elseif (op == 10) then -- SETTABLE
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				stack[dpc.A][b] = c;
			elseif (op == 11) then -- NEWTABLE
				setobj(dpc.A, {});
			elseif (op == 12) then -- SELF
				local a = dpc.A;
				local b = dpc.B;
				local c = dpc.C;
				b = stack[b];
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(a + 1, b);
				setobj(a, b[c]);
			elseif (op == 13) then -- ADD
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, b + c);
			elseif (op == 14) then -- SUB
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, b - c);
			elseif (op == 15) then -- MUL
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, b * c);
			elseif (op == 16) then -- MOD
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, b % c);
			elseif (op == 17) then -- POW
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, b ^ c);
			elseif (op == 18) then -- DIV
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, b / c);
			elseif (op == 19) then -- IDIV
				local b = dpc.B;
				local c = dpc.C;
				local r;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				r = b / c;
				setobj(dpc.A, r - (r % 1));
			elseif (op == 20) then -- BAND
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, band(b, c));
			elseif (op == 21) then -- BOR
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, bor(b, c));
			elseif (op == 22) then -- BXOR
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, bxor(b, c));
			elseif (op == 23) then -- SHIFTL
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, shl(b, c));
			elseif (op == 24) then -- SHIFTR
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				setobj(dpc.A, shr(b, c));
			elseif (op == 25) then -- UMN
				setobj(dpc.A, -stack[dpc.B]);
			elseif (op == 26) then -- BNOT
				setobj(dpc.A, bnot(stack[dpc.B]));
			elseif (op == 27) then -- NOT
				setobj(dpc.A, not stack[dpc.B]);
			elseif (op == 28) then -- LEN
				setobj(dpc.A, #stack[dpc.B]);
			elseif (op == 29) then -- CONCAT
				local r = '';
				for i = dpc.B, dpc.C do
					r = r .. stack[i];
				end
				setobj(dpc.A, r);
			elseif (op == 30) then -- JMP
				local a = dpc.A;
				pc = pc + dpc.sBx;
				if (a ~= 0) then
					luaF_close(a - 1);
				end
			elseif (op == 31) then -- EQ
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				if ((b == c) ~= (dpc.A ~= 0)) then
					pc = pc + 1;
				end
			elseif (op == 32) then -- LT
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				if ((b < c) ~= (dpc.A ~= 0)) then
					pc = pc + 1;
				end
			elseif (op == 33) then -- LE
				local b = dpc.B;
				local c = dpc.C;
				if (b >= 0x100) then
					b = k[b - 0x100];
				else
					b = stack[b];
				end
				if (c >= 0x100) then
					c = k[c - 0x100];
				else
					c = stack[c];
				end
				if ((b <= c) ~= (dpc.A ~= 0)) then
					pc = pc + 1;
				end
			elseif (op == 34) then -- TEST
				if ((dpc.C ~= 0) ~= (not not stack[dpc.A])) then
					pc = pc + 1;
				end
			elseif (op == 35) then -- TESTSET
				local b = stack[dpc.B];
				if ((dpc.C ~= 0) ~= (not not b)) then
					pc = pc + 1;
				else
					setobj(dpc.A, b);
				end
			elseif (op == 36) then -- CALL
				local a = dpc.A;
				local b = dpc.B;
				local c = dpc.C;
				local func = stack[a];
				local nr, rets;
				if (b ~= 1) then
					if (b == 0) then
						b = top;
					else
						b = a + b - 1;
					end
					local args = {};
					for i = a + 1, b do
						args[i - a] = stack[i];
					end
					nr, rets = h_wrap(func(unpack(args, 1, b - a)));
				else
					nr, rets = h_wrap(func());
				end
				if (c ~= 1) then
					if (c == 0) then
						top = nr + a - 1;
					else
						nr = c - 1;
					end
					for i = 1, nr do
						setobj(a + i - 1, rets[i]);
					end
				end
			elseif (op == 37) then -- TAILCALL
				local a = dpc.A;
				local b = dpc.B;
				local func = stack[a];
				luaF_close(0);
				if (b ~= 1) then
					if (b == 0) then
						b = top;
					else
						b = a + b - 1;
					end
					local args = {};
					for i = a + 1, b do
						args[i - a] = stack[i];
					end
					return h_wrap(func(unpack(args, 1, b - a)));
				else
					return h_wrap(func());
				end
			elseif (op == 38) then -- RETURN
				local nr, rets = 0;
				local a = dpc.A;
				local b = dpc.B;
				luaF_close(0);
				if (b ~= 1) then
					if (b == 0) then
						nr = top;
					else
						nr = a + b - 2;
					end
					rets = {};
					for i = a, nr do
						rets[i - a + 1] = stack[i];
					end
					nr = nr - a + 1;
				end
				return nr, rets;
			elseif (op == 39) then -- FORLOOP
				local a = dpc.A;
				local step = stack[a + 2];
				local limit = stack[a + 1];
				local idx = stack[a] + step;
				local fwd = step > 0;
				setobj(a, idx);
				if (fwd and idx <= limit) or (not fwd and idx >= limit) then
					pc = pc + dpc.sBx;
					setobj(a + 3, idx);
				end
			elseif (op == 40) then -- FORPREP
				local a = dpc.A;
				setobj(a, assert(tonumber(stack[a]), '`for` initial value must be a number'));
				setobj(a + 1, assert(tonumber(stack[a + 1]), '`for` limit must be a number'));
				setobj(a + 2, assert(tonumber(stack[a + 2]), '`for` step must be a number'));
				setobj(a, stack[a] - stack[a + 2]);
				pc = pc + dpc.sBx;
			elseif (op == 41) then -- TFORCALL
				local a = dpc.A;
				local _, rets;
				setobj(a + 5, stack[a + 2]); -- source mirrored for consistency
				setobj(a + 4, stack[a + 1]);
				setobj(a + 3, stack[a]);
				_, rets = h_wrap(stack[a](stack[a + 1], stack[a + 2]));
				for i = a + 3, a + dpc.C + 2 do
					setobj(i, rets[i - a - 2]);
				end
			elseif (op == 42) then -- TFORLOOP
				local a = dpc.A;
				local r = stack[a + 1];
				if (r ~= nil) then
					setobj(a, r);
					pc = pc + dpc.sBx;
				end
			elseif (op == 43) then -- SETLIST
				local a = dpc.A;
				local b = dpc.B;
				local c = dpc.C;
				local t = stack[a];
				local off;
				if (b == 0) then
					b = top - a;
				end
				if (c == 0) then
					c = code[pc].Ax;
					pc = pc + 1;
				end
				off = (c - 1) * 50;
				for i = 1, b do
					t[off + i] = stack[a + i];
				end
			elseif (op == 44) then -- CLOSURE
				local p = cl.p.p[dpc.Bx];
				local ups = p.upvalues;
				local ncl = p.cached;
				if ncl then
					for i = 0, p.sizeupvalues - 1 do
						local u = ncl.upvals[i];
						local m = ups[i];
						local v;
						if m.onstack then
							v = stack[m.idx];
						else
							v = upvals[m.idx];
							v = v.stk[v.idx];
						end
						if (v ~= u.stk[u.idx]) then
							ncl = nil;
							break;
						end
					end
				end
				if (not ncl) then
					local nopen = #openupval;
					ncl = luaF_newLclosure(p.sizeupvalues);
					ncl.p = p;
					for i = 0, p.sizeupvalues - 1 do
						local m = ups[i];
						local n;
						if m.onstack then
							for j = 1, nopen do
								local cu = openupval[j];
								if (cu.idx == m.idx) then
									n = cu;
									break;
								end
							end
							if (not n) then
								n = { -- create upvalue
									stk = stack;
									idx = m.idx;
								};
								nopen = nopen + 1;
								openupval[nopen] = n;
							end
						else
							n = upvals[m.idx];
						end
						ncl.upvals[i] = n;
					end
				end
				p.cached = ncl;
				setobj(dpc.A, luaF_wrap(ncl));
			elseif (op == 45) then -- VARARG
				local vararg = frame.vararg;
				local a = dpc.A;
				local b = dpc.B;
				if (b == 0) then
					b = a + vararg.len - 1;
				else
					b = a + b - 2;
				end
				for i = a, b do
					setobj(i, vararg[i - a]);
				end
			end
		end
	end

	function luaF_wrap(l, env)
		local narg = l.p.numparams;
		local nvar = l.p.is_vararg ~= 0;

		if env and (l.nupvalues >= 1) then
			-- `stk` is a pointer to the table
			-- holding the upvalue, which is itself
			-- when it is closed
			local e_up = {};
			e_up.stk = e_up;
			e_up.idx = 'v';
			e_up.v = env;

			l.upvals[0] = e_up;
		end

		-- about @newframe
		-- The frame is supposed to work as a light way of
		-- passing closure data to the luaV_execute function, while
		-- also keeping support for something such as debugging via line
		-- number, as it keeps track of the lastpc
		return function(...)
			local newframe = {};
			local pass, list = h_wrap(...);
			local pl, al = {}, nil;
			local nr, rets;

			if (narg ~= 0) then -- stack has arguments
				for i = 1, narg do
					pl[i - 1] = list[i];
				end
			end
			if nvar then -- handle vararg
				al = {};
				al.len = pass - narg;
				for i = 1, pass - narg do
					al[i - 1] = list[i + narg];
				end
			end

			newframe.lclosure = l;
			newframe.stack = pl;
			newframe.vararg = al;
			newframe.lastpc = 0; -- used for debugging
			nr, rets = luaV_execute(newframe); -- execute

			if nr and (nr ~= 0) then -- finish return
				return unpack(rets, 1, nr);
			end
		end
	end

	-- use this to quickly make functions
	function luaF_dispatch(bytecode, env)
		return luaF_wrap(luaU_undump(bytecode), env);
	end
end

return {
	luaF_newLclosure = luaF_newLclosure,
	luaF_dispatch = luaF_dispatch,
	luaU_undump = luaU_undump,
	luaF_wrap = luaF_wrap
};
