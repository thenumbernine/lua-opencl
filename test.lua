#!/usr/bin/env luajit
local cl = require 'ffi.OpenCL'
local ffi = require 'ffi'

local classert = require 'cl.assert'
local Platform = require 'cl.platform'
local Context = require 'cl.context'
local Commands = require 'cl.commands'
local Program = require 'cl.program'
local Buffer = require 'cl.buffer' 
local Kernel = require 'cl.kernel'

local vec3sz = require 'ffi.vec.create_ffi'(3, 'size_t', 'sz')

local platform = Platform.getAll()[1]
local device = platform:getDevices{useCPU=false}[1]
local context = Context{platform=platform, device=device}
local commands = Commands{context=context, device=device}

local n = 16
local program = Program{
	context=context, 
	code=[[
__kernel void test(
	__global float* c,
	const __global float* a,
	const __global float* b
) {
	int i = get_global_id(0);
	if (i >= ]]..n..[[) return;
	c[i] = a[i] + b[i];
}
]]
}
if not program:build{device} then
	print('failed to build')
	print(program:getBuildInfo(device, cl.CL_PROGRAM_BUILD_LOG))
	error'failed'
end

print(program:getBuildInfo(device, cl.CL_PROGRAM_BUILD_LOG))

local aBuffer = Buffer(context, cl.CL_MEM_READ_WRITE, n * ffi.sizeof'float')
local bBuffer = Buffer(context, cl.CL_MEM_READ_WRITE, n * ffi.sizeof'float') 
local cBuffer = Buffer(context, cl.CL_MEM_READ_WRITE, n * ffi.sizeof'float')

local aMem = ffi.new('float[?]', n)
local bMem = ffi.new('float[?]', n)
local cMem = ffi.new('float[?]', n)
for i=0,n-1 do 
	aMem[i] = i 
	bMem[i] = i
end

classert(cl.clEnqueueWriteBuffer(commands.obj, aBuffer.obj, true, 0, n * ffi.sizeof'float', aMem, 0, nil, nil))
classert(cl.clEnqueueWriteBuffer(commands.obj, bBuffer.obj, true, 0, n * ffi.sizeof'float', bMem, 0, nil, nil))

local testKernel = Kernel(program, 'test')
testKernel:setArgs(cBuffer, aBuffer, bBuffer)

local globalSize = vec3sz(1024, 1, 1)
local localSize = vec3sz(16, 1, 1)
classert(cl.clEnqueueNDRangeKernel(commands.obj, testKernel.obj, 1, nil, globalSize:ptr(), localSize:ptr(), 0, nil, nil))
cl.clFinish(commands.obj)

classert(cl.clEnqueueReadBuffer(commands.obj, cBuffer.obj, true, 0, n * ffi.sizeof'float', cMem, 0, nil, nil))
cl.clFinish(commands.obj)

for i=0,n-1 do
	print(aMem[i]..' + '..bMem[i]..' = '..cMem[i])
end
