const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

const GL = @import("gl.zig");
const logger = std.log.scoped(.nanovg_gl);

const nvg = @import("nanovg");
const internal = nvg.internal;

pub const Options = struct {
    antialias: bool = false,
    stencil_strokes: bool = false,
    debug: bool = false,
};

pub fn init(gl: *const GL, allocator: Allocator, options: Options) !nvg {
    const gl_context = try GLContext.init(gl, allocator, options);

    const params = internal.Params{
        .user_ptr = gl_context,
        .edge_antialias = options.antialias,
        .renderCreate = renderCreate,
        .renderCreateTexture = renderCreateTexture,
        .renderDeleteTexture = renderDeleteTexture,
        .renderUpdateTexture = renderUpdateTexture,
        .renderGetTextureSize = renderGetTextureSize,
        .renderViewport = renderViewport,
        .renderCancel = renderCancel,
        .renderFlush = renderFlush,
        .renderFill = renderFill,
        .renderStroke = renderStroke,
        .renderTriangles = renderTriangles,
        .renderDelete = renderDelete,
    };
    return nvg{
        .ctx = try internal.Context.init(allocator, params),
    };
}

const GLContext = struct {
    gl: *const GL,
    allocator: Allocator,
    options: Options,
    shader: Shader,
    view: [2]f32,
    textures: ArrayList(Texture) = .{},
    texture_id: i32 = 0,
    vert_arr: GL.Uint = 0,
    vert_buf: GL.Uint = 0,
    calls: ArrayList(Call) = .{},
    paths: ArrayList(Path) = .{},
    verts: ArrayList(internal.Vertex) = .{},
    uniforms: ArrayList(FragUniforms) = .{},

    fn init(gl: *const GL, allocator: Allocator, options: Options) !*GLContext {
        var self = try allocator.create(GLContext);
        self.* = GLContext{
            .gl = gl,
            .allocator = allocator,
            .options = options,
            .shader = undefined,
            .view = .{ 0, 0 },
        };
        return self;
    }

    fn deinit(ctx: *GLContext) void {
        ctx.shader.delete(ctx.gl);
        ctx.textures.deinit(ctx.allocator);
        ctx.calls.deinit(ctx.allocator);
        ctx.paths.deinit(ctx.allocator);
        ctx.verts.deinit(ctx.allocator);
        ctx.uniforms.deinit(ctx.allocator);
        ctx.allocator.destroy(ctx);
    }

    fn castPtr(ptr: *anyopaque) *GLContext {
        return @alignCast(@ptrCast(ptr));
    }

    fn checkError(ctx: GLContext, str: []const u8) void {
        if (!ctx.options.debug) return;
        const gl = ctx.gl;
        const err = gl.getError();
        if (err != GL.NO_ERROR) {
            logger.err("GLError {X:0>8} after {s}", .{ err, str });
        }
    }

    fn allocTexture(ctx: *GLContext) !*Texture {
        var found_tex: ?*Texture = null;
        for (ctx.textures.items) |*tex| {
            if (tex.id == 0) {
                found_tex = tex;
                break;
            }
        }
        if (found_tex == null) {
            found_tex = try ctx.textures.addOne(ctx.allocator);
        }
        const tex = found_tex.?;
        tex.* = std.mem.zeroes(Texture);
        ctx.texture_id += 1;
        tex.id = ctx.texture_id;

        return tex;
    }

    fn findTexture(ctx: *GLContext, id: i32) ?*Texture {
        for (ctx.textures.items) |*tex| {
            if (tex.id == id) return tex;
        }
        return null;
    }
};

const ShaderType = enum(u2) {
    fill_gradient,
    fill_image,
    simple,
    image,
};

