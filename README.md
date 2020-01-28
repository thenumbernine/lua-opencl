OpenCL bindings / OOP for Lua.

This library is a mess.  The first thing I did with it was port the cl.hpp into Lua.  Next, I added to it some quick initialization code as you can find in the CLCommon project. 
Next I made OOP-ish port similar to my lua-gl project.  
The two are different APIs at different levels of abstraction, so I made the latter sit on top of the former.

### Dependencies:

- LuaJIT
- https://github.com/thenumbernine/lua-ext
- https://github.com/thenumbernine/lua-template
- https://github.com/thenumbernine/lua-ffi-bindings (OpenCL, OpenGL if you use 'glSharing', ffi-based vector types)

### Example:

Here's an example of the code:

``` Lua

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

```

gives

```
1 * 1 = 1
2 * 2 = 4
3 * 3 = 9
4 * 4 = 16
5 * 5 = 25
6 * 6 = 36
7 * 7 = 49
8 * 8 = 64
9 * 9 = 81
10 * 10 = 100
11 * 11 = 121
12 * 12 = 144
13 * 13 = 169
14 * 14 = 196
15 * 15 = 225
16 * 16 = 256
17 * 17 = 289
18 * 18 = 324
19 * 19 = 361
20 * 20 = 400
21 * 21 = 441
22 * 22 = 484
23 * 23 = 529
24 * 24 = 576
25 * 25 = 625
26 * 26 = 676
27 * 27 = 729
28 * 28 = 784
29 * 29 = 841
30 * 30 = 900
31 * 31 = 961
32 * 32 = 1024
33 * 33 = 1089
34 * 34 = 1156
35 * 35 = 1225
36 * 36 = 1296
37 * 37 = 1369
38 * 38 = 1444
39 * 39 = 1521
40 * 40 = 1600
41 * 41 = 1681
42 * 42 = 1764
43 * 43 = 1849
44 * 44 = 1936
45 * 45 = 2025
46 * 46 = 2116
47 * 47 = 2209
48 * 48 = 2304
49 * 49 = 2401
50 * 50 = 2500
51 * 51 = 2601
52 * 52 = 2704
53 * 53 = 2809
54 * 54 = 2916
55 * 55 = 3025
56 * 56 = 3136
57 * 57 = 3249
58 * 58 = 3364
59 * 59 = 3481
60 * 60 = 3600
61 * 61 = 3721
62 * 62 = 3844
63 * 63 = 3969
64 * 64 = 4096
```

...all computed on the GPU
