#!/usr/bin/env luajit
local ffi = require 'ffi'
require 'ext'


local function get64bit(list)
	local best = list:mapi(function(item)
		local exts = item:getExtensions():mapi(string.lower)
		return {item=item, fp64=exts:find(function(s) return s:match'cl_%w+_fp64' end)}
	end):sort(function(a,b)
		return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
	end)[1]
	return best.item, best.fp64
end

local platform = get64bit(require 'cl.platform'.getAll())
local device, fp64 = get64bit(platform:getDevices{gpu=true})

print('device', device:getName())

local n = 64
local real = fp64 and 'double' or 'float'
print('using real',real)

local ctx = require 'cl.context'{platform=platform, device=device}

local cl = require 'ffi.OpenCL'
local cmds = require 'cl.commandqueue'{context=ctx, device=device, properties=cl.CL_QUEUE_PROFILING_ENABLE}

local code =
'#define N '..n..'\n'..
'#define real '..real..'\n'..
(fp64 and '#pragma OPENCL EXTENSION cl_khr_fp64 : enable\n' or '')..
[[
kernel void test(
	global real* c,
	const global real* a,
	const global real* b
) {
	int i = get_global_id(0);
	if (i >= N) return;
	c[i] = a[i] * b[i];
}
]]

local program = require 'cl.program'{context=ctx, devices={device}, code=code}

-- gpu mem
local aBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}
local bBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}
local cBuffer = ctx:buffer{rw=true, size=n*ffi.sizeof(real)}

-- cpu mem
local aMem = ffi.new(real..'[?]', n)
local bMem = ffi.new(real..'[?]', n)
local cMem = ffi.new(real..'[?]', n)
for i=0,n-1 do 
	aMem[i] = i+1
	bMem[i] = i+1
end

cmds:enqueueWriteBuffer{buffer=aBuffer, block=true, size=n*ffi.sizeof(real), ptr=aMem}
cmds:enqueueWriteBuffer{buffer=bBuffer, block=true, size=n*ffi.sizeof(real), ptr=bMem}

local testKernel = program:kernel('test', cBuffer, aBuffer, bBuffer)

local event = require 'cl.event'()
cmds:enqueueNDRangeKernel{kernel=testKernel, globalSize=n, localSize=16, event=event}
cmds:finish()
local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
local fin = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
print('duration', tonumber(fin - start)..' ns')
cmds:enqueueReadBuffer{buffer=cBuffer, block=true, size=n*ffi.sizeof(real), ptr=cMem}
for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()