const Shader = struct {
    prog: GL.Uint,
    frag: GL.Uint,
    vert: GL.Uint,

    view_loc: GL.Int,
    tex_loc: GL.Int,
    colormap_loc: GL.Int,
    frag_loc: GL.Int,

    fn create(
        shader: *Shader,
        gl: *const GL,
        header: [:0]const u8,
        vertsrc: [:0]const u8,
        fragsrc: [:0]const u8,
    ) !void {
        var status: GL.Int = undefined;
        var str: [2][*]const u8 = undefined;
        var len: [2]GL.Int = undefined;
        str[0] = header.ptr;
        len[0] = @intCast(header.len);

        shader.* = std.mem.zeroes(Shader);

        const prog = gl.createProgram();
        const vert = gl.createShader(.VERTEX_SHADER);
        const frag = gl.createShader(.FRAGMENT_SHADER);
        str[1] = vertsrc.ptr;
        len[1] = @intCast(vertsrc.len);
        gl.shaderSource(vert, 2, &str[0], &len[0]);
        str[1] = fragsrc.ptr;
        len[1] = @intCast(fragsrc.len);
        gl.shaderSource(frag, 2, &str[0], &len[0]);

        gl.compileShader(vert);
        gl.getShaderiv(vert, .COMPILE_STATUS, &status);
        if (status != GL.TRUE) {
            printShaderErrorLog(gl, vert, "shader", "vert");
            return error.ShaderCompilationFailed;
        }

        gl.compileShader(frag);
        gl.getShaderiv(frag, .COMPILE_STATUS, &status);
        if (status != GL.TRUE) {
            printShaderErrorLog(gl, frag, "shader", "frag");
            return error.ShaderCompilationFailed;
        }

        gl.attachShader(prog, vert);
        gl.attachShader(prog, frag);

        gl.linkProgram(prog);
        gl.getProgramiv(prog, .LINK_STATUS, &status);
        if (status != GL.TRUE) {
            printProgramErrorLog(gl, prog, "shader");
            return error.ProgramLinkingFailed;
        }

        shader.prog = prog;
        shader.vert = vert;
        shader.frag = frag;

        shader.view_loc = gl.getUniformLocation(shader.prog, "viewSize");
        shader.tex_loc = gl.getUniformLocation(shader.prog, "tex");
        shader.colormap_loc = gl.getUniformLocation(shader.prog, "colormap");
        shader.frag_loc = gl.getUniformLocation(shader.prog, "frag");
    }

    fn delete(shader: Shader, gl: *const GL) void {
        if (shader.prog != 0) gl.deleteProgram(shader.prog);
        if (shader.vert != 0) gl.deleteShader(shader.vert);
        if (shader.frag != 0) gl.deleteShader(shader.frag);
    }

    fn printShaderErrorLog(
        gl: *const GL,
        shader: GL.Uint,
        name: []const u8,
        shader_type: []const u8,
    ) void {
        var buf: [512]u8 = undefined;
        var len: GL.Int = 0;
        gl.getShaderInfoLog(shader, 512, &len, &buf[0]);
        if (len > 512) len = 512;
        const log = buf[0..@intCast(len)];
        logger.err("Shader {s}/{s} error:\n{s}", .{ name, shader_type, log });
    }

    fn printProgramErrorLog(
        gl: *const GL,
        program: GL.Uint,
        name: []const u8,
    ) void {
        var buf: [512]u8 = undefined;
        var len: GL.Int = 0;
        gl.getProgramInfoLog(program, 512, &len, &buf[0]);
        if (len > 512) len = 512;
        const log = buf[0..@intCast(len)];
        logger.err("Program {s} error:\n{s}", .{ name, log });
    }
};

const Texture = struct {
    id: i32,
    tex: GL.Uint,
    width: i32,
    height: i32,
    tex_type: internal.TextureType,
    flags: nvg.ImageFlags,
};

const Blend = struct {
    src_rgb: GL.BlendFactor,
    dst_rgb: GL.BlendFactor,
    src_alpha: GL.BlendFactor,
    dst_alpha: GL.BlendFactor,

    fn fromOperation(op: nvg.CompositeOperationState) Blend {
        return .{
            .src_rgb = convertBlendFuncFactor(op.src_rgb),
            .dst_rgb = convertBlendFuncFactor(op.dst_rgb),
            .src_alpha = convertBlendFuncFactor(op.src_alpha),
            .dst_alpha = convertBlendFuncFactor(op.dst_alpha),
        };
    }

    fn convertBlendFuncFactor(factor: nvg.BlendFactor) GL.BlendFactor {
        return switch (factor) {
            .zero => .ZERO,
            .one => .ONE,
            .src_color => .SRC_COLOR,
            .one_minus_src_color => .ONE_MINUS_SRC_COLOR,
            .dst_color => .DST_COLOR,
            .one_minus_dst_color => .ONE_MINUS_DST_COLOR,
            .src_alpha => .SRC_ALPHA,
            .one_minus_src_alpha => .ONE_MINUS_SRC_ALPHA,
            .dst_alpha => .DST_ALPHA,
            .one_minus_dst_alpha => .ONE_MINUS_DST_ALPHA,
            .src_alpha_saturate => .SRC_ALPHA_SATURATE,
        };
    }
};

