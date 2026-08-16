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
| `--rtthread` | RT-Thread 模式（自动启用 newlib-nano 链接，编译 `bsp/rtthread*` 与 `third_party/` 内核） |
| `--rtthread-version 51` | RT-Thread 内核版本：默认 `315`（lts-v3.1.x）/ `51`（v5.1.0） |
| `--irq-mode unified` | RT-Thread 中断模式：默认 `ch32`（轻量入口 + 软件中断延迟切换）/ `unified`（统一入口，全量保存 + 直接切换） |

编译流程：AS start.S → CC board/init.c → CC drivers → CC trap → CC main.c → LD → OBJDUMP → 生成 .mem/.uartbin

## build_run.py — 一键构建 + 上板运行

一条命令完成 **构建 → 复位 FPGA → UART 下载 → 监听运行输出**（板子需已连接，SDK/ 目录下执行）：

```bash
cd SDK

# 构建 hello（newlib-nano）→ 复位 → 下载 → 监听，输出空闲 3 秒即停
python tools/build_run.py demos/newlib/hello --newlib

# RT-Thread（默认 lts-v3.1.x；--irq-mode unified 切统一入口）
python tools/build_run.py demos/rtthread --rtthread --idle-timeout 5
python tools/build_run.py demos/rtthread --rtthread --irq-mode unified

# 只下载不监听 / 下载前不复位
python tools/build_run.py demos/nolibc/breathing --no-listen
python tools/build_run.py demos/nolibc/breathing --no-reset
```

构建参数（`--newlib` / `--clang` / `--rtthread` / `--rtthread-version` / `--irq-mode` / `--opt` / `--debug` / `--extra`）透传 build.py，运行参数（`--port` / `--baud` / `--idle-timeout`（默认 3s） / `--timeout` / `--until` / `--log` / `--no-reset` / `--no-listen`）透传 uart_send.py。产物命名与 build.py 一致（默认 Os → `<demo>_os.uartbin`；`--opt O2` → `<demo>_o2.uartbin`；`--clang` → `<demo>_clang_<opt>.uartbin`）。

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

## RT-Thread 应用开发

BD32 内置 RT-Thread 双版本移植（lts-v3.1.x / v5.1.0），两种中断模式可选：CLINT mtime 系统节拍（1ms）、UART 控制台。验证流程（仿真/上板矩阵）见 [验证手册](verification.md)。

### 版本与目录

| 内核版本 | 内核源码（`third_party/`） | BSP（`SDK/bsp/`） | demo（`SDK/demos/`） |
|---|---|---|---|
| lts-v3.1.x（v3.1.5，默认） | `rt-thread-3.1.5` | `rtthread` | `rtthread` |
| v5.1.0 | `rt-thread-5.1.0` | `rtthread51` | `rtthread51` |

### 中断模式（`--irq-mode`）

RISC-V 机器模式中断编码（`mcause[11:0]`）中本移植用到三种：

- **3 号 = 机器软件中断（MSI）**：由 CLINT `msip` 触发，RT-Thread 用它请求"延迟切换"（PendSV 角色）；
- **7 号 = 机器定时器中断（MTI）**：由 CLINT `mtime ≥ mtimecmp` 触发，驱动 1ms 系统 tick；
- **11 号 = 机器外部中断（MEI）**：由 PLIC 转发外设中断（UART / GPIO / Timer 等）。

| 模式 | 工作方式 | 优点 | 缺点 | 适用场景 |
|---|---|---|---|---|
| `ch32`（默认） | 7/11 号走轻量入口，只保存 17 个 caller 寄存器；需要切换时写 `CLINT_MSIP` 触发 3 号软件中断，由 SW_handler 全量保存并延迟切换 | 常态中断只存 caller 寄存器，中断开销小、响应快 | 依赖软件中断与 `mscratch`；需要切换时多一次软件中断（两次 trap 路径） | 中断频繁、对中断延迟敏感（默认推荐） |
| `unified` | 3/7/11 全部走统一入口，全量保存 30 个寄存器，中断返回时检查切换 flag 直接切换 | 实现简单、代码量小；无软件中断依赖、不依赖 `mscratch`；切换单次 trap 完成 | 每次中断（含不需要切换的）都全量保存/恢复，常态中断开销大 | 中断不频繁、精简优先，或不想依赖软件中断/`mscratch` |

### 构建 / 仿真 / 上板

