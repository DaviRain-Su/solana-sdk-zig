# Solana 账户内存布局参考手册

## 输入缓冲区完整布局

### 总体结构
```
┌─────────────────────────┐
│  账户数量 (8 bytes)      │
├─────────────────────────┤
│  账户 #1                │
├─────────────────────────┤
│  账户 #2                │
├─────────────────────────┤
│  ...                    │
├─────────────────────────┤
│  账户 #N                │
├─────────────────────────┤
│  指令数据长度 (8 bytes)  │
├─────────────────────────┤
│  指令数据 (变长)         │
├─────────────────────────┤
│  程序 ID (32 bytes)     │
└─────────────────────────┘
```

### 账户数据详细布局

#### 非重复账户
```
偏移量   大小        字段名              说明
------  ---------  ----------------  ----------------------------------
0x00    1 byte     dup_marker        0xFF 表示非重复账户
0x01    1 byte     is_signer         是否为签名者 (0 或 1)
0x02    1 byte     is_writable       是否可写 (0 或 1)
0x03    1 byte     is_executable     是否可执行 (0 或 1)
0x04    4 bytes    original_data_len 原始数据长度（填充）
0x08    32 bytes   key               账户公钥
0x28    32 bytes   owner             所有者公钥
0x48    8 bytes    lamports          账户余额
0x50    8 bytes    data_len          数据长度
0x58    N bytes    data              账户数据
0x58+N  10240 bytes padding          MAX_PERMITTED_DATA_INCREASE
        8 bytes    rent_epoch        租金周期
        0-7 bytes  alignment         对齐到8字节边界
```

#### 重复账户
```
偏移量   大小        字段名              说明
------  ---------  ----------------  ----------------------------------
0x00    1 byte     dup_index         引用的账户索引 (0-253)
0x01    7 bytes    padding           填充（必须是7字节，不是8字节）
```

## Zig 数据结构映射

### AccountData 结构
```zig
pub const AccountData = extern struct {
    duplicate_index: u8,      // 0x00
    is_signer: u8,           // 0x01
    is_writable: u8,         // 0x02
    is_executable: u8,       // 0x03
    original_data_len: u32,  // 0x04
    id: Pubkey,              // 0x08 (32 bytes)
    owner_id: Pubkey,        // 0x28 (32 bytes)
    lamports: u64,           // 0x48
    data_len: u64,           // 0x50
    // 总大小：88 bytes (0x58)
};
```

### 关键常量
```zig
// 最大账户数量（受栈大小限制）
pub const MAX_ACCOUNTS = 16;

// 账户数据最大增长量
pub const MAX_PERMITTED_DATA_INCREASE = 10_240; // 10KB

// BPF 对齐要求
pub const BPF_ALIGN_OF_U128 = 8;

// 非重复账户标记
pub const NON_DUP_MARKER = 0xFF;

// Solana 栈大小限制
pub const STACK_SIZE = 4096; // 4KB
```

## 解析算法伪代码

```zig
fn parseAccounts(input: [*]const u8) {
    offset = 0

    // 1. 读取账户数量
    num_accounts = readU64(input[offset..])
    offset += 8

    // 2. 解析每个账户
    for i in 0..num_accounts {
        dup_marker = input[offset]
        offset += 1

        if (dup_marker != 0xFF) {
            // 重复账户
            accounts[i] = accounts[dup_marker]
            offset += 7  // 注意：7字节，不是8字节
        } else {
            // 非重复账户
            is_signer = input[offset]
            offset += 1
            is_writable = input[offset]
            offset += 1
            is_executable = input[offset]
            offset += 1

            offset += 4  // 跳过 original_data_len

            key = input[offset..offset+32]
            offset += 32

            owner = input[offset..offset+32]
            offset += 32

            lamports = readU64(input[offset..])
            offset += 8

            data_len = readU64(input[offset..])
            offset += 8

            data_ptr = input + offset
            offset += data_len

            // 关键：必须跳过10KB填充
            offset += MAX_PERMITTED_DATA_INCREASE

            // 跳过 rent_epoch
            offset += 8

            // 对齐到8字节
            alignment = offset & 7
            if (alignment != 0) {
                offset += 8 - alignment
            }
        }
    }

    // 3. 读取指令数据
    instruction_len = readU64(input[offset..])
    offset += 8

    instruction_data = input[offset..offset+instruction_len]
    offset += instruction_len

    // 4. 读取程序ID
    program_id = input[offset..offset+32]
}
```

## 常见错误对照表

| 错误现象 | 可能原因 | 解决方法 |
|---------|---------|---------|
| Owner 字段错误 | 未跳过10KB填充 | 添加 `offset += ACCOUNT_DATA_PADDING` |
| 账户数据垃圾值 | 栈内存生命周期问题 | 在 entrypoint 函数分配缓冲区 |
| 对齐错误 | 直接指针转换 | 使用 `*align(1)` 或 `readInt` |
| 第二个账户解析失败 | 重复账户填充错误 | 使用7字节而非8字节填充 |
| Stack overflow | 缓冲区太大 | 减少 MAX_ACCOUNTS |
| Program ID 错误 | 偏移量计算累积错误 | 验证每步的偏移量 |

## 内存安全检查清单

### 解析前
- [ ] 缓冲区在正确的作用域分配
- [ ] 缓冲区大小符合栈限制
- [ ] 所有指针初始化为 undefined

### 解析中
- [ ] 每次读取前检查边界
- [ ] 使用安全的未对齐读取函数
- [ ] 正确处理重复账户引用

### 解析后
- [ ] 返回的 slice 指向有效内存
- [ ] 账户数量在 MAX_ACCOUNTS 内
- [ ] 所有必需字段都已填充

## 调试命令参考

```bash
# 编译 Solana 程序
/path/to/solana-zig/zig build

# 部署程序
solana program deploy zig-out/lib/program.so

# 运行测试
node test.js

# 查看程序日志
solana logs | grep "Program log"

# 检查账户信息
solana account <PUBKEY>

# 查看交易详情
solana confirm -v <SIGNATURE>
```

## Rust 与 Zig 对比

| Rust | Zig | 说明 |
|------|-----|------|
| `Vec<AccountInfo>` | `[]AccountInfo` | Zig 需要预分配 |
| `#[repr(C)]` | `extern struct` | 内存布局兼容 |
| `unsafe { *(ptr as *const T) }` | `@ptrCast(*const T, ptr)` | 指针转换 |
| 自动内存管理 | 手动生命周期 | Zig 无 GC |
| `u8::MAX` | `0xFF` | 常量值 |

## 参考链接

- [Solana Account Model](https://docs.solana.com/developing/programming-model/accounts)
- [Program Runtime](https://docs.solana.com/developing/on-chain-programs/overview)
- [Zig Alignment](https://ziglang.org/documentation/master/#Alignment)
- [BPF Memory Model](https://github.com/solana-labs/rbpf/blob/main/docs/memory.md)