const call_type = enum {
    none,
    fill,
    convexfill,
    stroke,
    triangles,
};

const Call = struct {
    call_type: call_type,
    image: i32,
    colormap: i32,
    path_offset: u32,
    path_count: u32,
    triangle_offset: u32,
    triangle_count: u32,
    uniform_offset: u32,
    blend_func: Blend,

    fn fill(call: Call, ctx: *GLContext) void {
        const gl = ctx.gl;
        const paths = ctx.paths.items[call.path_offset..][0..call.path_count];

        // Draw shapes
        gl.enable(.STENCIL_TEST);
        defer gl.disable(.STENCIL_TEST);
        gl.stencilMask(0xff);
        gl.stencilFunc(.ALWAYS, 0x0, 0xff);
        gl.colorMask(false, false, false, false);

        // set bindpoint for solid loc
        setUniforms(ctx, call.uniform_offset, 0, 0);
        ctx.checkError("fill simple");

        gl.stencilOpSeparate(.FRONT, .KEEP, .KEEP, .INCR_WRAP);
        gl.stencilOpSeparate(.BACK, .KEEP, .KEEP, .DECR_WRAP);
        gl.disable(.CULL_FACE);
        for (paths) |path| {
            gl.drawArrays(.TRIANGLE_FAN, @intCast(path.fill_offset), @intCast(path.fill_count));
        }
        gl.enable(.CULL_FACE);

        // Draw anti-aliased pixels
        gl.colorMask(true, true, true, true);

        setUniforms(ctx, call.uniform_offset + 1, call.image, call.colormap);
        ctx.checkError("fill fill");

        if (ctx.options.antialias) {
            gl.stencilFunc(.EQUAL, 0x00, 0xff);
            gl.stencilOp(.KEEP, .KEEP, .KEEP);
            // Draw fringes
            for (paths) |path| {
                gl.drawArrays(.TRIANGLE_STRIP, @intCast(path.stroke_offset), @intCast(path.stroke_count));
            }
        }

        // Draw fill
        gl.stencilFunc(.NOTEQUAL, 0x0, 0xff);
        gl.stencilOp(.ZERO, .ZERO, .ZERO);
        gl.drawArrays(.TRIANGLE_STRIP, @intCast(call.triangle_offset), @intCast(call.triangle_count));
    }

    fn convexFill(call: Call, ctx: *GLContext) void {
        const gl = ctx.gl;
        const paths = ctx.paths.items[call.path_offset..][0..call.path_count];

        setUniforms(ctx, call.uniform_offset, call.image, call.colormap);
        ctx.checkError("convex fill");

        for (paths) |path| {
            gl.drawArrays(.TRIANGLE_FAN, @intCast(path.fill_offset), @intCast(path.fill_count));
            // Draw fringes
            if (path.stroke_count > 0) {
                gl.drawArrays(.TRIANGLE_STRIP, @intCast(path.stroke_offset), @intCast(path.stroke_count));
            }
        }
    }

    fn stroke(call: Call, ctx: *GLContext) void {
        const gl = ctx.gl;
        const paths = ctx.paths.items[call.path_offset..][0..call.path_count];

        if (ctx.options.stencil_strokes) {
            gl.enable(.STENCIL_TEST);
            defer gl.disable(.STENCIL_TEST);

            gl.stencilMask(0xff);

            // Fill the stroke base without overlap
            gl.stencilFunc(.EQUAL, 0x0, 0xff);
            gl.stencilOp(.KEEP, .KEEP, .INCR);
            setUniforms(ctx, call.uniform_offset + 1, call.image, call.colormap);
            ctx.checkError("stroke fill 0");
            for (paths) |path| {
                gl.drawArrays(
                    .TRIANGLE_STRIP,
                    @intCast(path.stroke_offset),
                    @intCast(path.stroke_count),
                );
            }

            // Draw anti-aliased pixels.
            setUniforms(ctx, call.uniform_offset, call.image, call.colormap);
            gl.stencilFunc(.EQUAL, 0x00, 0xff);
            gl.stencilOp(.KEEP, .KEEP, .KEEP);
            for (paths) |path| {
                gl.drawArrays(
                    .TRIANGLE_STRIP,
                    @intCast(path.stroke_offset),
                    @intCast(path.stroke_count),
                );
            }

            // Clear stencil buffer.
            gl.colorMask(false, false, false, false);
            gl.stencilFunc(.ALWAYS, 0x0, 0xff);
            gl.stencilOp(.ZERO, .ZERO, .ZERO);
            ctx.checkError("stroke fill 1");
            for (paths) |path| {
                gl.drawArrays(
                    .TRIANGLE_STRIP,
                    @intCast(path.stroke_offset),
                    @intCast(path.stroke_count),
                );
            }
            gl.colorMask(true, true, true, true);
        } else {
            setUniforms(ctx, call.uniform_offset, call.image, call.colormap);
            // Draw Strokes
            for (paths) |path| {
                gl.drawArrays(
                    .TRIANGLE_STRIP,
                    @intCast(path.stroke_offset),
                    @intCast(path.stroke_count),
                );
            }
        }
    }

    fn triangles(call: Call, ctx: *GLContext) void {
        setUniforms(ctx, call.uniform_offset, call.image, call.colormap);
        ctx.checkError("triangles fill");
        ctx.gl.drawArrays(
            .TRIANGLES,
            @intCast(call.triangle_offset),
            @intCast(call.triangle_count),
        );
    }
};

