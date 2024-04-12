const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

//== Common ===//

// Rexport std.math for convenience
pub usingnamespace math;

inline fn compileError(comptime fmt: []const u8, args: anytype) void {
    @compileError(std.fmt.comptimePrint(fmt, args));
}

//== Vectors ===//

pub fn vec2(comptime T: type, v: anytype) Vec2(T) {
    return Vec2(T).init(v);
}

pub fn Vec2(comptime T: type) type {
    return extern struct {
        x: T = @as(T, 0),
        y: T = @as(T, 0),

        const Vec = @This();
        pub usingnamespace VecImpl(Vec, T);

        pub fn rotate(v: Vec, r: Vec) Vec {
            return .{
                .x = r.x * v.x - r.y * v.y,
                .y = r.y * v.x + r.x * v.y,
            };
        }

        pub fn rotateInv(v: Vec, r: Vec) Vec {
            return .{
                .x = r.x * v.x + r.y * v.y,
                .y = -r.y * v.x + r.x * v.y,
            };
        }
    };
}

pub fn vec3(comptime T: type, v: anytype) Vec3(T) {
    return Vec3(T).init(v);
}

pub fn Vec3(comptime T: type) type {
    return extern struct {
        x: T = @as(T, 0),
        y: T = @as(T, 0),
        z: T = @as(T, 0),

        pub usingnamespace VecImpl(@This(), T);
    };
}

pub fn vec4(comptime T: type, v: anytype) Vec4(T) {
    return Vec4(T).init(v);
}

pub fn Vec4(comptime T: type) type {
    return extern struct {
        x: T = @as(T, 0),
        y: T = @as(T, 0),
        z: T = @as(T, 0),
        w: T = @as(T, 0),

        pub usingnamespace VecImpl(@This(), T);
    };
}

