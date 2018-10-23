#!/usr/bin/env luajit
local ffi = require 'ffi'
require 'ext'

local env = require 'cl.obj.env'{size=49}

local src = env:buffer{name='src', type='real', data=range(env.base.volume)}
local dst = env:buffer{name='dst', type='real'}

local kernel = env:kernel{
	name = 'test',
	argsOut = {dst},
	argsIn = {src},
	body = 'dst[index] = src[index] * src[index];',
}

kernel()

print'first pass:'
local srcMem = src:toCPU()
local dstMem = dst:toCPU()
for i=0,env.base.volume-1 do
	io.write(' '..srcMem[i]..'^2 = '..dstMem[i])
end
print()

local programObj = kernel.program.obj
local binaries = programObj:getBinaries()
print(programObj:getSource())
print(tolua(binaries))

local program2 = env:program{binaries=binaries}
program2:compile()
local kernel2 = program2:kernel'test'

kernel2(src, dst)

print'second pass:'
local srcMem = dst:toCPU()
local dstMem = src:toCPU()
for i=0,env.base.volume-1 do
	io.write(' '..srcMem[i]..'^2 = '..dstMem[i])
end
print()
