# 调试模块（Debug Module）

> 本页内容自 README 迁移整理，覆盖调试架构、DMI/CSR 位域、Trigger、OpenOCD/GDB 使用手册与仿真/上板验证。


BD32 实现了 RISC-V Debug Specification 1.0 子集（`dmstatus.version=3`，dcsr 按 1.0 位域读回；OpenOCD 0.12 同时接受 version 2/3），支持通过 JTAG 接口进行在线调试，并经 GDB 完成真实程序符号级调试验证。调试子系统位于 `rtl/Debug/`，由 `bd32_board_top` 在 `BD32_DEBUG_EN` 宏开启时例化。

调试采用 **halt-in-place + 直接端口访问** 架构（与 tinyriscv/Ibex 同类，区别于 E203/CVA6 的 Debug ROM + Park Loop）：
- halt 后流水线全级 stall + flush，CPU 原地冻结；无需 Debug ROM、不执行任何调试代码
- GPR/CSR 通过专用调试端口直连（RegFile / CSR_Reg_Access），不经 CPU 执行；CPU 运行中也可访问（规范允许的可选超集，OpenOCD 正常流程在 halt 后访问）
- 内存访问走 SBA（32-bit 读；8/16/32-bit 写），在 halt 期间读写 ITCM/DTCM 以及外设总线（APB：UART/GPIO/CLINT/PLIC/Timer 等）
- Debug Module 自身不映射到系统地址空间（非内存映射外设），调试器经 JTAG DMI 访问；SBA 按地址在核内分发：BootROM/ITCM/DTCM 直连，总线区（APB 外设等）与 CPU 访存共用同一条 AXI 主机通路（AXI 互联层仅一个主机）

## 架构

```
PC (OpenOCD/GDB)
    │  USB
    ▼
FT2232H Channel A (JTAG: TCK/TDI/TDO/TMS)
    │
    ▼
┌─────────────────────────────────────────────────┐
│  debug_top                                      │
│  ┌───────────┐    ┌──────────┐   ┌───────────┐  │
│  │ jtag_tap  │──▶│ debug_dm │──▶│ debug_cdc │──│──▶ CPU (halt/resume/step)
│  │ (TAP+DTM) │◀──│ (DM)     │◀──│ (TCK↔CLK) │◀─│── CPU (dbg_halted)
│  └───────────┘    └──────────┘   └───────────┘  │
└─────────────────────────────────────────────────┘
```

- **jtag_tap**：IEEE 1149.1 TAP 状态机 + DTM（Debug Transport Module），IDCODE = 0x1BD32003，IR 编码：IDCODE=0x01, DTMCS=0x10, DMI=0x11
- **debug_dm**：Debug Module 核心，实现 abstract command（GPR/CSR 读写）、SBA（System Bus Access）、halt/resume/step 控制、Trigger Module（mcontrol type=2）
- **debug_cdc**：JTAG TCK 域与 CPU CLK 域之间的跨时钟域同步（握手协议）

## 支持的调试功能

| 功能 | 状态 | 说明 |
|------|------|------|
| halt / resume | 已验证 | `dmcontrol.haltreq` / `resumereq` |
| 单步（stepi） | 已验证 | `dcsr.step=1`，门控分支预测保证 PC+4 |
| reset halt | 已验证 | `ndmreset` + haltreq 驻留，停在复位向量 |
| GPR / CSR 读写 | 已验证 | abstract command，regno 0x1000~0x101F / 0xC000\|csr 与 1.0 直接编码 |
| dcsr / dpc | 已验证 | dcsr 按 1.0 位域读回（debugver/cause/step/ebreakm） |
| SBA | 已验证 | 32-bit 地址，8/16/32-bit 写 + 32-bit 读，读写 ITCM/DTCM + 外设总线（APB） |
| 硬件断点 | 已验证 | 4 路 tdata1/tdata2（tselect 选择），mcontrol type=2 地址匹配，OpenOCD `hbreak` + GDB |
| 数据观察点 | 已验证 | load/store 地址匹配（tdata1 bit0/bit1）+ sizelo 宽度过滤（8/16/32-bit），命中 halt（dpc=访存指令、不提交），GDB `watch` |
| ebreak 进调试 | 已验证 | `dcsr.ebreakm=1` 时 ebreak 触发 halt，cause=1，dpc=ebreak 地址 |
| GDB 在线调试 | 已验证 | 真实 demo（breathing）符号级调试：加载/断点/单步/变量 |

