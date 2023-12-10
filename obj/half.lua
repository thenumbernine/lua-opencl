--[[
between cl.obj.half and cl.obj.number
I'm thinking maybe I should make a 'cl.util' folder
since neither of these are really specific to the OOP wrappers to the Lua wrappers of OpenCL C API
--]]

local bit = require 'bit'
local ffi = require 'ffi'
local math = require 'ext.math'
local struct = require 'struct'

local float16bits_t = struct{
	name = 'float16bits_t',	-- in OpenCL, 'float8' means 8x 4-byte-float ... in some languages 'float16' means 2-byte float ...
	union = true,
	fields = {
		{name='i', type='unsigned short'},
		{name='ptr', type='unsigned char[2]'},
		{type=struct{
			anonymous = true,
			fields = {
				{name = 'mant', type='unsigned short:10'},
				{name = 'exp', type='unsigned short:5'},
				{name = 'sign', type='unsigned short:1'},
			},
		}},
	}
}
ffi.cdef[[
typedef float16bits_t half;
]]
assert(ffi.sizeof'float16bits_t' == 2)

local float32bits_t = struct{
	name = 'float32bits_t',
	union = true,
	fields = {
		{name='i', type='unsigned int'},
		{name='f', type='float'},
		{name='ptr', type='unsigned char[4]'},
		{type=struct{
			anonymous = true,
			fields = {
				{name = 'mant', type='unsigned int:23'},
				{name = 'exp', type='unsigned int:8'},
				{name = 'sign', type='unsigned int:1'},
			},
		}},
	},
}
assert(ffi.sizeof'float32bits_t' == 4)

local b32 = ffi.new'float32bits_t'
local function tohalf(x)	-- converts to 'half' type defined in cl/obj/env.lua
	b32.f = x

	local h = ffi.new'half'
	h.sign = 0
	if b32.exp == 0xff then		-- nan / inf
		h.mant = bit.rshift(b32.mant, 13)
		if b32.mant ~= 0 then
			h.mant = bit.bor(h.mant, 0x200)
		end
		h.exp = 0x1f		-- nan / inf
	else
		local exp = b32.exp - 0x70
		if exp >= 0x1f then			-- exp overflow -> +-inf
			h.mant = 0
			h.exp = 0x1f
		elseif exp < -10 then	-- zero
			h.mant = 0
			h.exp = 0
		else
			if exp <= 0 then		-- exp in [-10,0]
				local negexp = 13 - exp	-- negexp in [13,23]
				local c = bit.bor(b32.mant, 0x800000)
				h.i = bit.rshift(c, negexp+1)
				if bit.band(c, bit.lshift(1, negexp)) ~= 0
				and bit.band(c, (bit.lshift(3, negexp) - 1)) ~= 0
				then
					h.i = h.i + 1
				end
			else
				h.mant = bit.rshift(b32.mant, 13)
				h.exp = exp
				if bit.band(b32.mant, 0x1000) ~= 0
				and bit.band(b32.mant, 0x2fff) ~= 0
				then
					h.i = h.i + 1	-- add through mant & exp
				end
			end
		end
	end
	h.sign = b32.sign
	return h
end

local function fromhalf(x)
	local exp = bit.rshift(bit.band(x.i, 0x7c00), 10)
	local mant = bit.lshift(bit.band(x.i, 0x3ff), 13)

	if exp == 0x1f then
		exp = 0xff
		if mant ~= 0 then
			mant = bit.bor(mant, 0x400000)
		end
	elseif exp == 0 then
		if mant ~= 0 then
			exp = exp + 1
			while bit.band(mant, 0x7f800000) == 0 do
				mant = bit.lshift(mant, 1)
				exp = exp - 1
			end
			mant = bit.band(mant, 0x7fffff)
			exp = exp + 0x70
		end
	else
		exp = exp + 0x70
	end

	b32.mant = mant
	b32.exp = exp
	b32.sign = x.sign

	--[[
	looks like tonumber(float32) doesn't work for all possible float binary representations ... like 0xfff80000
	Lua print() and Lua tonumber() treat values as null, but printf() treats them like floats

	7f800000 = 0 : 111 1111 1000 0 : 000 0000 0000 0000 0000 = inf
	ff800000 = 1 : 111 1111 1000 0 : 000 0000 0000 0000 0000 = -inf
	ffc00000 = 1 : 111 1111 1100 0 : 000 0000 0000 0000 0000 = nan

	value doesn't convert with tonumber(float32):

	fff80000 = 1 : 111 1111 1111 1 : 000 0000 0000 0000 0000
	--]]
	local y = tonumber(b32.f)
	if not y then y = math.nan end
	--assert(y, "failed to convert for "..('%x'):format(b32.i)..' '..tostring(b32.f))
	return y
end

-- use these for optional converting when half is used, or keeping as number if it's not
-- but TODO this uses 'real' type, defined in cl.obj.env and used nowhere else in the cl repo

local function fromreal(x)
	if ffi.sizeof'real' == 2 then
		return fromhalf(x)
	end
	return x
end

local function toreal(x)
	if ffi.sizeof'real' == 2 then
		return tohalf(x)
	end
	return x
end

--[[ how well does this work?
--[=[
local function test(x)
	local h = half.to(x)
	local y = half.from(h)
	print(math.abs(y-x), x, ('%x'):format(h.i), y)
end
for x=-10,10 do test(x + 1e-5) end
for x=-10,10 do test(x - 1e-5) end
for x=-10,10 do test(10^x) end
for x=-10,10 do test(-10^x) end
test(1/0)
test(-1/0)
test(0/0)
test(-0/0)
--]=]

local math = require 'ext.math'
-- numbers that don't map back and forth: 16-bit nans and 0
for i=0,65536 do
	local h = ffi.new'half'
	h.i = i
	local x = half.from(h)
	assert(type(x) == 'number')
	b32.f = x
	local h2 = half.to(x)
	if i ~= h2.i then
		print(('%x\t%x\t%x'):format(i, h2.i, b32.i), x)
		assert(not math.isfinite(x) or h.i == h2.i)
	end
end
os.exit()
--]]

return {
	to = tohalf,
	from = fromhalf,

	toreal = toreal,
	fromreal = fromreal,

	float16bits_t = float16bits_t,
	float32bits_t = float32bits_t,
}
