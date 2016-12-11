#!/usr/bin/env luajit
local range = require 'ext.range'

local env = require 'cl.obj.env'{size=64} 
local a = env:buffer{name='a', type='real', data=range(env.volume)}
local b = env:buffer{name='b', type='real', data=range(env.volume)}
local c = env:buffer{name='c', type='real'}
env:kernel{
	argsOut = {c},
	argsIn = {a,b},
	body='c[index] = a[index] * b[index];',
}()

local aMem = a:toCPU()
local bMem = b:toCPU()
local cMem = c:toCPU()
for i=0,env.volume-1 do
	io.write(aMem[i],'*',bMem[i],'=',cMem[i],'\t')
end
print()
