#!/usr/bin/env luajit
local range = require 'ext.range'
local ffi = require 'ffi'
local CLEnv = require 'cl.obj.env'

-- TODO separate out domain from kernel
local env = require 'cl.obj.env'{size=64} 
local a = env:buffer{name='a', type='real'}
local b = env:buffer{name='b', type='real'}
local c = env:buffer{name='c', type='real'}
local kernel = env:kernel{
	argsIn = {a,b},
	argsOut = {c},
	body='c[index] = a[index] * b[index];',
}

-- cpu mem
local n = env.volume
a:fromCPU(range(n))
b:fromCPU(range(n))

kernel()

local aMem = a:toCPU()
local bMem = b:toCPU()
local cMem = c:toCPU()
for i=0,n-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()
