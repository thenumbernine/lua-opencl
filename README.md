lua port of 
(a) the cl.hpp file
(b) my CLCommon code

I'm going to create wrapper classes (just like I do with my 'gl' project)
But should I put them in the 'cl' directly, and the cl.hpp equivalent functions elsewhere?
or should I put them elsewhere and leave cl.hpp here?  This for now.  I'll put the wrapper classes in the obj folder.

uses luajit ffi and my lua-ext project.

The obj/wrapper classes make use of my lua-template project.

Here's an example of the code:

``` Lua

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
	print(aMem[i]..' * '..bMem[i]..' = '..cMem[i])
end

```
