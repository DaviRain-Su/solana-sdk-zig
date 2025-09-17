# Solana-Program-Zig 实现路线图

## 📋 概述

本文档提供了从当前状态逐步实现完整 Solana-Program-Zig SDK 的详细路线图。基于依赖关系分析，我们已经完成了基础模块，现在需要实现关键的程序执行功能。

## 🎯 当前状态

### ✅ 已完成模块
- `pubkey.zig` - 公钥类型和操作
- `account_info.zig` - 账户信息结构
- `instruction.zig` - 指令和账户元数据
- `program_error.zig` - 错误处理
- `log.zig` - 日志输出
- `syscalls.zig` - 系统调用绑定
- `bpf.zig` - BPF/SBF 平台检测

### ❌ 待实现模块
- `entrypoint.zig` - 程序入口点
- `cpi.zig` - 跨程序调用
- `sysvars/` - 系统变量
- 序列化支持

## 🚀 实现路线图

### 第一阶段：核心程序功能（第1-2天）

#### 1. 实现 `entrypoint.zig`（最高优先级）

**目标**：使程序能够被 Solana 运行时调用

**实现要点**：
```zig
// src/entrypoint.zig

const std = @import("std");
const AccountInfo = @import("account_info.zig").AccountInfo;
const Pubkey = @import("pubkey.zig").Pubkey;
const ProgramResult = @import("program_error.zig").ProgramResult;
const SUCCESS = @import("program_error.zig").SUCCESS;

/// 标准程序入口点
pub fn entrypoint(
    comptime process_instruction: fn(
        program_id: *const Pubkey,
        accounts: []AccountInfo,
        instruction_data: []const u8
    ) ProgramResult
) void {
    // 导出 C ABI 兼容的入口函数
    const entrypoint_impl = struct {
        fn entrypoint_c(input: [*]u8) callconv(.C) u64 {
            // 1. 解析输入缓冲区
            var offset: usize = 0;

            // 2. 解析账户数量
            const num_accounts = input[offset];
            offset += 1;

            // 3. 解析账户信息数组
            var accounts: [MAX_TX_ACCOUNTS]AccountInfo = undefined;
            for (0..num_accounts) |i| {
                accounts[i] = parseAccount(input[offset..]);
                offset += getAccountSize(input[offset..]);
            }

            // 4. 解析指令数据长度
            const data_len = @as(usize, input[offset]) |
                              (@as(usize, input[offset + 1]) << 8);
            offset += 2;

            // 5. 获取指令数据切片
            const instruction_data = input[offset..offset + data_len];
            offset += data_len;

            // 6. 解析 program_id
            const program_id = @ptrCast(*const Pubkey, @alignCast(
                @alignOf(Pubkey),
                input + offset
            ));

            // 7. 调用用户的处理函数
            const result = process_instruction(
                program_id,
                accounts[0..num_accounts],
                instruction_data
            );

            // 8. 返回结果码
            return switch (result) {
                SUCCESS => 0,
                else => @intFromError(result),
            };
        }
    };

    // 导出符号
    @export(entrypoint_impl.entrypoint_c, .{
        .name = "entrypoint",
        .linkage = .strong,
    });
}

/// 解析单个账户信息
fn parseAccount(input: []const u8) AccountInfo {
    // 实现账户解析逻辑
    // 参考 Rust 版本的内存布局
}
```

**测试用例**：
```zig
// examples/hello_world.zig
const pinocchio = @import("pinocchio");

fn process_instruction(
    program_id: *const pinocchio.Pubkey,
    accounts: []pinocchio.AccountInfo,
    instruction_data: []const u8
) pinocchio.ProgramResult {
    _ = program_id;
    _ = accounts;
    _ = instruction_data;

    pinocchio.log.print("Hello, Solana from Zig!", .{});
    return pinocchio.SUCCESS;
}

pub const entrypoint = pinocchio.entrypoint(process_instruction);
```

#### 2. 实现 `lazy_entrypoint.zig`（可选优化）

**目标**：提供延迟解析的入口点，减少不必要的账户解析开销

```zig
// src/lazy_entrypoint.zig

pub const LazyAccountInfo = struct {
    input: [*]const u8,
    offset: usize,

    pub fn parse(self: *LazyAccountInfo) AccountInfo {
        // 按需解析账户
    }
};

pub fn lazy_entrypoint(
    comptime process: fn(LazyContext) ProgramResult
) void {
    // 实现延迟解析逻辑
}
```

### 第二阶段：跨程序调用（第3-4天）

#### 3. 实现 `cpi.zig`

**目标**：支持调用其他 Solana 程序

