#!/usr/bin/env luajit
local cl = require 'ffi.OpenCL'
local ffi = require 'ffi'
local CLCommon = require 'opencl'

local classert = require 'opencl.assert'
local Program = require 'opencl.program'
local Buffer = require 'opencl.buffer' 
local Kernel = require 'opencl.kernel'

local clobj = CLCommon()
local commands = clobj.commands

local n = 16
local program = Program(clobj.context, [[
__kernel void test(
	__global float* c,
	const __global float* a,
	const __global float* b
) {
	int i = get_global_id(0);
	if (i >= ]]..n..[[) return;
	c[i] = a[i] + b[i];
}
]])
if not program:build({clobj.device}) then
	print('failed to build')
	print(program:getBuildInfo(clobj.device, cl.CL_PROGRAM_BUILD_LOG))
	error'failed'
end

print(program:getBuildInfo(clobj.device, cl.CL_PROGRAM_BUILD_LOG))

local aBuffer = Buffer(clobj.context, cl.CL_MEM_READ_WRITE, n * ffi.sizeof'float')
local bBuffer = Buffer(clobj.context, cl.CL_MEM_READ_WRITE, n * ffi.sizeof'float') 
local cBuffer = Buffer(clobj.context, cl.CL_MEM_READ_WRITE, n * ffi.sizeof'float')

local aMem = ffi.new('float[?]', n)
local bMem = ffi.new('float[?]', n)
local cMem = ffi.new('float[?]', n)
for i=0,n-1 do 
	aMem[i] = i 
	bMem[i] = i
end

classert(cl.clEnqueueWriteBuffer(commands, aBuffer.object_, true, 0, n * ffi.sizeof'float', aMem, 0, nil, nil))
classert(cl.clEnqueueWriteBuffer(commands, bBuffer.object_, true, 0, n * ffi.sizeof'float', bMem, 0, nil, nil))

local testKernel = Kernel(program, 'test')
testKernel:setArgs(cBuffer, aBuffer, bBuffer)

local globalSize = ffi.new('size_t[3]', 1024, 1, 1)
local localSize = ffi.new('size_t[3]', 16, 1, 1)
classert(cl.clEnqueueNDRangeKernel(commands, testKernel.object_, 1, nil, globalSize, localSize, 0, nil, nil))
cl.clFinish(commands)

classert(cl.clEnqueueReadBuffer(commands, cBuffer.object_, true, 0, n * ffi.sizeof'float', cMem, 0, nil, nil))
cl.clFinish(commands)

for i=0,n-1 do
	print(aMem[i]..' + '..bMem[i]..' = '..cMem[i])
end