const Path = struct {
    fill_offset: u32,
    fill_count: u32,
    stroke_offset: u32,
    stroke_count: u32,
};

fn maxVertCount(paths: []const internal.Path) usize {
    var count: usize = 0;
    for (paths) |path| {
        count += path.fill.len;
        count += path.stroke.len;
    }
    return count;
}

fn xformToMat3x4(m3: *[12]f32, t: *const [6]f32) void {
    m3[0] = t[0];
    m3[1] = t[1];
    m3[2] = 0;
    m3[3] = 0;
    m3[4] = t[2];
    m3[5] = t[3];
    m3[6] = 0;
    m3[7] = 0;
    m3[8] = t[4];
    m3[9] = t[5];
    m3[10] = 1;
    m3[11] = 0;
}

fn premulColor(c: nvg.Color) nvg.Color {
    return .{ .r = c.r * c.a, .g = c.g * c.a, .b = c.b * c.a, .a = c.a };
}

const FragUniforms = struct {
    scissor_mat: [12]f32, // matrices are actually 3 vec4s
    paint_mat: [12]f32,
    inner_color: nvg.Color,
    outer_color: nvg.Color,
    scissor_extent: [2]f32,
    scissor_scale: [2]f32,
    extent: [2]f32,
    radius: f32,
    feather: f32,
    stroke_mult: f32,
    stroke_thr: f32,
    tex_type: f32,
    shaderType: f32,

    fn fromPaint(
        frag: *FragUniforms,
        paint: *nvg.Paint,
        scissor: *internal.Scissor,
        width: f32,
        fringe: f32,
        stroke_thr: f32,
        ctx: *GLContext,
    ) i32 {
        var invxform: [6]f32 = undefined;

        frag.* = std.mem.zeroes(FragUniforms);

        frag.inner_color = premulColor(paint.inner_color);
        frag.outer_color = premulColor(paint.outer_color);

        if (scissor.extent[0] < -0.5 or scissor.extent[1] < -0.5) {
            @memset(&frag.scissor_mat, 0);
            frag.scissor_extent[0] = 1;
            frag.scissor_extent[1] = 1;
            frag.scissor_scale[0] = 1;
            frag.scissor_scale[1] = 1;
        } else {
            _ = nvg.transformInverse(&invxform, &scissor.xform);
            xformToMat3x4(&frag.scissor_mat, &invxform);
            frag.scissor_extent[0] = scissor.extent[0];
            frag.scissor_extent[1] = scissor.extent[1];
            frag.scissor_scale[0] = @sqrt(scissor.xform[0] * scissor.xform[0] + scissor.xform[2] * scissor.xform[2]) / fringe;
            frag.scissor_scale[1] = @sqrt(scissor.xform[1] * scissor.xform[1] + scissor.xform[3] * scissor.xform[3]) / fringe;
        }

        std.mem.copy(f32, &frag.extent, &paint.extent);
        frag.stroke_mult = (width * 0.5 + fringe * 0.5) / fringe;
        frag.stroke_thr = stroke_thr;

        if (paint.image.handle != 0) {
            const tex = ctx.findTexture(paint.image.handle) orelse return 0;
            if (tex.flags.flip_y) {
                var m1: [6]f32 = undefined;
                var m2: [6]f32 = undefined;
                nvg.transformTranslate(&m1, 0, frag.extent[1] * 0.5);
                nvg.transformMultiply(&m1, &paint.xform);
                nvg.transformScale(&m2, 1, -1);
                nvg.transformMultiply(&m2, &m1);
                nvg.transformTranslate(&m1, 0, -frag.extent[1] * 0.5);
                nvg.transformMultiply(&m1, &m2);
                _ = nvg.transformInverse(&invxform, &m1);
            } else {
                _ = nvg.transformInverse(&invxform, &paint.xform);
            }
            frag.shaderType = @floatFromInt(@intFromEnum(ShaderType.fill_image));

            if (tex.tex_type == .rgba) {
                frag.tex_type = if (tex.flags.premultiplied) 0 else 1;
            } else if (paint.colormap.handle == 0) {
                frag.tex_type = 2;
            } else {
                frag.tex_type = 3;
            }
        } else {
            frag.shaderType = @floatFromInt(@intFromEnum(ShaderType.fill_gradient));
            frag.radius = paint.radius;
            frag.feather = paint.feather;
            _ = nvg.transformInverse(&invxform, &paint.xform);
        }

        xformToMat3x4(&frag.paint_mat, &invxform);

        return 1;
    }
};