/// Mixin that provide a common implementation for a vector-like type Vec.
/// Vec must be a structs containing only fields of type T, each with a default value
pub fn VecImpl(comptime Vec: type, comptime T: type) type {
    const info = @typeInfo(Vec).Struct;
    const fields = info.fields;

    comptime if (info.layout != .Extern) {
        @compileError("Only structs with extern layout are currently supported");
    };

    inline for (fields) |field| {
        // All fields must be of the same type
        comptime assert(field.type == T);
        // All fields must have a default value
        comptime assert(field.default_value != null);
    }

    return struct {
        pub const is_float = switch (@typeInfo(T)) {
            .Float => true,
            .Int => false,
            else => compileError("Expected scalar type, got {s}", .{@typeName(T)}),
        };

        /// Initialize vector from a series of scalar values (may be a single value, an array, a
        /// tuple or a struct with length greater or equal to the vector size)
        pub fn init(v: anytype) Vec {
            const V = @TypeOf(v);
            const type_err = std.fmt.comptimePrint(
                "Expected scalar, array, tuple or struct of scalars, got {s}",
                .{@typeName(V)},
            );

            // Default initialize
            var r = Vec{};
            comptime var len = 0;
            switch (@typeInfo(V)) {
                // If a single scalar is given, assign it to all components
                .Int, .Float, .ComptimeInt, .ComptimeFloat => {
                    inline for (fields) |field| {
                        const name = field.name;
                        @field(r, name) = @as(T, v);
                    }
                },
                // For sequence types, store the given number of components
                .Array => |a| len = a.len,
                .Struct => |s| {
                    len = if (s.is_tuple) s.fields.len else @compileError(type_err);
                    if (s.is_tuple) {
                        len = s.fields.len;
                    } else {
                        // If a struct is given, try to use the same fields
                        comptime assert(s.fields.len >= fields.len);
                        inline for (fields) |field| {
                            const name = field.name;
                            @field(r, name) = @field(v, name);
                        }
                    }
                },
                else => @compileError(type_err),
            }

            inline for (0..len) |i| {
                @field(r, fields[i].name) = @as(T, v[i]);
            }

            return r;
        }

        // Initialization utils for float vectors
        pub usingnamespace if (is_float) struct {
            /// Initialize float vector from a sequence of integers
            pub fn fromInt(v: anytype) Vec {
                const V = @TypeOf(v);
                const type_err = std.fmt.comptimePrint(
                    "Expected integer, array, tuple or struct of integers, got {s}",
                    .{@typeName(V)},
                );

                // Default initialize
                var r = Vec{};
                comptime var len = 0;
                switch (@typeInfo(V)) {
                    // If a single scalar is given, assign it to all components
                    .Int, .ComptimeInt => {
                        inline for (fields) |field| {
                            const name = field.name;
                            @field(r, name) = @floatFromInt(v);
                        }
                    },
                    // For sequence types, store the given number of components
                    .Array => |a| len = a.len,
                    .Struct => |s| {
                        if (s.is_tuple) {
                            len = s.fields.len;
                        } else {
                            // If a struct is given, try to use the same fields
                            comptime assert(s.fields.len >= fields.len);
                            inline for (fields) |field| {
                                const name = field.name;
                                @field(r, name) = @floatFromInt(@field(v, name));
                            }
                        }
                    },
                    else => @compileError(type_err),
                }

                inline for (0..len) |i| {
                    @field(r, fields[i].name) = @floatFromInt(v[i]);
                }

                return r;
            }
        } else struct {};

        /// Addition with scalar or other vector
        pub inline fn add(a: Vec, b: anytype) Vec {
            const B = @TypeOf(b);

            var r: Vec = undefined;

            switch (B) {
                T => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) + b;
                },
                Vec => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) + @field(b, name);
                },
                else => compileError(
                    "Expected {s} or {s}, got {s}",
                    .{ @typeName(Vec), @typeName(T), @typeName(B) },
                ),
            }

            return r;
        }

        /// Subtraction with scalar or other vector
        pub inline fn sub(a: Vec, b: anytype) Vec {
            const B = @TypeOf(b);
            var r: Vec = undefined;

            switch (B) {
                T => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) - b;
                },
                Vec => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) - @field(b, name);
                },
                else => compileError(
                    "Expected {s} or {s}, got {s}",
                    .{ @typeName(Vec), @typeName(T), @typeName(B) },
                ),
            }

            return r;
        }

        /// Multiplication by scalar or Hadamard product with other vector
        pub inline fn mul(a: Vec, b: T) Vec {
            const B = @TypeOf(b);
            var r: Vec = undefined;

            switch (B) {
                T => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) * b;
                },
                Vec => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) * @field(b, name);
                },
                else => compileError(
                    "Expected {s} or {s}, got {s}",
                    .{ @typeName(Vec), @typeName(T), @typeName(B) },
                ),
            }

            return r;
        }

        /// Division by scalar or Hadamard division with other vector
        pub inline fn div(a: Vec, b: T) Vec {
            const B = @TypeOf(b);
            var r: Vec = undefined;

            switch (B) {
                T => inline for (fields) |field| {
                    const name = field.name;
                    const f = @as(T, 1) / b;
                    @field(r, name) = @field(a, name) * f;
                },
                Vec => inline for (fields) |field| {
                    const name = field.name;
                    @field(r, name) = @field(a, name) / @field(b, name);
                },
                else => compileError(
                    "Expected {s} or {s}, got {s}",
                    .{ @typeName(Vec), @typeName(T), @typeName(B) },
                ),
            }

            return r;
        }

        /// Scalar (dot) product between two vectors
        pub inline fn dot(a: Vec, b: Vec) T {
            var r: T = 0;

            inline for (fields) |field| {
                const name = field.name;
                r += @field(a, name) * @field(b, name);
            }

            return r;
        }

        /// Compute squared norm of given vector
        pub inline fn normSq(vec: Vec) T {
            return vec.dot(vec);
        }

        /// Compute norm of given vector
        pub inline fn norm(vec: Vec) T {
            return math.sqrt(vec.normSq());
        }

        /// Compute squared distance between two vectors (squared norm of the difference)
        pub inline fn distSq(a: Vec, b: Vec) T {
            return a.sub(b).norm();
        }

        /// Compute distance between two vectors (norm of the difference)
        pub inline fn dist(a: Vec, b: Vec) T {
            return math.sqrt(a.distSq(b));
        }
    };
}

test "math.Vec" {
    const a = vec2(f32, 0);

    try std.testing.expect(@sizeOf(@TypeOf(a)) == 2 * @sizeOf(f32));
    try std.testing.expect(a.x == a.y and a.x == 0);

    const b = vec2(f32, .{1});

    try std.testing.expect(@TypeOf(a) == @TypeOf(b));
    try std.testing.expect(b.x == 1 and b.y == 0);

    try std.testing.expect(a.dist(b) == 1);
}

//== Matrices ===//

// TODO (Matteo): Implement common matrix operations and transformations

/// A 4x4 matrix suitable for representing linear, affine and projective
/// transformations
///
/// Default value is identity
pub fn Mat4(comptime T: type) type {
    return extern struct {
        cols: [4]Vec = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },

        // TODO (Matteo): Check if using a (possibly) SIMD vector actually gives
        // performance benefits
        const Vec = @Vector(4, T);
        const Mat = @This();
    };
}