未实现：Debug ROM / Park Loop、ProgBuf（progbufsize=0）、abstract 内存访问（cmdtype=2）、多 hart。

## 未实现能力说明（调试扩展点）

以下 Debug Spec 能力未实现。当前调试操作全部由 DM 硬件直连完成（GPR/CSR 直读、SBA 访存），无需 CPU 执行任何调试代码；列于此便于后续完善时对照。

| 能力 | 概念 | 当前影响 / 补充时机 |
|------|------|------|
| ProgBuf | DM 内小块 RAM（典型 1~16 字），调试器写入任意 RISC-V 指令，CPU 在 debug mode 下取指执行 | 无“任意代码注入”通道；flash 在线编程、复杂寄存器序列等需 CPU 执行的操作受限 |
| 抽象内存访问（cmdtype=2） | 调试器发抽象命令，由 CPU 自身执行一次 load/store，走 CPU 视角（PMP、地址翻译、CPU 私有存储） | SBA 仅总线视角；启用 PMP 或 CPU 私有存储后需补充 |
| 多 hart | 多核调试（dmcontrol.hasel / hart 选择） | 当前单 hart，不涉及 |

**Trigger 高级特性**（当前仅 4 路 mcontrol type=2 地址匹配）：

- priv 过滤（mcontrol6）：指定只在某特权级触发，避免 ISR 中同地址误命中；当前纯 M-mode 不受影响，增加 U/S-mode 后需要
- match 模式扩展：NAPOT 地址范围 / 大于小于 / 掩码匹配，一路 trigger 可覆盖一段地址区间
- chain：两路 trigger 条件“与”（如地址 + 数据值同时匹配）
- timing / hit 计数：第 N 次命中才触发（循环计数场景）
- action=0 异常断点：trigger 命中产生 breakpoint 异常（不进 debug mode），供软件无外部调试器时自用断点（当前仅支持 action=1 进 debug mode）
- icount（type=3）：执行 N 条指令后触发
- itrigger（type=4）/ etrigger（type=5）：中断 / 外部信号触发
- textra32（tdata3）：scontext/mcontext 等上下文过滤，未实现（读写返回 0）

**dcsr 控制位**（当前读回固定为 0）：

- `stepie`（单步时中断使能）：为 0 时单步不响应中断；为 1 时可单步进入中断处理流程
- `stopcount`：debug mode 下 mcycle / instret / 性能计数器停止，避免调试暂停计入性能测量
- `stoptime`：debug mode 下时间类计数器（mtime 等）停止

## Trigger Module（硬件断点）

DM 内部实现 4 路 trigger 寄存器组（tselect + 4×tdata1/tdata2），通过 abstract command 的 CSR 地址空间（0x7A0~0x7A3）访问：

