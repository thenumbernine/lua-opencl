local class = require 'ext.class'
local cl = require 'ffi.OpenCL'
local bit = require 'bit'
local classertparam = require 'cl.assertparam'
local Memory = require 'cl.memory'
local GetInfo = require 'cl.getinfo'

local Image = class(GetInfo(Memory))

-- TODO verify that this goes with the clCreateFromGLTexture function below
Image.getInfo = Image:makeGetter{
	getter = cl.clGetImageInfo,
	vars = {
		{name='CL_IMAGE_FORMAT', type=''},
		{name='CL_IMAGE_ELEMENT_SIZE', type=''},
		{name='CL_IMAGE_ROW_PITCH', type=''},
		{name='CL_IMAGE_SLICE_PITCH', type=''},
		{name='CL_IMAGE_WIDTH', type=''},
		{name='CL_IMAGE_HEIGHT', type=''},
		{name='CL_IMAGE_DEPTH', type=''},
		{name='CL_IMAGE_ARRAY_SIZE', type=''},
		{name='CL_IMAGE_BUFFER', type=''},
		{name='CL_IMAGE_NUM_MIP_LEVELS', type=''},
		{name='CL_IMAGE_NUM_SAMPLES', type=''},
	},
}

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
