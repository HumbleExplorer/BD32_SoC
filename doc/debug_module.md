# 调试模块（Debug Module）

BD32 实现 RISC-V Debug Spec 0.13 风格子集（`dcsr` 读回按 1.0 位域）。
调试子系统位于 `rtl/Debug/`，由板级顶层在 `BD32_DEBUG_EN` 开启时例化。

## 架构：halt-in-place + 直接端口访问

- halt 后流水线全级 stall + flush，CPU 原地冻结；**无需 Debug ROM / Park Loop**。
- GPR/CSR 通过专用调试端口直连（RegFile / CSR_Reg_Access），不经 CPU 执行。
- 内存访问走 SBA（System Bus Access），halt 期间可读写 ITCM/DTCM 及 APB 外设。

```
PC (OpenOCD/GDB) → USB → FT2232H (JTAG) → jtag_tap (TAP+DTM) → debug_dm → debug_cdc → CPU
```

- `jtag_tap`：IEEE 1149.1 TAP + DTM；IDCODE = 0x1BD32003；IR：IDCODE=0x01、DTMCS=0x10、DMI=0x11。
- `debug_dm`：abstract command（GPR/CSR）、SBA、halt/resume/step、Trigger。
- `debug_cdc`：TCK 域与 CPU 时钟域同步。

## DMI 寄存器（地址 / 位域）

| 地址 | 寄存器 | 说明 |
|---|---|---|
| 0x04 | data0 | abstract command 数据 |
| 0x10 | dmcontrol | bit0=dmactive、bit1=ndmreset、bit30=resumereq、bit31=haltreq、[25:16]=hartsel |
| 0x11 | dmstatus | bit8=anyhalted、bit9=allhalted、bit11=allrunning |
| 0x16 | abstractcs | bit11=busy、[9:7]=cmderr |
| 0x17 | command | aarsize[23:20]（0=8/1=16/2=32bit）、transfer[17]、write[16]、regno[15:0] |
| 0x38 | sbcs | [19:17]=sbaccess、[20]=sbreadonaddr、[16]=sbautoincrement、[15]=sbreadondata、[14:12]=sberror |
| 0x39 | sbaddress0 | SBA 地址 |
| 0x3C | sbdata0 | SBA 数据 |

## Abstract Command 编码

`regno`：GPR `0x1000|n`；DM 内部寄存器 `0x7A0`(tselect) / `0x7A1`(tdata1) /
`0x7A2`(tdata2) / `0x7B0`(dcsr) / `0x7B1`(dpc) / `0x7B2`(dscratch0)；
CPU CSR `0xC000|csr` 或 `0x0000|csr`。

示例（OpenOCD TCL）：

```text
# 读 x10：command=0x0022_100A，再读 data0
dmi_write 0x17 0x0022100A
dmi_read  0x04
# 写 x10=0x12345678
dmi_write 0x04 0x12345678
dmi_write 0x17 0x0023100A
```

## Trigger（硬件断点 / 数据观察点）

- 4 路 mcontrol（type=2），`tselect` 选择，越界写自动钳位到 3。
- `tdata1` 位域：`[31:28]=type`、`[27]=dmode`、`[17:16]=sizelo`、`[2]=execute`、`[1]=store`、`[0]=load`。
- 复位值 `tdata1=0x2000_0000`（dmode=0，避免 OpenOCD 0.12 枚举清零导致 hbreak 失效）。
- 断点：IF 级取指地址匹配（execute）；观察点：EX 级访存有效地址匹配（load/store）+ 宽度过滤。
- 命中锁存：trigger 命中后 haltreq 驻留，需显式 resume；观察点命中时 store/load 不提交。

## ebreak 进调试

`dcsr.ebreakm=1` 时 ebreak 不产生异常，CPU 原地 halt（cause=1、dpc=ebreak 地址）。
软件断点：`dcsr.ebreakm=1` 时 ebreak 进调试；GDB `break` 由 OpenOCD 写入 ebreak 实现（数量不受 4 路硬件限制），也可手动用 SBA 临时替换指令为 ebreak（0x00100073）。OpenOCD 0.12 不声明 `swbreak` 特性，GDB 在 PC 位于断点地址时会先“删断点→单步→重插→继续”，因此 `continue` 可正常越过软件断点；回归脚本 `run_gdb_swbp_continue.bat`。若断点位于循环内被反复调用的函数（如 `delay_ms`），continue 后再次命中是正常行为（程序确实再次执行到该处），可通过 `$ra`/sp 与调用点区分。

## dcsr 位域（1.0 布局）

`[31:28]=debugver(4)`、`[15]=ebreakm`、`[8:6]=cause`
（1=ebreak、2=trigger、3=haltreq、4=step、5=resethaltreq）、`[2]=step`。

## 与 Debug Spec 的对照

| 功能 | 实现状态 |
|---|---|
| halt / resume / reset halt / 单步 | 实现 |
| GPR/CSR 抽象访问（cmdtype=0） | 实现 |
| SBA（cmdtype=2 替代） | 实现（8/16/32-bit 写，32-bit 读） |
| Trigger（断点 + 观察点） | 实现（4 路） |
| ebreak 进调试 | 实现 |
| dcsr/dpc/dscratch0 | 实现 |
| ProgBuf | 未实现（progbufsize=0） |
| Debug ROM / Park Loop | 未实现 |
| 抽象内存访问（cmdtype=2） | 未实现 |
| 多 hart | 未实现 |

## 在线调试工具

- 配置：`SDK/tools/bd32_openocd.cfg`（FT2232H + BD32 TAP，gdb 3333 / telnet 4444）。
- GDB 用法、DMI 直接操作示例见 README「调试功能使用手册」。