/// Affine transformation in 2D space, represented by an actual 2x3 matrix plus
/// an implict 3rd row {0,0,1}.
///
/// Default value is identity
///
/// The layout of the matrix is not explicit in the struct name, in order to
/// better communicate the intented use and avoid confusion (e.g. two 2x3
/// matrices cannot be multiplied together)
pub fn AffineMat2(comptime T: type) type {
    return extern struct {
        cols: [3]Vec = .{
            Vec.init(.{ 1, 0 }),
            Vec.init(.{ 0, 1 }),
            Vec.init(.{ 0, 0 }),
        },

        const Vec = Vec2(T);
        const Mat = @This();

        fn MulRet(comptime Operand: type) type {
            return switch (Operand) {
                Mat, Vec => Operand,
                else => @compileError(std.fmt.comptimePrint(
                    "Expected {s} or {s}, got {s}",
                    .{ @typeName(Mat), @typeName(Vec), @typeName(Operand) },
                )),
            };
        }

        pub fn mul(a: Mat, b: anytype) MulRet(@TypeOf(b)) {
            switch (@TypeOf(b)) {
                Mat => {
                    var r = Mat{};
                    r.cols[0] = Vec.add(
                        a.cols[0].mul(b.cols[0].x),
                        a.cols[1].mul(b.cols[0].y),
                    );
                    r.cols[1] = Vec.add(
                        a.cols[0].mul(b.cols[1].x),
                        a.cols[1].mul(b.cols[1].y),
                    );
                    r.cols[2] = Vec.add(
                        a.cols[0].mul(b.cols[2].x),
                        a.cols[1].mul(b.cols[2].y),
                    ).add(a.cols[2]);
                    return r;
                },
                Vec => {
                    return Vec.add(
                        a.cols[0].mul(b.x),
                        a.cols[1].mul(b.y),
                    ).add(a.cols[2]);
                },
                else => unreachable,
            }
        }
    };
}

test "math.Mat" {
    const aff = AffineMat2(f32){};
    const vec = vec2(f32, .{ 2, 3 });
    const mul = aff.mul(vec);

    try std.testing.expect(vec.x == mul.x);
    try std.testing.expect(vec.y == mul.y);
}

//=== 2D Geometric primitives ===//

/// Aligned box, a.k.a. rectangle with 0° rotation
pub fn AlignedBox2(comptime T: type) type {
    const Vec = Vec2(T);

    return extern struct {
        origin: Vec = .{},
        size: Vec = .{},

        const Self = @This();

        pub inline fn center(self: Self) Vec {
            return self.size.mul(0.5).add(self.origin);
        }

        pub fn contains(
            self: Self,
            point: Vec,
        ) bool {
            const min = self.origin;
            const max = self.origin.add(self.size);

            if (point.x < min.x) return false;
            if (point.y < min.y) return false;
            if (point.x > max.x) return false;
            if (point.y > max.y) return false;

            return true;
        }

        pub fn offset(self: Self, amount: T) Self {
            return .{
                .origin = self.origin.sub(amount / 2),
                .size = self.size.add(amount),
            };
        }

        pub fn asArray(ptr: *Self) *[4]T {
            return @ptrCast(ptr);
        }

        pub fn toArray(self: Self) [4]T {
            // TODO (Matteo): Improve? Assignment to local variable is required,
            // because self is constant.
            var temp = self;
            return temp.asArray().*;
        }
    };
}

test "math.AlignedBox2" {
    const box = rect(@as(f32, 10), 10, 30, 50);
    const arr = box.toArray();

    try std.testing.expect(arr[0] == box.origin.x);
    try std.testing.expect(arr[1] == box.origin.y);
    try std.testing.expect(arr[2] == box.size.x);
    try std.testing.expect(arr[3] == box.size.y);
}

/// Oriented box, a.k.a. rectangle with arbitary rotation
pub fn OrientedBox2(comptime T: type) type {
    return extern struct {
        origin: Vec2(T) = .{},
        size: Vec2(T) = .{},
        dir: Vec2(T) = .{},
    };
}

/// Ellipse (circle is a degenerate case) with arbitary rotation
pub fn Ellipse2(comptime T: type) type {
    return extern struct {
        center: Vec2(T) = .{},
        size: Vec2(T) = .{},
        dir: Vec2(T) = .{},
    };
}

// TODO (Matteo): Nomenclature review?
pub inline fn rect(
    x: anytype,
    y: @TypeOf(x),
    w: @TypeOf(x),
    h: @TypeOf(x),
) AlignedBox2(@TypeOf(x)) {
    return .{
        .origin = .{ .x = x, .y = y },
        .size = .{ .x = w, .y = h },
    };
}
