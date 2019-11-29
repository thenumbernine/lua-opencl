
local range = require 'ext.range'

local env = require 'cl.obj.env'{size=64} 
local a = env:buffer{name='a', type='real', data=range(env.base.volume)}
local b = env:buffer{name='b', type='real', data=range(env.base.volume)}
local c = env:buffer{name='c', type='real'}
env:kernel{
	argsOut = {c},
	argsIn = {a,b},
	body='c[index] = a[index] * b[index];',
}()

local aMem = a:toCPU()
local bMem = b:toCPU()
local cMem = c:toCPU()
for i=0,env.base.volume-1 do
	print(aMem[i]..' * '..bMem[i]..' = '..cMem[i])
end

