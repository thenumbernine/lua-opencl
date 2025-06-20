#!/usr/bin/env luajit
-- cl-cpp test by invoking clang through the cl.obj.program class
local ffi = require 'ffi'
require 'ext'

local n = 64

local CLEnv = require 'cl.obj.env'
local env = CLEnv{
	useGLSharing = false,
	getPlatform = CLEnv.getPlatformFromCmdLine(...),
	getDevices = CLEnv.getDevicesFromCmdLine(...),
	deviceType = CLEnv.getDeviceTypeFromCmdLine(...),
	precision = cmdline.real or 'double',
	size = n,
}
env.code = ''
local real = env.real
print('using real',real)

local clcppfn = 'cpptest.clcpp'
local bcfn = 'cpptest.bc'
local spvfn = 'cpptest.spv'

local program = env:program{
	-- Why is .spirvToolchainFileCL and .code both required? because CL is the write file and code is the read content
	code = path(clcppfn):read(),				-- code source
	spirvToolchainFileCL = 'cpptest.tmp.clcpp',	-- temp write file after adding env header
	spirvToolchainFileBC = bcfn,
	spirvToolchainFileSPV = spvfn,
}

-- has to be separate eh?
program:compile{
	buildOptions = table{
		'-O0',	-- sometimes amd chokes on this
		'-DARRAY_SIZE='..n,
		'-DREAL='..real,
		env.real == 'double' and '-DUSE_FP64' or '',
	}:concat' ',
}

-- gpu mem
local a = env:buffer{name='a', type='real', data=range(n)}
local b = env:buffer{name='b', type='real', data=range(n)}
local c = env:buffer{name='c', type='real', data=range(n)}

local testKernel = program:kernel('test', c.obj, a.obj, b.obj)

local event = require 'cl.event'()
testKernel.event = event
testKernel()
env.cmds[1]:finish()
local start = event:getProfilingInfo'CL_PROFILING_COMMAND_START'
local fin = event:getProfilingInfo'CL_PROFILING_COMMAND_END'
print('duration', tonumber(fin - start)..' ns')

-- cpu mem
local aMem = a:toCPU()
local bMem = b:toCPU()
local cMem = c:toCPU()

for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()

print'done'
