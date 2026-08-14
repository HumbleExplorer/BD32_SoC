# SDK 构建工具与协议

> 本页内容自 README 迁移整理，覆盖 build.py、riscv-tests 构建、LLVM 集成、MROM 构建与 uartbin 下载协议。


## build.py — 主构建脚本

路径：`SDK/tools/build.py`

| 参数 | 说明 |
|------|------|
| `source` | demo 目录或 .c 文件路径 |
| `--newlib` | 链接 newlib-nano（支持 printf/malloc） |
| `--no-bin` | 跳过 .mem/.uartbin 生成 |
| `--opt O2` | 优化等级（默认 Os） |
| `--clang` | 用 Clang 做前端代码生成（链接仍走 GCC） |
| `--debug` | 启用 `-g` 调试信息（GDB 源码级单步/查看变量，需 GDB 在线调试） |
| `--extra "-DFLAG"` | 追加编译标志 |

编译流程：AS start.S → CC board/init.c → CC drivers → CC trap → CC main.c → LD → OBJDUMP → 生成 .mem/.uartbin

## build_riscv_tests.py — riscv-tests 编译

riscv-tests 源码不随本仓库分发，需先获取到 `third_party/riscv-tests`（官方仓库 [riscv/riscv-tests](https://github.com/riscv/riscv-tests)，BSD-3-Clause）：

```bash
git clone https://github.com/riscv/riscv-tests.git third_party/riscv-tests
```

构建以 `SDK/isa` 为工作目录，`third_party/riscv-tests` 只作为第三方源码来源（路径可用环境变量 `RISCV_TESTS_SRC` 覆盖）：

- `SDK/isa/env/`（`link.ld`、`riscv_test.h`、`encoding.h`）是仓库内维护的 BD32 测试环境，随仓库提交；
- `SDK/isa/rv32ui`、`rv32um`、`rv64ui`、`macros` 是可再生成的官方源码与宏（不入库），缺失时脚本自动从 `third_party/riscv-tests/isa/` 复制补齐；`build_asm.py`（custom_asm）首次运行也会做同样处理。

其中 `riscv_test.h` 基于官方版本精简：去掉 PMP/SATP/陷阱向量等特权初始化，pass/fail 上报改为 x26/x27 以匹配 tb_core_top 判定；CSR/异常编码使用官方 `env/encoding.h`。

```bash
cd SDK
python tools/build_riscv_tests.py          # GCC
python tools/build_riscv_tests.py --clang  # Clang 汇编
```

产物输出到 `test_data/riscv-tests/`：`<test>.elf`、`<test>.dump`、`<test>.dat`（readmemh 字流）。

## LLVM/Clang 集成

通过 `--clang` 开关启用。设计原则：Clang 只负责 `.c`/`.S` 的代码生成，链接始终由 xPack GCC 完成（因为官方 LLVM Windows 包不含 RISC-V compiler-rt builtins）。

## MROM 构建

```bash
bash test_data/soc/build_mrom.sh
```

MROM（0x00000000，4KB）负责：设置 mcounteren → 测量 CPU 主频 → 计算 UART NCO 系数 → 跳转 ITCM 执行用户程序。

## uartbin 下载协议

由 `build.py` 生成（ELF `.text` → ITCM 段，`.data + .rodata` → DTCM 段），经串口由 BootROM 下载模式接收（MROM 读 GPIO[0]=1 后置 `DBG_EN=1`），写入 ITCM/DTCM 后跳转运行。

帧结构（无地址字段、无结束帧，纯计数协议，避免数据内容与帧标记冲突）：

| 字段 | 字节数 | 说明 |
|------|------|------|
| START_FRAME | 4 | 帧头 `0xBBAABBAA`（小端字节序发送：AA BB AA BB） |
| ITCM_COUNT | 4 | uint32 LE，ITCM 数据字数 |
| ITCM_DATA | ITCM_COUNT×4 | 依次写入 ITCM，起始地址 `0x0001_0000`，每字地址 +4 |
| DTCM_COUNT | 4 | uint32 LE，DTCM 数据字数（=0 表示无 DTCM 段） |
| DTCM_DATA | DTCM_COUNT×4 | 依次写入 DTCM，起始地址 `0x0002_0000`，每字地址 +4 |

要点：
- 所有 32 位字段均为**小端字节序**（LSB 先发），接收端按 `{new_byte, old[31:8]}` 左移拼装，第 4 字节到达时完成帧头检测。
- `DTCM_COUNT == 0` 时跳过 DTCM 段，直接进入运行。
- 下载完成后 UART `DBG_STAT[0]`（0x20）置 1，MROM 轮询到后点亮 LED 并跳转 ITCM（0x10000）运行。
- 下载仅在上电处于下载模式时生效（GPIO[0]=1）；正常模式（GPIO[0]=0）跳过下载直接运行 ITCM。

生成示例（build.py）：`struct.pack('<I', 0xBBAABBAA)` 为帧头；ITCM 数据取自 ELF `.text`，DTCM 数据取自 `.data` + `.rodata`。
