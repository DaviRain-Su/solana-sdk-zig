# Rust vs Zig Pubkey 实现对比

## Rust 版本 (Address) 的主要功能

1. **基础功能**
   - `new_from_array([u8; 32])` - 从数组创建
   - `from_str()` - 从 base58 字符串解析
   - `to_bytes()` - 转换为字节数组
   - `as_array()` - 获取字节数组引用

2. **PDA 相关**
   - `create_program_address()` - 创建程序派生地址
   - `find_program_address()` - 查找程序地址和 bump
   - `try_find_program_address()` - 尝试查找（返回 Option）
   - `create_with_seed()` - 使用种子创建地址

3. **特性**
   - 优化的 `PartialEq` 实现（4个 u64 比较）
   - base58 编码/解码
   - Display/Debug trait
   - Hash trait
   - 系统程序 ID 常量

4. **工具函数**
   - `new_unique()` - 创建唯一地址（测试用）
   - `is_on_curve()` - 检查是否在 ed25519 曲线上
   - `log()` - 日志输出

## Zig 版本当前实现

1. **已实现**
   - `fromBytes([32]u8)` ✅
   - `fromString([]const u8)` ✅
   - `toString()` ✅
   - `equals()` ✅
   - `createProgramAddress()` ✅
   - `findProgramAddress()` ✅
   - 基本常量（ZEROES, SIZE）✅

2. **缺失或需要完善**
   - `create_with_seed()` ❌
   - 优化的 equals 实现（当前未使用 u64 比较）
   - `new_unique()` 测试函数
   - `as_array()` / `to_bytes()` 访问器
   - 更多系统程序 ID 常量
   - Display/格式化支持

## 需要添加的功能

### 优先级高
1. 优化 equals 实现为 4x u64 比较
2. 添加 `toBytes()` 和 `asArray()` 方法
3. 添加 `createWithSeed()` 实现
4. 添加更多常用系统程序 ID

### 优先级中
5. 添加 `newUnique()` 测试辅助函数
6. 完善格式化输出支持
7. 添加更多测试用例