- `tdata1` 复位值 = 0x2000_0000（type=2 mcontrol, dmode=0, 默认 disabled；dmode=0 避免 OpenOCD 0.12 枚举时清零导致 hbreak 失败）
- OpenOCD 通过 `hbreak *<addr>` 命令编程 tdata2 = 目标地址，置 tdata1[2]（execute match enable）；tselect 越界写自动钳位，用于枚举 trigger 数量（4 路）
- CPU 侧多路并行比较 `trigger_hit = |(trigger_en[i] & (inst_addr_if == trigger_addr[i]))`，命中后触发 halt
- **action 语义**：仅实现 action=1（命中进 debug mode，即 halt）；action=0（异常断点）未实现。tdata1 中未实现字段（chain/match/timing/hit/select 等）写入后原样读回，但不参与硬件匹配逻辑
- **halt 保持锁存**：CPU 一旦进入 debug mode，DM 锁存 `halt_hold_r` 保持暂停，直到调试器发 `resumereq`（Debug Spec 4.7/4.8）。因此 `haltreq` 写 0（WARZ 清除请求）、删除断点（清 tdata1）或清 `dcsr.ebreakm` 都不会让 CPU 自动恢复运行
- **ebreak 进调试**：`dcsr.ebreakm=1` 时 ID 级 ebreak 不产生异常，CPU 原地 halt（ID 保持、不冲刷），DM 置 `dcsr.cause=1`、`dpc=ebreak 地址`；调试器恢复原指令后 resume 即可继续执行（软件断点通路）
- **数据观察点**：EX 级访存有效地址匹配（tdata2），tdata1[0]=load（读观察点）/ tdata1[1]=store（写观察点），sizelo[17:16] 过滤访问宽度（0=任意、1=8bit、2=16bit、3=32bit）；命中时流水线停在 EX、store/load 不落盘（总线请求被抑制），`dpc` 取访存指令自身、`dcsr.cause=2`；清 trigger 后 resume 才完成访问

## OpenOCD + GDB 使用（调试功能使用手册）

#### 1. 准备工作

**硬件与驱动**

| 项目 | 说明 |
|------|------|
| 板卡 | 烧录含调试子系统的 bitstream（`BD32_DEBUG_EN` 宏开启，`rtl/Debug/` 例化） |
| 调试器 | Sipeed RV-Debugger（FT2232H），Channel A 四线 JTAG：TCK / TDI / TDO / TMS + GND |
| 驱动 | FT2232H Channel A 需一次性绑定 WinUSB（Zadig）；之后保持 WinUSB 即可（JTAG 与复位均走 OpenOCD，无需切换驱动）；与 Vivado hw_server 冲突时先关闭 Hardware Target |
| 速率 | 杜邦线连接时 `adapter speed 500`（`bd32_openocd.cfg` 已配置），正式 PCB 可提高 |

**工具链**

