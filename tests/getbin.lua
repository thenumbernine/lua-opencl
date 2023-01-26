#!/usr/bin/env luajit
require 'ext'
local range = require 'ext.range'
local tolua = require 'ext.tolua'
local CLEnv = require 'cl.obj.env'

local env = CLEnv{
	getPlatform = CLEnv.getPlatformFromCmdLine(...),
	getDevices = CLEnv.getDevicesFromCmdLine(...),
	size=49,
}

local src = env:buffer{name='src', type='real', data=range(env.base.volume)}
local dst = env:buffer{name='dst', type='real'}

local kernel = env:kernel{
	name = 'test',
	argsOut = {dst},
	argsIn = {src},
	body = 'dst[index] = src[index] * src[index];',
}

kernel()

do
	print'first pass:'
	local srcMem = src:toCPU()
	local dstMem = dst:toCPU()
	for i=0,env.base.volume-1 do
		io.write(' '..srcMem[i]..'^2 = '..dstMem[i])
	end
	print()
end

local programObj = kernel.program.obj
local binaries = programObj:getBinaries()
print(programObj:getSource())
print(tolua(binaries))

local program2 = env:program{binaries=binaries}
program2:compile()
local kernel2 = program2:kernel'test'

kernel2(src, dst)

do
	print'second pass:'
	local srcMem = dst:toCPU()
	local dstMem = src:toCPU()
	for i=0,env.base.volume-1 do
		io.write(' '..srcMem[i]..'^2 = '..dstMem[i])
	end
	print()
end
