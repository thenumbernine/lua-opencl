#!/usr/bin/env luajit
local ffi = require 'ffi'

local n = 16
local real = 'float'

local platform, device, ctx, cmds, program = require 'cl'{
	device={gpu=true},
	program={code=
'#define N '..n..'\n'..
'#define real '..real..'\n'..[[
__kernel void test(
	__global real* c,
	const __global real* a,
	const __global real* b
) {
	int i = get_global_id(0);
	if (i >= N) return;
	c[i] = a[i] + b[i];
}
]]
}
}

-- gpu mem
local aBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}
local bBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}
local cBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}

-- cpu mem
local aMem = ffi.new(real..'[?]', n)
local bMem = ffi.new(real..'[?]', n)
local cMem = ffi.new(real..'[?]', n)
for i=0,n-1 do 
	aMem[i] = i 
	bMem[i] = i
end

cmds:enqueueWriteBuffer{buffer=aBuffer, block=true, size=n*ffi.sizeof(real), ptr=aMem}
cmds:enqueueWriteBuffer{buffer=bBuffer, block=true, size=n*ffi.sizeof(real), ptr=bMem}

local testKernel = program:kernel('test', cBuffer, aBuffer, bBuffer)

cmds:enqueueNDRangeKernel{kernel=testKernel, globalSize={n}, localSize={16}}

cmds:enqueueReadBuffer{buffer=cBuffer, block=true, size=n*ffi.sizeof(real), ptr=cMem}
for i=0,n-1 do
	print(aMem[i]..' + '..bMem[i]..' = '..cMem[i])
end