- OpenOCD（xPack 0.12.0+dev）：`./third_party/xpack-openocd-0.12.0-7/bin/openocd.exe`（从 [xPack OpenOCD Releases](https://github.com/xpack-dev-tools/openocd-xpack/releases) 下载 win32-x64 版本，解压到 `third_party/` 即可，无需安装）
- GDB（xPack GDB 16.3）：`<xPack 工具链>/bin/riscv-none-elf-gdb.exe`
- 目标程序 ELF：如 `./SDK/demos/nolibc/breathing/build/breathing.elf`

**启动 OpenOCD**（默认开 gdb 3333 / telnet 4444 / tcl 6666 端口）：

```bash
.\third_party\xpack-openocd-0.12.0-7\bin\openocd.exe -f .\SDK\tools\bd32_openocd.cfg
```

正常日志应出现 `tap/device found: 0x1bd32003`。随后启动 GDB：

```bash
<xPack 工具链>/bin/riscv-none-elf-gdb.exe program.elf
(gdb) target extended-remote :3333
```

若当前环境无法创建 TCP socket（如受限 shell / 沙箱），可改用**管道模式**：GDB 直接拉起 OpenOCD，通过 stdin/stdout 走 GDB Remote 协议，不依赖 3333 端口（`run_gdb_watchpoint.bat` 即此方式）：

```text
(gdb) target extended-remote | .../openocd.exe -c "gdb port pipe" -f .../bd32_openocd.cfg
```

#### 2. 基本控制：halt / resume / reset halt / 单步

| 功能 | GDB 命令 | 机制与预期 |
|------|----------|------------|
| 暂停 | `monitor halt` | `dmcontrol.haltreq=1`，流水线全级 stall + flush，CPU 原地冻结；dpc = 当前 PC |
| 继续 | `monitor resume` / `continue` | 清 haltreq 后从 dpc 取指继续执行 |
| 复位并暂停 | `monitor reset halt` | `ndmreset` 复位 SoC，haltreq 驻留，复位释放后停在复位向量 PC = 0x0 |
| 单步 | `stepi` | `dcsr.step=1`，执行 1 条指令后重新 halt；单步时门控分支预测，保证 PC 严格 +4 |

示例：

```bash
(gdb) monitor reset halt     # 停在 0x0（BootROM 起点）
(gdb) stepi                  # 每条指令 PC+4
(gdb) p/x $pc
```

#### 3. 寄存器访问（GPR / CSR）

halt 后通过 abstract command 直连 RegFile / CSR 专用端口，不经 CPU 执行任何调试代码：

```bash
(gdb) info registers         # 全部 GPR
(gdb) p/x $a0                # 读 x10
(gdb) set $a0 = 0x12345678   # 写 x10，再 p/x $a0 读回验证
(gdb) p/x $mstatus           # 读 CSR（abstract 通路）
(gdb) p/x $mtvec
(gdb) p/x $dcsr              # dcsr 按 1.0 位域读回
(gdb) p/x $dpc               # 停顿时 PC（断点/ebreak 命中时指向命中指令）
```

#### 4. 内存访问（SBA）

halt 期间通过 SBA 访问整个 SoC 地址空间（32-bit 地址；读为 32-bit，写支持 8/16/32-bit）：

```bash
(gdb) x/4wx 0x10000                          # 读 ITCM
(gdb) set {int}0x20000 = 0xdeadbeef          # 32-bit 写 DTCM
(gdb) set {char}0x20000 = 0x11               # 8-bit 写（RMW 合并）
(gdb) set {short}0x20002 = 0x1234            # 16-bit 写
(gdb) x/1wx 0x20000
```

可访问区域（与 SoC 内存映射一致）：

| 区域 | 地址 | 说明 |
|------|------|------|
| BootROM | 0x0000_0000 | 只读（SBA 子字读不误报 sberror） |
| ITCM | 0x0001_0000 | 代码段，可读写 |
| DTCM | 0x0002_0000 | 数据段，可读写 |
| GPIO | 0xE000_0000 | APB 外设（OUTPUT 0xE000_0008） |
| UART | 0xE001_0000 | APB 外设（LSR 0xE001_0014） |
| Timer / SPI / I2C | 0xE002_0000 / 0xE003_0000 / 0xE004_0000 | APB 外设 |
| CLINT | 0xF200_0000 | APB 外设（mtime 0xF200_BFF8） |
| PLIC | 0xFC00_0000 | APB 外设 |

访问未映射地址（如 0x12345678）时 SBA 置 `sberror`（sbcs[14:12]=2）并读回 0，halt 状态保持，可继续调试。

#### 5. 硬件断点（hbreak，4 路 Trigger）

```bash
(gdb) hbreak *0x10204        # 编程 tdata2=地址、tdata1 置 execute 使能
(gdb) continue
(gdb) p/x $pc                # 命中后停在 0x10204（dpc = 断点地址）
(gdb) info breakpoints
(gdb) delete breakpoints     # 清断点后需 resume 才恢复运行
```

要点：

- 4 路 mcontrol trigger（tselect 0~3）自动分配，可同时下多个 `hbreak` 形成多断点，命中后逐个 `delete` 再 `resume`。
- **命中锁存**：trigger 命中时 DM 自动锁存 haltreq；删除断点不会自动恢复运行，必须显式 resume。
- **不要断在当前 PC**：trigger halt 后 dpc = 命中地址，resume 从 dpc 重新取指，若断点仍在同一地址会再次命中而卡死（OpenOCD 报 unable to resume）。上板测试用"NOP 滑道 + 断点设在下一地址"规避。
- tdata1 复位值 0x2000_0000（type=2、dmode=0、disabled）；dmode=0 避免 OpenOCD 0.12 枚举 trigger 时清零导致 hbreak 失效。

#### 6. 数据观察点（watch，load/store 地址匹配）

```bash
(gdb) watch *(int*)0x20000   # 观察 DTCM 0x20000
(gdb) continue
(gdb) p/x $pc                # 命中：停在访存指令（dpc = load/store 自身）
(gdb) p/x *(int*)0x20000     # store 观察点：新值尚未落盘，读到旧值
(gdb) delete breakpoints
(gdb) continue               # 清观察点后 resume，该次访问才完成
```

要点：

- tdata1[0]=load（读观察点）、[1]=store（写观察点）、[2]=execute（断点）；sizelo[17:16] 过滤访问宽度：0=任意、1=8bit、2=16bit、3=32bit。例如只监视 32-bit 访问时，sb（8bit）不命中、sw（32bit）命中。
- 命中时流水线停在 EX：store 不落盘 / load 不写回（总线请求被抑制），dcsr.cause=2；清除观察点后 resume 才完成该访问。

#### 7. ebreak 进调试模式（软件断点通路）

`dcsr.ebreakm=1` 时 ebreak 指令不产生异常，CPU 原地 halt（ID 保持不冲刷），`dcsr.cause=1`、`dpc = ebreak 地址`，DM 锁存 haltreq。

手动软件断点：用 SBA 把目标指令临时替换为 ebreak（0x0010_0073），命中后恢复原指令再 resume：

```bash
(gdb) set {int}0x10200 = 0x00100073   # 写 ebreak
(gdb) set $pc = 0x10200
(gdb) continue                        # 命中：cause=1，dpc=0x10200
(gdb) set {int}0x10200 = 0x00000013   # 恢复原指令（NOP）
(gdb) continue
```

GDB 的软件断点命令（`break`）完整可用：OpenOCD 把 ebreak 写入目标地址（自动设置 `dcsr.ebreakm`），可设置、命中、`stepi` 单步越过、`continue` 继续运行。OpenOCD 0.12 不声明 `swbreak` 特性，GDB 在 PC 位于软件断点地址时自动执行“删断点→单步→重插→继续”，因此 `continue` 不会原地重命中；回归脚本 `run_gdb_swbp_continue.bat`。注意：若断点设在循环内被反复调用的函数（如 `delay_ms`/`uart_init`），continue 后再次停在同地址属正常现象（程序确实再次执行到该处），可通过 `$ra`/`$sp` 与调用点确认，并非无法越过。数量不受 4 路限制；上述手动替换 ebreak 的方式仍然可用。

#### 8. 真实 demo 符号级调试（以breathing demo程序为例）

```bash
(gdb) file ./SDK/demos/nolibc/breathing/build/breathing.elf
(gdb) target extended-remote :3333
(gdb) monitor reset halt
(gdb) load                          # SBA 写入 ITCM/DTCM
(gdb) set $pc = 0x10000             # 程序入口
(gdb) hbreak main                 # 符号断点（重建后地址自动跟随）
(gdb) continue
(gdb) stepi
(gdb) print <变量名>
```

`bd32_demo_debug.gdb` 已固化该流程（hbreak main、单步、全局变量 / .data / mtime 读取）。

**C 语言级调试**：用 `build.py --debug` 重建固件后，除了符号断点 + `stepi`，还可以源码行 `next`/查看变量（`run_gdb_c_debug.bat` 一键验证）。硬件断点最多 4 路（同时最多 4 个 hbreak）；多次 `next` 依赖触发槽可复用，需 bitstream 含 tdata1 修复（type=0 写入 -> 0x20000000）。

#### 9. OpenOCD TCL 直接操作（DMI 寄存器级）

不经过 GDB，直接用 OpenOCD 的 RISC-V 命令读写 DMI 寄存器（`bd32_debug_test.cfg`、`bd32_watchpoint_test.cfg` 等测试脚本即此类用法）。交互模式：启动 OpenOCD 后 `telnet localhost 4444`；批处理：`openocd -f xxx.cfg`（测试脚本内 telnet/gdb/tcl 端口均 disabled，避免 socket）。

常用命令：

```text
halt / resume / step / reg / reset halt
bd32.cpu riscv dmi_read <addr>
bd32.cpu riscv dmi_write <addr> <val>
```

**DMI 寄存器地址**（Debug Spec 1.0 布局，与 0.13 地址一致）：

| 地址 | 寄存器 | 说明 |
|------|--------|------|
| 0x04 | data0 | abstract command 数据 |
| 0x10 | dmcontrol | bit0=dmactive、bit1=ndmreset、bit28=ackhavereset、bit30=resumereq、bit31=haltreq（WARZ，写 0 清除请求）、[25:16]=hartsello（HARTSELLEN=1，仅 bit0 可实现） |
| 0x11 | dmstatus | bit8=anyhalted、bit9=allhalted、bit11=allrunning |
| 0x16 | abstractcs | bit12=busy、[10:8]=cmderr、[3:0]=datacount |
| 0x17 | command | aarsize[23:20]（0=8/1=16/2=32bit）、transfer[17]、write[16]、regno[15:0] |
| 0x38 | sbcs | [19:17]=sbaccess（0=8/1=16/2=32bit）、[20]=sbreadonaddr、[16]=sbautoincrement、[15]=sbreadondata、[14:12]=sberror、[21]=sbbusy、[22]=sbbusyerror |
| 0x39 | sbaddress0 | SBA 地址 |
| 0x3c | sbdata0 | SBA 数据 |

**Abstract command 的 regno 编码**：

- GPR：`0x1000|n`（n=0~31）
- DM 内部寄存器：`0x7A0`=tselect、`0x7A1`=tdata1、`0x7A2`=tdata2、`0x7B0`=dcsr、`0x7B1`=dpc、`0x7B2`=dscratch0
- CPU CSR：`0xC000|csr`（0.13 风格）或 `0x0000|csr`（1.0 直接编码）

读写示例（与上板验证脚本一致）：

```text
# 读 x10：command=0x0022_100A（aarsize=2=32bit、transfer=1、regno=0x100A），再读 data0
dmi_write 0x17 0x0022100A
dmi_read  0x04

# 写 x10=0x12345678：先写 data0，再 command=0x0023_100A（transfer+write）
dmi_write 0x04 0x12345678
dmi_write 0x17 0x0023100A

# 读 mstatus（CSR 0x300）：command=0x0022_C300
# 读 dcsr：0x0022_07B0；读 dpc：0x0022_07B1
# 写 dpc：先写 data0，再 command=0x0023_07B1
```

**SBA 访问示例**：

```text
# 32-bit 写 DTCM 0x20000 = 0xDEADBEEF
dmi_write 0x38 0x00040000   # sbaccess=2（32bit）
dmi_write 0x39 0x00020000   # 地址
dmi_write 0x3c 0xDEADBEEF   # 数据

# 32-bit 读（sbreadonaddr=1，写地址后自动发起读）
dmi_write 0x38 0x00140000
dmi_write 0x39 0x00020000
dmi_read  0x3c

# 8-bit 写：sbcs=0x00000；16-bit 写：0x00020000
# 未映射地址：sbcs[14:12] sberror=2
```

**Trigger 编程示例**（4 路，tselect 越界写自动钳位到 3）：

```text
# 选择 trigger0，写断点 0x10204
dmi_write 0x04 0x00000000 ; dmi_write 0x17 0x002307A0   # tselect=0
dmi_write 0x04 0x28000004 ; dmi_write 0x17 0x002307A1   # tdata1: type=2、dmode=1、execute
dmi_write 0x04 0x00010204 ; dmi_write 0x17 0x002307A2   # tdata2=断点地址

# 数据观察点 tdata1：0x2800_0002=store、0x2800_0001=load、0x2803_0002=store+仅32bit
# 清除：tdata1=0x2800_0000（type=2、无使能）
```

tdata1 位域：`[31:28]=type(2=mcontrol)`、`[27]=dmode`、`[17:16]=sizelo`、`[2]=execute`、`[1]=store`、`[0]=load`。

dcsr 位域（1.0 布局）：`[31:28]=debugver(4)`、`[15]=ebreakm`、`[8:6]=cause`（1=ebreak、2=trigger、3=haltreq、4=step、5=resethaltreq）、`[2]=step`。

#### 10. 一键回归脚本

SDK/tools/ 下所有脚本输出统一到仓库根 `logs/` 目录：

| 脚本 | 内容 | 结果文件 |
|------|------|----------|
| `bd32_debug_test.cfg`（OpenOCD 直接运行） | DMI 全功能：JTAG、halt/PC、GPR/CSR、单步、SBA、Trigger、reset halt | 终端输出 |
| `bd32_new_feat_test.cfg`（OpenOCD 直接运行） | 新功能专项：SBA 8/16-bit 写、双硬件断点（tselect0/1 依次命中）、ebreak 进调试 | 终端输出 |
| `bd32_sba_periph.cfg`（OpenOCD 直接运行） | SBA 外设总线：GPIO/UART/CLINT 读写、字节使能、未映射 sberror、halt 保持 | 终端输出 |
| `run_gdb_debug_test.bat` | GDB 全功能套件：reset halt、寄存器/CSR、单步、内存读写、hbreak（socket 模式） | `logs/gdb_test_result.txt` |
| `run_demo_debug.bat` | 真实 demo（breathing）符号级调试：加载、hbreak main、单步、变量（socket 模式） | `logs/demo_debug_result.txt` |
| `bd32_watchpoint_test.cfg`（OpenOCD 直接运行） | 数据观察点上板测试：写/读观察点命中、宽度过滤、无访问不误命中 | 终端输出 |
| `run_watchpoint_test.bat` | watchpoint TCL 测试包装 | `logs/watchpoint_test.log` |
| `run_gdb_watchpoint.bat` | GDB 在线 watchpoint（管道模式，无需 socket） | `logs/gdb_watchpoint_result.txt` |
| `run_gdb_c_debug.bat` | GDB C 语言级调试：hbreak main → continue → 源码行 next → 变量，及软件断点（break）命中验证（自动 --debug --opt O0 重建） | `logs/gdb_c_debug_result.txt` |
| `run_gdb_swbp_continue.bat` | GDB 软件断点 continue 回归：直接 continue 越过软件断点、stepi 后 continue、与 hbreak 结合使用（管道模式，无需 socket） | `logs/gdb_swbp_continue_result.txt` |
| `bd32_clean_itcm.cfg`（OpenOCD 直接运行） | 维护工具：将 ITCM 0x10200~0x10300 写回 NOP，清理探针/自循环残留 | 终端输出 |
| `run_msim_debug.bat`（script/debug_test/） | ModelSim 回归（tb_debug，无需板子） | `logs/msim_out.txt` |

```bash
# 正常环境直接运行：
openocd -f ./SDK/tools/bd32_debug_test.cfg
openocd -f ./SDK/tools/bd32_new_feat_test.cfg
openocd -f ./SDK/tools/bd32_sba_periph.cfg
openocd -f ./SDK/tools/bd32_watchpoint_test.cfg
./SDK/tools/run_watchpoint_test.bat
./SDK/tools/run_gdb_watchpoint.bat
./SDK/tools/run_gdb_debug_test.bat
./SDK/tools/run_demo_debug.bat
./script/debug_test/run_msim_debug.bat
```

本机环境说明（Windows exec 环境 Winsock 损坏，进程无法创建 TCP socket / 运行 Node）：
- 所有涉及 socket 的工具（OpenOCD gdb server、GDB、ModelSim 的 vsim）需通过**任务计划程序**运行：
  - `schtasks /run /tn BD32_GDB` —— GDB 全功能套件
  - `schtasks /run /tn GDBDEMO2` —— demo 在线调试
  - `schtasks /run /tn BD32_MSIM` —— ModelSim 回归（结果 `logs/msim_out.txt`）
- FT2232H Channel A 需一次性绑定 WinUSB 驱动（Zadig），否则 libusb 无法访问；绑定后保持 WinUSB 即可，复位不再需要切换到 VCP/ftd2xx（教程见 [验证手册](verification.md)「使用 Zadig 绑定 WinUSB」）
- Vivado hw_server 会占用 JTAG 适配器，使用前需关闭 Hardware Target
- 强制终止 OpenOCD 后可能需要拔插 USB 释放设备句柄
- adapter speed 设为 500 kHz（杜邦线连接），正式 PCB 可提高

## Debug 仿真验证

```bash
# 一键回归（-batch 无界面模式，不依赖 Winsock；从 script/debug_test 运行，
# 保证 SoC_Config.sv 中 ../../test_data 相对路径正确解析 mrom.dat / .mem）：
./script/debug_test/run_msim_debug.bat
# 结果：logs/msim_out.txt（进度标记 logs/msim_mark.txt）

# 交互式波形调试：
cd ./script/debug_test
vsim -do run.do
```

Testbench `tb/tb_debug.sv` 通过 DMI 接口直接激励 DM，无需 JTAG 物理连接，覆盖：
- Test 1~12：IDCODE、halt/resume、GPR/CSR 读写、SBA、单步
- Test 13：reset halt（停在复位向量）
- Test 14：reset halt 后改 dpc 再 resume 的取指对齐（`resume_hold` 回归）
- Test 15：trigger halt 锁存（清断点后 CPU 保持 halt）
- Test 16：ebreak 进调试模式（halt / cause=1 / dpc / 锁存 / resume 后正确执行）
- Test 17：多硬件断点（tselect 选择，双断点依次命中，逐个清除）
- Test 18：SBA 字节/半字写（ITCM/DTCM RMW 合并验证）
- Test 19：SBA 外设总线访问（APB GPIO 0xE000_0000 读写）
- Test 20：数据观察点（load/store 地址匹配 + 宽度过滤）
- Test 21：对照实验——sb 操作数串位是否只在调试路径出现（无调试自跑对比）
- Test 22：SBA 读 BootROM（0x0 区，GDB/OpenOCD 在线 stop 判定路径）+ BootROM 只读写保护
- Test 23：reset halt（CPU 停 0x0）后 2 字节 SBA 读 BootROM，验证子字读不误报 sberror

上板验证（2026-08-06/07 新 bitstream）全部通过：
- DMI 一键测试（`bd32_debug_test.cfg`，OpenOCD 枚举识别 4 个 trigger）
- GDB 套件（`run_gdb_debug_test.bat`：reset halt / 单步 / GPR / CSR / SBA / hbreak）
- 真实 demo（breathing.elf）符号级调试（`run_demo_debug.bat`）
- 新功能专项（`bd32_new_feat_test.cfg`：SBA 8/16-bit 写、双硬件断点、ebreak 进调试模式）
- SBA 外设总线（`bd32_sba_periph.cfg`：SBA 访问 GPIO/UART/CLINT 外设、字节使能、未映射 sberror、halt 保持）
- 数据观察点（`bd32_watchpoint_test.cfg`：写/读观察点、宽度过滤、无访问不误命中）
- GDB 在线数据观察点（`run_gdb_watchpoint.bat`：watch 0x20000 → continue → 命中停止，SBA 读 BootROM 判定路径完整）

当前回归结果：**ModelSim 仿真全部通过**；上板 DMI、新功能、外设 SBA、watchpoint、GDB 在线 watchpoint 全部 PASS。
