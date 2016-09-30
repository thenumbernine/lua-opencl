local class = require 'ext.class'
local cl = require 'ffi.OpenCL'
local gl = require 'ffi.OpenGL'
local ffi = require 'ffi'
local bit = require 'bit'
local classertparam = require 'cl.assertparam'

local Memory = require 'cl.memory'

local Image = class(Memory)

local ImageGL = class(Image)

--[[
args
	context
	flags (optional)

	one of these:
		flags
		read
		write
		rw

	tex
	target (optional, default to tex.target)
	level (optional, default 0)
--]]
function ImageGL:init(args)
	local tex = assert(args.tex)
	local flags = args.flags or 0
	if args.read then flags = bit.bor(flags, cl.CL_MEM_READ_ONLY) end
	if args.write then flags = bit.bor(flags, cl.CL_MEM_WRITE_ONLY) end
	if args.rw then flags = bit.bor(flags, cl.CL_MEM_READ_WRITE) end
	self.id = classertparam('clCreateFromGLTexture',
		assert(args.context).id,
		flags,
		args.target or tex.target,
		args.level or 0,
		tex.id)
	ImageGL.super.init(self, self.id)
end

return ImageGL