```bash
# 构建（默认 lts-v3.1.x + ch32 中断模式；--irq-mode unified 切换统一入口）
cd SDK
python tools/build.py demos/rtthread --rtthread
python tools/build.py demos/rtthread --rtthread --irq-mode unified
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51 --irq-mode unified

# 仿真（80ms 窗口，输出 t1/t2 交替即通过；产物名不区分中断模式）
cd ../script/soc_test
vsim -batch -do "do rtthread_sim.do"      # 默认 lts-v3.1.x，加载 rtthread_os_*.mem
vsim -batch -do "do rtthread_sim51.do"    # v5.1.0，加载 rtthread51_os_*.mem

# 上板（COM8 举例；先构建再下载）
cd ../../..
python SDK/tools/uart_send.py test_data/soc/c/rtthread_os.uartbin --port COM8 --reset --idle-timeout 5
python SDK/tools/uart_send.py test_data/soc/c/rtthread51_os.uartbin --port COM8 --reset --idle-timeout 5
```

串口输出 RT-Thread banner 后 t1/t2 持续交替打印即验证通过。

### 编写 RT-Thread 程序

一个 RT-Thread demo 就是一个带 `src/main.c` 的目录（如 `SDK/demos/<name>/src/main.c`），构建命令：`python tools/build.py demos/<name> --rtthread`（默认 lts-v3.1.x；加 `--rtthread-version 51` 用 v5.1.0）。

线程编写模板（每个线程独立配置栈大小 / 优先级 / 时间片）：

```c
#include <rtthread.h>

/* 线程参数：每个线程独立配置（栈大小、优先级、时间片可各不相同） */
#define T1_STACK_SIZE   4096
#define T1_PRIORITY     5
#define T1_TIMESLICE    20
#define T2_STACK_SIZE   2048
#define T2_PRIORITY     6
#define T2_TIMESLICE    10

static struct rt_thread t1, t2;
static rt_uint8_t t1_stack[T1_STACK_SIZE];
static rt_uint8_t t2_stack[T2_STACK_SIZE];

static void t1_entry(void *param)
{
    while (1) {
        rt_kprintf("t1\n");
        rt_thread_mdelay(100);          /* 主动让出 CPU，100ms 后恢复 */
    }
}

static void t2_entry(void *param)
{
    while (1) {
        rt_kprintf("t2\n");
        rt_thread_mdelay(100);
    }
}

int main(void)                          /* main 线程（RT_USING_USER_MAIN 自动创建） */
{
    rt_thread_init(&t1, "t1", t1_entry, RT_NULL,
                   t1_stack, sizeof(t1_stack), T1_PRIORITY, T1_TIMESLICE);
    rt_thread_init(&t2, "t2", t2_entry, RT_NULL,
                   t2_stack, sizeof(t2_stack), T2_PRIORITY, T2_TIMESLICE);
    rt_thread_startup(&t1);
    rt_thread_startup(&t2);
    return 0;
}
```

> RT-Thread 优先级数值越小优先级越高；只有**同优先级**线程之间才会发生时间片轮转，不同优先级是抢占调度（高优先级就绪即运行）。

要点：

- 入口 `main()` 由内核自动创建为 main 线程；业务线程用 `rt_thread_init`（静态栈）或 `rt_thread_create`（动态，从 8KB 系统堆分配）。
- 打印用 `rt_kprintf`（经 UART 控制台）；`rt_thread_mdelay` 让出 CPU。RT 模式已链接 newlib-nano，`printf`/`malloc` 也可用，但推荐统一走内核的 `rt_kprintf`/`rt_malloc`。
- 已开启的机制：信号量 / 互斥 / 事件 / 邮箱（见各版本 `rtconfig.h`）、系统堆 8KB、tick=1ms、优先级 0~7。
- 中断服务函数中不要调用会阻塞或触发调度的 API；时间片调度由 7 号定时器中断（+ 3 号软件中断，仅 ch32 模式）自动完成，用户无需干预。
- 内核源码（`third_party/`）只读，不做修改；板级适配在 `SDK/bsp/rtthread*`，移植细节见各文件注释（系统节拍、堆、栈、`RT_USING_SMALL_MEM_AS_HEAP` 等版本差异）。

> lts-v3.1.x 源码说明：官方 v3.1.5 tag 的 `include/libc/libc_signal.h` 无条件 `#include <signal.h>`，与新版 newlib 的 `sigevent`/`siginfo_t` 定义冲突；需按 lts-v3.1.x 分支改为 `#ifdef RT_USING_NEWLIB / #include <sys/signal.h> / #endif`（本次构建已应用）。