fn setUniforms(ctx: *GLContext, uniform_offset: u32, image: i32, colormap: i32) void {
    const gl = ctx.gl;
    const frag = &ctx.uniforms.items[uniform_offset];
    gl.uniform4fv(ctx.shader.frag_loc, 11, @ptrCast(frag));

    if (colormap != 0) {
        if (ctx.findTexture(colormap)) |tex| {
            gl.activeTexture(1);
            gl.bindTexture(.TEXTURE_2D, tex.tex);
            gl.activeTexture(0);
        }
    }

    if (image != 0) {
        if (ctx.findTexture(image)) |tex| {
            gl.bindTexture(.TEXTURE_2D, tex.tex);
        }
    }
    // // If no image is set, use empty texture
    // if (tex == NULL) {
    // 	tex = glnvg__findTexture(gl->dummyTex);
    // }
    // glnvg__bindTexture(tex != NULL ? tex->tex : 0);
    // ctx.checkError("tex paint tex");
}

fn renderCreate(uptr: *anyopaque) !void {
    const ctx = GLContext.castPtr(uptr);
    const gl = ctx.gl;

    try ctx.shader.create(
        gl,
        if (ctx.options.antialias)
            "#version 330 core\n#define EDGE_AA 1\n"
        else
            "#version 330 core\n",
        @embedFile("shader/vert.glsl"),
        @embedFile("shader/frag.glsl"),
    );

    gl.genVertexArrays(1, &ctx.vert_arr);
    gl.genBuffers(1, &ctx.vert_buf);

    // Some platforms does not allow to have samples to unset textures.
    // Create empty one which is bound when there's no texture specified.
    // ctx.dummyTex = glnvg__renderCreateTexture(NVG_TEXTURE_ALPHA, 1, 1, 0, NULL);
}

fn renderCreateTexture(
    uptr: *anyopaque,
    tex_type: internal.TextureType,
    w: i32,
    h: i32,
    flags: nvg.ImageFlags,
    data: ?[*]const u8,
) !i32 {
    const ctx = GLContext.castPtr(uptr);
    const gl = ctx.gl;
    var tex: *Texture = try ctx.allocTexture();

    gl.genTextures(1, &tex.tex);
    tex.width = w;
    tex.height = h;
    tex.tex_type = tex_type;
    tex.flags = flags;
    gl.bindTexture(.TEXTURE_2D, tex.tex);

    switch (tex_type) {
        .none => {},
        .alpha => {
            gl.pixelStorei(.UNPACK_ALIGNMENT, 1);
            gl.texImage2D(
                .TEXTURE_2D,
                0,
                .RED,
                w,
                h,
                0,
                .RED,
                .UNSIGNED_BYTE,
                data,
            );
            gl.pixelStorei(.UNPACK_ALIGNMENT, 4);
        },
        .rgba => gl.texImage2D(
            .TEXTURE_2D,
            0,
            .RGBA,
            w,
            h,
            0,
            .RGBA,
            .UNSIGNED_BYTE,
            data,
        ),
    }

    const wrap_s: GL.Enum = if (flags.repeat_x) .REPEAT else .CLAMP_TO_EDGE;
    const wrap_t: GL.Enum = if (flags.repeat_y) .REPEAT else .CLAMP_TO_EDGE;
    gl.texParameteri(.TEXTURE_2D, .TEXTURE_WRAP_S, wrap_s);
    gl.texParameteri(.TEXTURE_2D, .TEXTURE_WRAP_T, wrap_t);

    const mag_filter: GL.Enum = if (flags.nearest) .NEAREST else .LINEAR;
    gl.texParameteri(.TEXTURE_2D, .TEXTURE_MAG_FILTER, mag_filter);

    if (flags.generate_mipmaps) {
        const min_filter: GL.Enum = if (flags.nearest)
            .NEAREST_MIPMAP_NEAREST
        else
            .LINEAR_MIPMAP_LINEAR;
        gl.texParameteri(.TEXTURE_2D, .TEXTURE_MIN_FILTER, min_filter);
        gl.generateMipmap(.TEXTURE_2D);
    } else {
        const min_filter: GL.Enum = if (flags.nearest) .NEAREST else .LINEAR;
        gl.texParameteri(.TEXTURE_2D, .TEXTURE_MIN_FILTER, min_filter);
    }

    return tex.id;
}

