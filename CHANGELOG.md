# Changelog

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。首个正式版本发布时开始记录。

## [Unreleased] — 计划 v1.0.0

### 新增
- 数据观察点（watchpoint）：4 路 trigger 的 load/store 地址匹配 + 访问宽度过滤，GDB `watch` 在线调试
- UART 运行时测频：`soc_init()` 实测主频写入 `g_cpu_freq_hz`，`uart_init()` 按实测频率计算 NCO FCW，不再依赖编译期常量
- 调试功能使用手册（README）与 doc/ 文档集（架构 / 调试 / 外设 / 验证）

### 修复
- UART 测试台时钟常量错配（CLK_FREQ 100MHz → 50MHz，匹配实际 PCLK）
- SoC 仿真测试台调试输入悬空导致的 X 传播（ITCM 取指全变 NOP）
- 固件按 75MHz 重新编译（此前为 80MHz 常量，板端波特率偏差约 6.25% 导致串口乱码）
- README 移除本地绝对路径、补充 riscv-tests 已知限制说明

### 工程化
- 脚本路径可移植化（环境变量覆盖 + 相对仓库根路径，日志统一到 `logs/`）
- 清理可再生产物与临时文件
- 行尾统一（.gitattributes）、编辑器规范（.editorconfig）