**实现要点**：
```zig
// src/cpi.zig

const std = @import("std");
const syscalls = @import("syscalls.zig");
const AccountInfo = @import("account_info.zig").AccountInfo;
const Instruction = @import("instruction.zig").Instruction;
const ProgramResult = @import("program_error.zig").ProgramResult;

/// 调用另一个程序（无签名）
pub fn invoke(
    instruction: *const Instruction,
    accounts: []AccountInfo,
) ProgramResult {
    // 1. 验证账户权限
    for (instruction.accounts) |account_meta| {
        const account_info = findAccount(accounts, &account_meta.pubkey) orelse
            return error.MissingAccount;

        if (account_meta.is_writable and !account_info.is_writable) {
            return error.InvalidAccountData;
        }
        if (account_meta.is_signer and !account_info.is_signer) {
            return error.MissingRequiredSignature;
        }
    }

    // 2. 序列化指令数据
    var instruction_buf: [1024]u8 = undefined;
    const serialized = serializeInstruction(instruction, &instruction_buf);

    // 3. 序列化账户信息
    var accounts_buf: [1024]u8 = undefined;
    const serialized_accounts = serializeAccounts(accounts, &accounts_buf);

    // 4. 调用系统调用
    const result = syscalls.sol_invoke_signed_c(
        serialized.ptr,
        serialized_accounts.ptr,
        serialized_accounts.len,
        null, // 无签名种子
        0
    );

    return if (result == 0) SUCCESS else error.CustomError;
}

/// 使用 PDA 签名调用另一个程序
pub fn invoke_signed(
    instruction: *const Instruction,
    accounts: []AccountInfo,
    signers_seeds: []const []const []const u8,
) ProgramResult {
    // 1. 验证账户（同上）

    // 2. 序列化签名种子
    var seeds_buf: [1024]u8 = undefined;
    const serialized_seeds = serializeSeeds(signers_seeds, &seeds_buf);

    // 3. 调用系统调用
    const result = syscalls.sol_invoke_signed_c(
        instruction_ptr,
        accounts_ptr,
        accounts_len,
        serialized_seeds.ptr,
        serialized_seeds.len
    );

    return if (result == 0) SUCCESS else error.CustomError;
}

/// 查找账户
fn findAccount(accounts: []AccountInfo, pubkey: *const Pubkey) ?*AccountInfo {
    for (accounts) |*account| {
        if (account.key.equals(pubkey.*)) {
            return account;
        }
    }
    return null;
}
```

**测试用例**：
```zig
// examples/transfer_lamports.zig
const pinocchio = @import("pinocchio");
const system = @import("system_program.zig");

fn process_instruction(
    program_id: *const pinocchio.Pubkey,
    accounts: []pinocchio.AccountInfo,
    instruction_data: []const u8
) pinocchio.ProgramResult {
    _ = program_id;
    _ = instruction_data;

    const from = &accounts[0];
    const to = &accounts[1];
    const amount: u64 = 1_000_000; // 0.001 SOL

    // 创建系统转账指令
    const transfer_ix = system.transfer(from.key, to.key, amount);

    // 执行 CPI
    try pinocchio.cpi.invoke(&transfer_ix, accounts);

    pinocchio.log.print("Transferred {} lamports", .{amount});
    return pinocchio.SUCCESS;
}
```

### 第三阶段：系统变量（第5-7天）

#### 4. 实现核心 Sysvars

**目标**：提供对系统变量的访问

```zig
// src/sysvars/clock.zig

const std = @import("std");
const syscalls = @import("../syscalls.zig");
const Pubkey = @import("../pubkey.zig").Pubkey;

pub const CLOCK_SYSVAR_ID = Pubkey.comptimeFromBase58(
    "SysvarC1ock11111111111111111111111111111111"
);

pub const Clock = extern struct {
    slot: u64,
    epoch_start_timestamp: i64,
    epoch: u64,
    leader_schedule_epoch: u64,
    unix_timestamp: i64,

    /// 获取当前时钟信息
    pub fn get() !Clock {
        var clock: Clock = undefined;
        const result = syscalls.sol_get_clock_sysvar(@ptrCast(&clock));
        if (result != 0) {
            return error.SysvarAccessFailed;
        }
        return clock;
    }

    /// 从账户数据读取
    pub fn from_account_info(account: *const AccountInfo) !Clock {
        if (!account.key.equals(CLOCK_SYSVAR_ID)) {
            return error.InvalidSysvar;
        }
        if (account.data_len != @sizeOf(Clock)) {
            return error.InvalidAccountData;
        }
        return @ptrCast(*const Clock, @alignCast(
            @alignOf(Clock),
            account.data.ptr
        )).*;
    }
};
```