fn renderDeleteTexture(uptr: *anyopaque, image: i32) void {
    const ctx = GLContext.castPtr(uptr);
    const tex = ctx.findTexture(image) orelse return;
    if (tex.tex != 0) ctx.gl.deleteTextures(1, &tex.tex);
    tex.* = std.mem.zeroes(Texture);
}

fn renderUpdateTexture(
    uptr: *anyopaque,
    image: i32,
    x_arg: i32,
    y: i32,
    w_arg: i32,
    h: i32,
    data_arg: ?[*]const u8,
) i32 {
    _ = x_arg;
    _ = w_arg;
    const ctx = GLContext.castPtr(uptr);
    const tex = ctx.findTexture(image) orelse return 0;
    const gl = ctx.gl;

    // No support for all of skip, need to update a whole row at a time.
    const color_size: u32 = if (tex.tex_type == .rgba) 4 else 1;
    const y0: u32 = @intCast(y * tex.width);
    const data = &data_arg.?[y0 * color_size];
    const x = 0;
    const w = tex.width;

    gl.bindTexture(.TEXTURE_2D, tex.tex);
    switch (tex.tex_type) {
        .none => {},
        .alpha => {
            gl.pixelStorei(.UNPACK_ALIGNMENT, 1);
            gl.texSubImage2D(.TEXTURE_2D, 0, x, y, w, h, .RED, .UNSIGNED_BYTE, data);
            gl.pixelStorei(.UNPACK_ALIGNMENT, 4);
        },
        .rgba => gl.texSubImage2D(.TEXTURE_2D, 0, x, y, w, h, .RGBA, .UNSIGNED_BYTE, data),
    }
    gl.bindTexture(.TEXTURE_2D, 0);

    return 1;
}

fn renderGetTextureSize(uptr: *anyopaque, image: i32, w: *i32, h: *i32) i32 {
    const ctx = GLContext.castPtr(uptr);
    const tex = ctx.findTexture(image) orelse return 0;
    w.* = tex.width;
    h.* = tex.height;
    return 1;
}

fn renderViewport(uptr: *anyopaque, width: f32, height: f32, devicePixelRatio: f32) void {
    const ctx = GLContext.castPtr(uptr);
    ctx.view[0] = width;
    ctx.view[1] = height;
    _ = devicePixelRatio;
}

fn renderCancel(uptr: *anyopaque) void {
    const ctx = GLContext.castPtr(uptr);
    ctx.verts.clearRetainingCapacity();
    ctx.paths.clearRetainingCapacity();
    ctx.calls.clearRetainingCapacity();
    ctx.uniforms.clearRetainingCapacity();
}

