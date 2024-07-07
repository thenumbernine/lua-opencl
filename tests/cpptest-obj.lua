#!/usr/bin/env luajit
-- cl-cpp test by invoking clang through the cl.obj.program class
local ffi = require 'ffi'
require 'ext'

local n = 64
local real = 'double'

local devices, fp64, ctx, cl, cmds
if not cmdline.nocl then -- [[ initialize CL first to tell what kind of real we can use
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
	devices = platform:getDevices{gpu=true}:mapi(function(device)
		return isFP64(device) and device
	end)
	for i,device in ipairs(devices) do
		print('device '..i..': '..tostring(device:getName()))
	end

	fp64 = #devices:filter(isFP64) == #devices

	real = fp64 and 'double' or 'float'
	print('using real',real)

	ctx = require 'cl.context'{platform=platform, devices=devices}

	cl = require 'ffi.req' 'OpenCL'
	local CommandQueue = require 'cl.commandqueue'
	cmds = devices:mapi(function(device)
		return CommandQueue{context=ctx, device=device, properties=cl.CL_QUEUE_PROFILING_ENABLE}
	end)
end
--]]


local CLEnv = require 'cl.obj.env'
local env = CLEnv{
	verbose = true,
	useGLSharing = false,
	getPlatform = CLEnv.getPlatformFromCmdLine(...),
	getDevices = CLEnv.getDevicesFromCmdLine(...),
	deviceType = CLEnv.getDeviceTypeFromCmdLine(...),
	size = n,
}


local clcppfn = 'cpptest.clcpp'
local bcfn = 'cpptest.bc'
local spvfn = 'cpptest.spv'

local program = env:program{
	context = ctx,
	devices = devices,
	-- TODO why is .spirvToolchainFileCL and .code both required?
	code = path(clcppfn):read(),				-- code source
	spirvToolchainFileCL = 'cpptest.tmp.clcpp',	-- temp write file after adding env header
	spirvToolchainFileBC = bcfn,
	spirvToolchainFileSPV = spvfn,
}
program:compile{
	buildOptions = table{
		'-O0',	-- sometimes amd chokes on this
		'-DARRAY_SIZE='..n,
		'-DREAL='..real,
	}:concat' ',
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
	aMem[i] = i+1
	bMem[i] = i+1
end

cmds[1]:enqueueWriteBuffer{buffer=aBuffer, block=true, size=n*ffi.sizeof(real), ptr=aMem}
cmds[1]:enqueueWriteBuffer{buffer=bBuffer, block=true, size=n*ffi.sizeof(real), ptr=bMem}

local testKernel = program:kernel('test', cBuffer, aBuffer, bBuffer)
local maxWorkGroupSize = tonumber(testKernel.obj:getWorkGroupInfo('CL_KERNEL_WORK_GROUP_SIZE', devices[1]))

local event = require 'cl.event'()
cmds[1]:enqueueNDRangeKernel{kernel=testKernel, globalSize=n, localSize=math.min(16, maxWorkGroupSize), event=event}
cmds[1]:finish()
local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
local fin = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
print('duration', tonumber(fin - start)..' ns')
cmds[1]:enqueueReadBuffer{buffer=cBuffer, block=true, size=n*ffi.sizeof(real), ptr=cMem}
for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()

print'done'
