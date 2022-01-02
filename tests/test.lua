#!/usr/bin/env luajit
local ffi = require 'ffi'
require 'ext'

local function matchExt(obj, pat)
	local exts = obj:getExtensions():mapi(string.lower)
	return not not exts:find(nil, function(s) return s:match(pat) end)
end

local function isFP64(obj)
	return matchExt(obj, 'cl_%w+_fp64')
end

local function get64bit(list)
	local best = list:mapi(function(item)
		return {item=item, fp64=isFP64(item)}
	end):sort(function(a,b)
		return (a.fp64 and 1 or 0) > (b.fp64 and 1 or 0)
	end)[1]
	return best.item, best.fp64
end

local platform = get64bit(require 'cl.platform'.getAll())
local devices = platform:getDevices{gpu=true}:mapi(function(device)
	return isFP64(device) and device or nil
end)
if #devices == 0 then error("found no devices with fp64") end
for i,device in ipairs(devices) do
	print('device '..i..': '..tostring(device:getName()))
end

local fp64 = #devices:filter(isFP64) == #devices

local n = 64
local real = fp64 and 'double' or 'float'
print('using real',real)

local ctx = require 'cl.context'{platform=platform, devices=devices}

local cl = require 'ffi.OpenCL'
local CommandQueue = require 'cl.commandqueue'
local cmds = devices:mapi(function(device)
	return CommandQueue{context=ctx, device=device, properties=cl.CL_QUEUE_PROFILING_ENABLE}
end)

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

local Program = require 'cl.program'
local program = Program{context=ctx, devices=devices, code=code}

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

cmds[1]:enqueueWriteBuffer{buffer=aBuffer, block=true, size=n*ffi.sizeof(real), ptr=aMem}
cmds[1]:enqueueWriteBuffer{buffer=bBuffer, block=true, size=n*ffi.sizeof(real), ptr=bMem}

local testKernel = program:kernel('test', cBuffer, aBuffer, bBuffer)

local event = require 'cl.event'()
cmds[1]:enqueueNDRangeKernel{kernel=testKernel, globalSize=n, localSize=16, event=event}
cmds[1]:finish()
local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
local fin = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
print('duration', tonumber(fin - start)..' ns')
cmds[1]:enqueueReadBuffer{buffer=cBuffer, block=true, size=n*ffi.sizeof(real), ptr=cMem}
for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()