fn renderFlush(uptr: *anyopaque) void {
    const ctx = GLContext.castPtr(uptr);
    const gl = ctx.gl;

    if (ctx.calls.items.len > 0) {
        // Setup required GL state.
        gl.useProgram(ctx.shader.prog);

        gl.enable(.CULL_FACE);
        gl.cullFace(.BACK);
        gl.frontFace(.CCW);
        gl.enable(.BLEND);
        gl.disable(.DEPTH_TEST);
        gl.disable(.SCISSOR_TEST);
        gl.colorMask(true, true, true, true);
        gl.stencilMask(0xffffffff);
        gl.stencilOp(.KEEP, .KEEP, .KEEP);
        gl.stencilFunc(.ALWAYS, 0, 0xffffffff);
        gl.activeTexture(0);
        gl.bindTexture(.TEXTURE_2D, 0);

        gl.bindVertexArray(ctx.vert_arr);
        gl.bindBuffer(.ARRAY_BUFFER, ctx.vert_buf);
        gl.bufferData(
            .ARRAY_BUFFER,
            @intCast(ctx.verts.items.len * @sizeOf(internal.Vertex)),
            ctx.verts.items.ptr,
            .STREAM_DRAW,
        );
        gl.enableVertexAttribArray(0);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(0, 2, .FLOAT, false, @sizeOf(internal.Vertex), null);
        gl.vertexAttribPointer(1, 2, .FLOAT, false, @sizeOf(internal.Vertex), @ptrFromInt(2 * @sizeOf(f32)));

        // Set view and texture just once per frame.
        gl.uniform1i(ctx.shader.tex_loc, 0);
        gl.uniform1i(ctx.shader.colormap_loc, 1);
        gl.uniform2fv(ctx.shader.view_loc, 1, &ctx.view[0]);

        for (ctx.calls.items) |call| {
            gl.blendFuncSeparate(
                call.blend_func.src_rgb,
                call.blend_func.dst_rgb,
                call.blend_func.src_alpha,
                call.blend_func.dst_alpha,
            );
            switch (call.call_type) {
                .none => {},
                .fill => call.fill(ctx),
                .convexfill => call.convexFill(ctx),
                .stroke => call.stroke(ctx),
                .triangles => call.triangles(ctx),
            }
        }

        gl.disableVertexAttribArray(0);
        gl.disableVertexAttribArray(1);
        gl.disable(.CULL_FACE);
        gl.bindBuffer(.ARRAY_BUFFER, 0);
        gl.bindVertexArray(0);
        gl.useProgram(0);
        gl.bindTexture(.TEXTURE_2D, 0);
    }

    // Reset calls
    ctx.verts.clearRetainingCapacity();
    ctx.paths.clearRetainingCapacity();
    ctx.calls.clearRetainingCapacity();
    ctx.uniforms.clearRetainingCapacity();
}

fn renderFill(
    uptr: *anyopaque,
    paint: *nvg.Paint,
    composite_operation: nvg.CompositeOperationState,
    scissor: *internal.Scissor,
    fringe: f32,
    bounds: [4]f32,
    paths: []const internal.Path,
) void {
    const ctx = GLContext.castPtr(uptr);

    const call = ctx.calls.addOne(ctx.allocator) catch return;
    call.* = std.mem.zeroes(Call);

    call.call_type = .fill;
    call.triangle_count = 4;
    if (paths.len == 1 and paths[0].convex) {
        call.call_type = .convexfill;
        call.triangle_count = 0; // Bounding box fill quad not needed for convex fill
    }
    ctx.paths.ensureUnusedCapacity(ctx.allocator, paths.len) catch return;
    call.path_offset = @intCast(ctx.paths.items.len);
    call.path_count = @intCast(paths.len);
    call.image = paint.image.handle;
    call.colormap = paint.colormap.handle;
    call.blend_func = Blend.fromOperation(composite_operation);

    // Allocate vertices for all the paths.
    const maxverts = maxVertCount(paths) + call.triangle_count;
    ctx.verts.ensureUnusedCapacity(ctx.allocator, maxverts) catch return;

    for (paths) |path| {
        const copy = ctx.paths.addOneAssumeCapacity();
        copy.* = std.mem.zeroes(Path);
        if (path.fill.len > 0) {
            copy.fill_offset = @intCast(ctx.verts.items.len);
            copy.fill_count = @intCast(path.fill.len);
            ctx.verts.appendSliceAssumeCapacity(path.fill);
        }
        if (path.stroke.len > 0) {
            copy.stroke_offset = @intCast(ctx.verts.items.len);
            copy.stroke_count = @intCast(path.stroke.len);
            ctx.verts.appendSliceAssumeCapacity(path.stroke);
        }
    }

    // Setup uniforms for draw calls
    if (call.call_type == .fill) {
        // Quad
        call.triangle_offset = @intCast(ctx.verts.items.len);
        ctx.verts.appendAssumeCapacity(.{ .x = bounds[2], .y = bounds[3], .u = 0.5, .v = 1.0 });
        ctx.verts.appendAssumeCapacity(.{ .x = bounds[2], .y = bounds[1], .u = 0.5, .v = 1.0 });
        ctx.verts.appendAssumeCapacity(.{ .x = bounds[0], .y = bounds[3], .u = 0.5, .v = 1.0 });
        ctx.verts.appendAssumeCapacity(.{ .x = bounds[0], .y = bounds[1], .u = 0.5, .v = 1.0 });

        call.uniform_offset = @intCast(ctx.uniforms.items.len);
        ctx.uniforms.ensureUnusedCapacity(ctx.allocator, 2) catch return;
        // Simple shader for stencil
        const frag = ctx.uniforms.addOneAssumeCapacity();
        frag.* = std.mem.zeroes(FragUniforms);
        frag.stroke_thr = -1.0;
        frag.shaderType = @floatFromInt(@intFromEnum(ShaderType.simple));
        // Fill shader
        _ = ctx.uniforms.addOneAssumeCapacity().fromPaint(paint, scissor, fringe, fringe, -1.0, ctx);
    } else {
        call.uniform_offset = @intCast(ctx.uniforms.items.len);
        ctx.uniforms.ensureUnusedCapacity(ctx.allocator, 1) catch return;
        // Fill shader
        _ = ctx.uniforms.addOneAssumeCapacity().fromPaint(paint, scissor, fringe, fringe, -1.0, ctx);
    }
}