```zig
// src/sysvars/rent.zig

pub const RENT_SYSVAR_ID = Pubkey.comptimeFromBase58(
    "SysvarRent111111111111111111111111111111111"
);

pub const Rent = extern struct {
    lamports_per_byte_year: u64,
    exemption_threshold: f64,
    burn_percent: u8,

    /// 获取租金信息
    pub fn get() !Rent {
        var rent: Rent = undefined;
        const result = syscalls.sol_get_rent_sysvar(@ptrCast(&rent));
        if (result != 0) {
            return error.SysvarAccessFailed;
        }
        return rent;
    }

    /// 计算最小免租金余额
    pub fn minimum_balance(self: Rent, data_len: usize) u64 {
        const years_exempt = self.exemption_threshold;
        const data_len_u64 = @as(u64, data_len);
        return @floatToInt(u64, @as(f64, self.lamports_per_byte_year) *
                                @as(f64, data_len_u64) * years_exempt);
    }
};
```

### 第四阶段：序列化支持（第8-10天）

#### 5. 实现 Borsh 序列化

```zig
// src/borsh.zig

const std = @import("std");

pub fn BorshSerialize(comptime T: type) type {
    return struct {
        pub fn serialize(self: T, writer: anytype) !void {
            const info = @typeInfo(T);
            switch (info) {
                .Struct => |s| {
                    inline for (s.fields) |field| {
                        try serialize(@field(self, field.name), writer);
                    }
                },
                .Int => try writer.writeInt(T, self, .little),
                .Bool => try writer.writeByte(if (self) 1 else 0),
                .Array => |a| {
                    if (a.child == u8) {
                        try writer.writeAll(&self);
                    } else {
                        for (self) |item| {
                            try serialize(item, writer);
                        }
                    }
                },
                else => @compileError("Unsupported type for Borsh"),
            }
        }
    };
}

pub fn BorshDeserialize(comptime T: type) type {
    return struct {
        pub fn deserialize(reader: anytype) !T {
            const info = @typeInfo(T);
            switch (info) {
                .Struct => |s| {
                    var result: T = undefined;
                    inline for (s.fields) |field| {
                        @field(result, field.name) = try deserialize(
                            field.type,
                            reader
                        );
                    }
                    return result;
                },
                .Int => return try reader.readInt(T, .little),
                .Bool => return (try reader.readByte()) != 0,
                else => @compileError("Unsupported type for Borsh"),
            }
        }
    };
}
```

### 第五阶段：系统程序接口（第11-12天）

#### 6. 实现系统程序助手

```zig
// src/programs/system.zig

const pinocchio = @import("../lib.zig");

pub const SYSTEM_PROGRAM_ID = pinocchio.Pubkey.comptimeFromBase58(
    "11111111111111111111111111111111"
);

pub const SystemInstruction = enum(u32) {
    CreateAccount = 0,
    Assign = 1,
    Transfer = 2,
    CreateAccountWithSeed = 3,
    AdvanceNonceAccount = 4,
    WithdrawNonceAccount = 5,
    InitializeNonceAccount = 6,
    AuthorizeNonceAccount = 7,
    Allocate = 8,
    AllocateWithSeed = 9,
    AssignWithSeed = 10,
    TransferWithSeed = 11,
    UpgradeNonceAccount = 12,
};

/// 创建转账指令
pub fn transfer(
    from: *const pinocchio.Pubkey,
    to: *const pinocchio.Pubkey,
    lamports: u64,
) pinocchio.Instruction {
    var data: [12]u8 = undefined;
    // 指令类型 (4 bytes)
    @memcpy(data[0..4], &@as(u32, @intFromEnum(SystemInstruction.Transfer)));
    // 金额 (8 bytes)
    @memcpy(data[4..12], &lamports);

    const accounts = &[_]pinocchio.AccountMeta{
        pinocchio.AccountMeta.writable(from.*, true),  // from (signer, writable)
        pinocchio.AccountMeta.writable(to.*, false),    // to (writable)
    };

    return pinocchio.Instruction.init(
        SYSTEM_PROGRAM_ID,
        accounts,
        &data,
    );
}

/// 创建账户指令
pub fn create_account(
    from: *const pinocchio.Pubkey,
    to: *const pinocchio.Pubkey,
    lamports: u64,
    space: u64,
    owner: *const pinocchio.Pubkey,
) pinocchio.Instruction {
    var data: [52]u8 = undefined;
    var offset: usize = 0;

    // 指令类型 (4 bytes)
    @memcpy(data[offset..offset+4], &@as(u32, 0));
    offset += 4;

    // lamports (8 bytes)
    @memcpy(data[offset..offset+8], &lamports);
    offset += 8;

    // space (8 bytes)
    @memcpy(data[offset..offset+8], &space);
    offset += 8;

    // owner (32 bytes)
    @memcpy(data[offset..offset+32], &owner.bytes);

    const accounts = &[_]pinocchio.AccountMeta{
        pinocchio.AccountMeta.writable(from.*, true),   // from (signer, writable)
        pinocchio.AccountMeta.writable(to.*, true),     // to (signer, writable)
    };

    return pinocchio.Instruction.init(
        SYSTEM_PROGRAM_ID,
        accounts,
        &data,
    );
}
```

