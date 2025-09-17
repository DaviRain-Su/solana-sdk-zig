# Solana Program 依赖关系树

## 完整依赖树形图

```
solana-program
│
├── 【核心基础层 - 无内部依赖】
│   ├── solana-program-error
│   ├── solana-program-memory
│   │   └── solana-define-syscall (仅 target_os="solana")
│   ├── solana-msg
│   │   └── solana-define-syscall (仅 target_os="solana")
│   ├── solana-native-token
│   ├── solana-sdk-ids
│   ├── solana-stable-layout
│   ├── solana-program-option
│   ├── solana-serialize-utils
│   ├── solana-serde-varint
│   └── solana-short-vec
│
├── 【类型定义层】
│   ├── solana-pubkey
│   │   └── solana-address
│   │       ├── atomic
│   │       ├── decode
│   │       ├── error
│   │       ├── sanitize
│   │       ├── sha2
│   │       └── syscalls
│   │
│   ├── solana-hash
│   │   ├── solana-atomic-u64
│   │   ├── solana-sanitize
│   │   ├── five8 (base58编码)
│   │   └── solana-frozen-abi (可选)
│   │
│   └── solana-instruction-error
│       └── num-traits
│
├── 【指令和账户层】
│   ├── solana-instruction
│   │   ├── solana-instruction-error
│   │   ├── solana-pubkey
│   │   └── solana-define-syscall (仅 target_os="solana")
│   │
│   └── solana-account-info
│       ├── solana-program-error
│       ├── solana-program-memory
│       └── solana-pubkey
│
├── 【程序执行层】
│   ├── solana-program-entrypoint
│   │   ├── solana-account-info
│   │   │   ├── solana-program-error
│   │   │   ├── solana-program-memory
│   │   │   └── solana-pubkey
│   │   ├── solana-define-syscall
│   │   ├── solana-msg
│   │   ├── solana-program-error
│   │   └── solana-pubkey
│   │
│   └── solana-cpi
│       ├── solana-account-info
│       │   ├── solana-program-error
│       │   ├── solana-program-memory
│       │   └── solana-pubkey
│       ├── solana-instruction
│       │   ├── solana-instruction-error
│       │   └── solana-pubkey
│       ├── solana-program-error
│       ├── solana-pubkey
│       ├── solana-define-syscall (仅 target_os="solana")
│       └── solana-stable-layout (仅 target_os="solana")
│
├── 【系统变量层 (Sysvars)】
│   ├── solana-sysvar
│   │   ├── solana-pubkey
│   │   └── solana-sysvar-id
│   │
│   ├── solana-clock
│   │   ├── solana-sdk-ids
│   │   ├── solana-sdk-macro
│   │   └── solana-sysvar-id
│   │
│   ├── solana-rent
│   │   ├── solana-sdk-ids
│   │   ├── solana-sdk-macro
│   │   └── solana-sysvar-id
│   │
│   ├── solana-epoch-schedule
│   │   ├── solana-sdk-ids
│   │   ├── solana-sdk-macro
│   │   └── solana-sysvar-id
│   │
│   ├── solana-epoch-rewards
│   │   ├── solana-sdk-ids
│   │   ├── solana-sdk-macro
│   │   └── solana-sysvar-id
│   │
│   ├── solana-epoch-stake
│   │   └── solana-pubkey
│   │
│   ├── solana-last-restart-slot
│   │   ├── solana-sdk-ids
│   │   ├── solana-sdk-macro
│   │   └── solana-sysvar-id
│   │
│   ├── solana-slot-hashes
│   │   ├── solana-pubkey
│   │   ├── solana-hash
│   │   ├── solana-sdk-ids
│   │   └── solana-sysvar-id
│   │
│   ├── solana-slot-history
│   │   ├── solana-sdk-ids
│   │   └── solana-sysvar-id
│   │
│   └── solana-instructions-sysvar
│       ├── solana-instruction
│       ├── solana-pubkey
│       └── solana-sysvar-id
│
├── 【加密哈希层】
│   ├── solana-blake3-hasher
│   │   └── blake3 (外部库)
│   │
│   ├── solana-sha256-hasher
│   │   └── sha2 (外部库)
│   │
│   ├── solana-keccak-hasher
│   │   └── sha3 (外部库)
│   │
│   ├── solana-secp256k1-recover
│   │   └── libsecp256k1 (外部库)
│   │
│   └── solana-big-mod-exp
│
├── 【序列化工具层】
│   ├── solana-program-pack
│   │   ├── solana-program-error
│   │   └── solana-borsh (可选)
│   │
│   ├── solana-borsh (可选，默认启用)
│   │   └── borsh (外部库)
│   │
│   └── solana-fee-calculator (已弃用)
│       └── solana-native-token
│
└── 【平台特定】
    ├── solana-define-syscall (仅 target_os="solana")
    ├── solana-example-mocks (非 solana 平台)
    └── solana-system-interface (可选)
```