fn renderStroke(
    uptr: *anyopaque,
    paint: *nvg.Paint,
    composite_operation: nvg.CompositeOperationState,
    scissor: *internal.Scissor,
    fringe: f32,
    strokeWidth: f32,
    paths: []const internal.Path,
) void {
    const ctx = GLContext.castPtr(uptr);

    const call = ctx.calls.addOne(ctx.allocator) catch return;
    call.* = std.mem.zeroes(Call);

    call.call_type = .stroke;
    ctx.paths.ensureUnusedCapacity(ctx.allocator, paths.len) catch return;
    call.path_offset = @intCast(ctx.paths.items.len);
    call.path_count = @intCast(paths.len);
    call.image = paint.image.handle;
    call.colormap = paint.colormap.handle;
    call.blend_func = Blend.fromOperation(composite_operation);

    // Allocate vertices for all the paths.
    const maxverts = maxVertCount(paths);
    ctx.verts.ensureUnusedCapacity(ctx.allocator, maxverts) catch return;

    for (paths) |path| {
        const copy = ctx.paths.addOneAssumeCapacity();
        copy.* = std.mem.zeroes(Path);
        if (path.stroke.len > 0) {
            copy.stroke_offset = @intCast(ctx.verts.items.len);
            copy.stroke_count = @intCast(path.stroke.len);
            ctx.verts.appendSliceAssumeCapacity(path.stroke);
        }
    }

    if (ctx.options.stencil_strokes) {
        // Fill shader
        call.uniform_offset = @intCast(ctx.uniforms.items.len);
        ctx.uniforms.ensureUnusedCapacity(ctx.allocator, 2) catch return;
        _ = ctx.uniforms.addOneAssumeCapacity().fromPaint(paint, scissor, fringe, fringe, -1, ctx);
        _ = ctx.uniforms.addOneAssumeCapacity().fromPaint(paint, scissor, strokeWidth, fringe, 1.0 - 0.5 / 255.0, ctx);
    } else {
        // Fill shader
        call.uniform_offset = @intCast(ctx.uniforms.items.len);
        _ = ctx.uniforms.ensureUnusedCapacity(ctx.allocator, 1) catch return;
        _ = ctx.uniforms.addOneAssumeCapacity().fromPaint(paint, scissor, strokeWidth, fringe, -1, ctx);
    }
}

fn renderTriangles(
    uptr: *anyopaque,
    paint: *nvg.Paint,
    comp_op: nvg.CompositeOperationState,
    scissor: *internal.Scissor,
    fringe: f32,
    verts: []const internal.Vertex,
) void {
    const ctx = GLContext.castPtr(uptr);

    const call = ctx.calls.addOne(ctx.allocator) catch return;
    call.* = std.mem.zeroes(Call);

    call.call_type = .triangles;
    call.image = paint.image.handle;
    call.colormap = paint.colormap.handle;
    call.blend_func = Blend.fromOperation(comp_op);

    call.triangle_offset = @intCast(ctx.verts.items.len);
    call.triangle_count = @intCast(verts.len);
    ctx.verts.appendSlice(ctx.allocator, verts) catch return;

    call.uniform_offset = @intCast(ctx.uniforms.items.len);
    const frag = ctx.uniforms.addOne(ctx.allocator) catch return;
    _ = frag.fromPaint(paint, scissor, 1, fringe, -1, ctx);
    frag.shaderType = @floatFromInt(@intFromEnum(ShaderType.image));
}

fn renderDelete(uptr: *anyopaque) void {
    const ctx = GLContext.castPtr(uptr);
    ctx.deinit();
}