## 📊 测试和验证

### 单元测试

每个模块都应包含单元测试：

```zig
// src/entrypoint.zig
test "parse account info" {
    const test_data = [_]u8{...};
    const account = parseAccount(&test_data);
    try std.testing.expect(account.is_signer == true);
}
```

### 集成测试

```zig
// tests/integration_test.zig
const std = @import("std");
const pinocchio = @import("pinocchio");

test "hello world program" {
    // 1. 编译程序
    const result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{"zig", "build", "-Doptimize=ReleaseFast"},
    });

    // 2. 部署到测试验证器
    // 3. 发送交易
    // 4. 验证结果
}
```

### CU 基准测试

```zig
// benchmarks/cu_benchmark.zig
test "measure hello world CU" {
    // 部署程序
    // 执行交易
    // 测量 CU 消耗
    // 目标: ≤16 CU
}

test "measure transfer CU" {
    // 部署程序
    // 执行转账
    // 测量 CU 消耗
    // 目标: ≤38 CU
}
```

## 📈 进度跟踪

| 阶段 | 模块 | 优先级 | 预计时间 | 状态 |
|------|------|--------|----------|------|
| 1 | entrypoint.zig | 🔴 高 | 1天 | ⏳ 待开始 |
| 1 | lazy_entrypoint.zig | 🟡 中 | 0.5天 | ⏳ 待开始 |
| 2 | cpi.zig | 🔴 高 | 1天 | ⏳ 待开始 |
| 3 | sysvars/clock.zig | 🔴 高 | 0.5天 | ⏳ 待开始 |
| 3 | sysvars/rent.zig | 🔴 高 | 0.5天 | ⏳ 待开始 |
| 3 | sysvars/system.zig | 🟡 中 | 0.5天 | ⏳ 待开始 |
| 4 | borsh.zig | 🟡 中 | 1天 | ⏳ 待开始 |
| 4 | pack.zig | 🟡 中 | 0.5天 | ⏳ 待开始 |
| 5 | programs/system.zig | 🔴 高 | 0.5天 | ⏳ 待开始 |
| 5 | programs/token.zig | 🟡 中 | 1天 | ⏳ 待开始 |

## 🎯 成功标准

### 短期目标（1周）
- ✅ 能够部署和运行 Hello World 程序
- ✅ 能够执行系统转账
- ✅ 能够读取时钟和租金 sysvar
- ✅ CU 消耗与 Rust 版本相当

### 中期目标（2周）
- ✅ 完整的 CPI 支持
- ✅ 所有核心 sysvar 实现
- ✅ Borsh 序列化支持
- ✅ 系统程序和 Token 程序接口

### 长期目标（1个月）
- ✅ 功能完整性与 solana-program 对等
- ✅ 性能优于或等于 Rust 实现
- ✅ 完善的文档和示例
- ✅ 社区采用和反馈

## 🛠️ 开发工具

### 构建命令
```bash
# 构建库
zig build

# 运行测试
zig build test

# 构建示例
zig build examples

# 部署到本地验证器
solana-test-validator &
solana program deploy zig-out/lib/program.so
```

### 调试技巧
```bash
# 查看程序日志
solana logs

# 检查 CU 消耗
solana program show <program-id>

# 反汇编 SBF 字节码
llvm-objdump -d zig-out/lib/program.so
```

## 📚 参考资源

- [Rust Pinocchio 源码](https://github.com/anza-xyz/pinocchio)
- [Solana Program Runtime](https://docs.solana.com/developing/programming-model/runtime)
- [SBF 指令集](https://github.com/solana-labs/rbpf)
- [Zig 语言文档](https://ziglang.org/documentation/master/)

## 🤝 贡献指南

1. 每个新功能创建独立分支
2. 遵循现有代码风格
3. 必须包含单元测试
4. 更新相关文档
5. 通过 CU 基准测试

---

**最后更新**: 2025-01-17
**维护者**: Pinocchio-Zig Team