## 简化依赖层级视图

```
第0层（无依赖原语）
├── solana-program-error
├── solana-program-memory
├── solana-msg
├── solana-native-token
├── solana-sdk-ids
├── solana-stable-layout
├── solana-define-syscall
└── 工具类（serialize-utils, serde-varint, short-vec, program-option）

    ↓

第1层（基础类型）
├── solana-pubkey → [address]
├── solana-hash → [atomic-u64, sanitize]
└── solana-instruction-error → [num-traits]

    ↓

第2层（核心结构）
├── solana-instruction → [instruction-error, pubkey]
└── solana-account-info → [program-error, program-memory, pubkey]

    ↓

第3层（程序功能）
├── solana-cpi → [account-info, instruction, program-error, pubkey]
└── solana-program-entrypoint → [account-info, msg, program-error, pubkey]

    ↓

第4层（系统变量）
├── solana-sysvar → [pubkey, sysvar-id]
└── 各种具体sysvar → [sdk-ids, sysvar-id, sdk-macro]
```

## Zig 实现优先级

基于依赖关系，推荐的实现顺序：

### 阶段 1: 基础原语（无依赖）✅
```
1. program_error.zig     ✅ 已实现
2. log.zig (msg)         ✅ 已实现
3. syscalls.zig          ✅ 已实现
4. bpf.zig               ✅ 已实现
```

### 阶段 2: 基础类型 ✅
```
5. pubkey.zig            ✅ 已实现
6. instruction.zig       ✅ 已实现
```

### 阶段 3: 账户结构 ✅
```
7. account_info.zig      ✅ 已实现
```

### 阶段 4: 程序执行 ❌
```
8. entrypoint.zig        ❌ 待实现
9. cpi.zig              ❌ 待实现
```

### 阶段 5: 系统变量 ❌
```
10. sysvars/            ❌ 待实现
    ├── clock.zig
    ├── rent.zig
    └── ...
```

### 阶段 6: 序列化（可选）❌
```
11. borsh.zig           ❌ 待实现
12. pack.zig            ❌ 待实现
```

## 最小可运行程序所需模块

```
必需模块依赖树：
program (你的程序)
    │
    ├── entrypoint
    │   ├── account_info
    │   │   ├── program_error
    │   │   ├── program_memory → syscalls
    │   │   └── pubkey
    │   ├── msg → syscalls
    │   └── program_error
    │
    └── instruction
        ├── pubkey
        └── instruction_error

最小集合（8个模块）：
- syscalls.zig
- program_error.zig
- program_memory.zig
- msg.zig
- pubkey.zig
- instruction_error.zig
- instruction.zig
- account_info.zig
- entrypoint.zig
```

## 外部依赖

```
外部库依赖：
├── 基础库
│   ├── memoffset (内存偏移计算)
│   ├── num-traits (数字trait)
│   └── five8 (base58编码)
│
├── 序列化
│   ├── borsh
│   ├── bincode
│   └── serde
│
└── 加密
    ├── blake3
    ├── sha2
    ├── sha3
    └── libsecp256k1
```