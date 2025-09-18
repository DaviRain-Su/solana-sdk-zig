# Solana SDK Zig Examples

这个目录包含了 Solana SDK Zig 的示例程序。

## 示例程序列表

1. **msg_example.zig** - 演示 msg 模块的各种日志功能

## 如何运行示例程序

### 方法 1: 作为普通 Zig 程序运行（用于测试和调试）

```bash
# 进入 examples 目录
cd examples

# 运行 msg 示例
../solana-zig/zig build run-msg

# 运行所有示例
../solana-zig/zig build run

# 运行测试
../solana-zig/zig build test
```

### 方法 2: 编译为 Solana 程序（BPF/SBF）

要将示例编译为可以在 Solana 上部署的程序，需要创建一个 Solana 程序项目：

```bash
# 创建新的 Solana 程序项目
mkdir my-solana-program
cd my-solana-program

# 创建 build.zig
cat > build.zig << 'EOF'
const std = @import("std");
const pinocchio = @import("pinocchio");

pub fn build(b: *std.Build) void {
    // 使用 Solana BPF 目标
    const target = b.resolveTargetQuery(pinocchio.sbf_target);
    const optimize = .ReleaseFast;

    // 创建 Solana 程序
    const program = b.addSharedLibrary(.{
        .name = "my_program",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 链接 Solana 程序
    _ = pinocchio.buildProgram(b, program, target, optimize);

    b.installArtifact(program);
}
EOF

# 创建源文件
mkdir src
cat > src/main.zig << 'EOF'
const pinocchio = @import("pinocchio");
const msg = pinocchio.msg;

pub export fn entrypoint(input: [*]u8) u64 {
    msg.msg("Hello from Solana program!");

    // 解析账户和指令数据
    // ... 程序逻辑 ...

    return 0; // SUCCESS
}
EOF

# 编译程序
../solana-zig/zig build -Dtarget=bpfel-freestanding -Doptimize=ReleaseFast
```

### 方法 3: 直接运行示例测试

从 SDK 根目录运行：

```bash
# 运行 msg_example 的测试
./solana-zig/zig test examples/msg_example.zig

# 运行为可执行文件
./solana-zig/zig run examples/msg_example.zig
```

## 示例程序说明

### msg_example.zig

展示了 msg 模块的所有功能：

- 基本日志: `msg()`, `msgf()`
- 数值日志: `msg64()`
- 公钥日志: `msgPubkey()`
- 计算单元日志: `msgComputeUnits()`
- 数据日志: `msgData()`, `msgHex()`
- 错误处理: `msgPanic()`, `msgAssert()`, `msgError()`
- 结构化日志: `msgDebug()`, `msgInfo()`, `msgWarn()`, `msgErr()`
- 性能监控: `measureComputeUnits()`

## 部署到 Solana

编译后的程序可以部署到 Solana：

```bash
# 启动本地测试验证器
solana-test-validator

# 部署程序
solana program deploy zig-out/lib/my_program.so

# 调用程序
solana program invoke <PROGRAM_ID>
```

## 注意事项

1. **目标架构**: Solana 程序必须编译为 BPF/SBF 目标（bpfel 或 sbf）
2. **入口点**: Solana 程序必须导出 `entrypoint` 函数
3. **返回值**: 成功返回 0，错误返回非零错误码
4. **日志**: 在 Solana 环境中，日志通过 `sol_log_` 系统调用输出；在本地测试时，输出到 stderr
5. **内存限制**: Solana 程序有严格的栈和堆限制，避免大量分配

## 更多示例

更多示例程序即将添加，包括：
- 转账示例
- PDA（程序派生地址）示例
- CPI（跨程序调用）示例
- SPL Token 操作示例