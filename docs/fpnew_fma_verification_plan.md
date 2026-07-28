# 单格式 `fpnew_fma` 仿真验证计划

## 1. 验证目标与范围

本环境直接实例化一个 `fpnew_fma`，不经过 `fpnew_fma_multi` 或 `fpnew_top`。每次编译只选择一种 IEEE 浮点格式：

| `FORMAT` | `FpFormat` | 位宽 | 指数位 | 尾数存储位 |
|---|---|---:|---:|---:|
| `FP16` | `fpnew_pkg::FP16` | 16 | 5 | 10 |
| `FP32` | `fpnew_pkg::FP32` | 32 | 8 | 23 |
| `FP64` | `fpnew_pkg::FP64` | 64 | 11 | 52 |

FP16、FP32、FP64 分别编译、运行和签核，覆盖率数据库不得跨格式合并。Berkeley
SoftFloat 没有本项目 FP8 和 FP16ALT 的原生类型，因此本环境遇到这两种格式必须明确
报错，不得把它们映射成其他格式近似验证。

验证内容包括：

- 七种数值运算：FMADD、FMSUB、FNMSUB、FNMADD、ADD、SUB、MUL；
- 五种 RISC-V 静态舍入模式：RNE、RTZ、RDN、RUP、RMM；
- 正常数值、零、subnormal、无穷、qNaN、sNaN 和错误 NaN-boxing；
- `valid/ready` 输入输出握手、输入和输出反压、流水线清空、异步复位；
- result、status、extension bit、tag、mask 和 aux；
- 八种流水线参数配置。

`ROD` 不属于本环境的签核范围，`DYN` 不能直接送入单元。`reg_ena_i` 固定为 0，不验证
外部寄存器使能覆盖功能。

## 2. 编译参数和流水线配置

编译期配置包根据 `FMA_FORMAT_FP16`、`FMA_FORMAT_FP32` 或
`FMA_FORMAT_FP64` 定义以下公共类型：

```systemverilog
localparam fpnew_pkg::fp_format_e FMA_FORMAT = ...;
localparam int unsigned FMA_WIDTH = fpnew_pkg::fp_width(FMA_FORMAT);
typedef logic [FMA_WIDTH-1:0] fma_word_t;
```

因此 transaction、interface 和 DUT 端口都使用该次编译的真实位宽，而不是固定
64 位。只有 DPI 边界使用 64 位无符号整数，FP16 和 FP32 放在低位。

必须支持以下配置：

| `CFG` | `NumPipeRegs` | `PipeConfig` |
|---|---:|---|
| `n0_before` | 0 | BEFORE |
| `n2_before` | 2 | BEFORE |
| `n2_inside` | 2 | INSIDE |
| `n2_after` | 2 | AFTER |
| `n1_dist` | 1 | DISTRIBUTED |
| `n2_dist` | 2 | DISTRIBUTED |
| `n3_dist` | 3 | DISTRIBUTED |
| `n4_dist` | 4 | DISTRIBUTED |

## 3. 验证环境结构

```text
tb/fma_uvm/
├── common/                 编译期格式和公共 transaction/record
├── interface/              参数化 DUT interface
├── agents/
│   ├── input/              data/control sequencer、driver 和 input monitor
│   └── output/             ready sequencer、driver 和 output monitor
├── env/
│   ├── components/         SoftFloat reference、scoreboard、coverage
│   ├── fma_env_cfg.svh
│   ├── fma_virtual_sequencer.svh
│   └── fma_env.svh
├── sequences/
│   ├── data/
│   ├── control/
│   ├── ready/
│   └── virtual/
├── tests/                  七个 test class
├── assertions/             接口、状态和 early_out_valid 检查
├── dpi/softfloat/          统一 DPI adapter 和独立自检
├── top/                    单 DUT top
├── files/、mk/、cfg/       filelist、构建和回归配置
└── scripts/                回归、结果和覆盖率检查
```

每个 class 单独放在一个 `.svh` 中。package 文件只负责 `import` 和 `include`。依赖顺序固定为 common → agents/env → sequences → tests → top。

### 3.1 连接关系

```text
input_monitor.in_data_ap
    ├── fma_reference_model
    └── fma_coverage

fma_reference_model.ref_expected_ap
    └── scoreboard.scb_expected_imp

output_monitor.out_agt_data_ap
    └── scoreboard.scb_actual_imp

scoreboard.scb_checked_data_ap
    └── fma_coverage

input_monitor.in_control_ap
    ├── scoreboard.scb_control_imp
    └── fma_coverage
```

输入 monitor 是“DUT 接受了一项运算”的唯一判定位置。driver response 只用于 sequence
得知该 item 是完成输入握手还是被 reset/flush 取消，不能送往参考模型、scoreboard 或
coverage。

## 4. Agent 职责和驱动时序

### 4.1 Input agent

Input agent 内包含两个相互独立的 sequencer/driver：

- data sequencer/driver 独占 A、B、C、`is_boxed_i`、`rnd_mode_i`、`op_i`、
  `op_mod_i`、tag、mask、aux 和 `in_valid_i`；
- control sequencer/driver 独占 `rst_ni` 和 `flush_i`。

`valid` 属于数据传输协议，必须和当前 data item 的存在、保持和完成输入握手绑定；它
不是 reset/flush 一类的全局控制事件，所以不能由 control driver 驱动。

### 4.2 Output agent

Output agent 的 ready sequencer/driver 独占 `out_ready_i`。ready item 表示
`ready 值 + 保持周期数`，从而能直接描述 always-ready、短暂停顿、长暂停和有界随机
反压。随机低电平的默认最长持续时间为 16 个周期，sequence 结束时必须把 ready 置 1。

### 4.3 边沿约定

- data、control、ready 都在时钟下降沿改变；
- 输入和输出正常数据在时钟上升沿采样；
- `flush_i` 在时钟上升沿采样；
- 异步低有效 reset 的 assert 事件由 `negedge rst_ni` 监测，deassert 事件由
  `posedge rst_ni` 监测；
- top 在 0 时刻只提供安全初值，随后 reset/flush 由 control driver 独占。

这样，目标上升沿到来之前所有刺激都已稳定，不依赖多个 driver 在同一仿真时间片中的
执行先后。

### 4.4 data item 的接受和取消

data driver 只有在 `rst_ni==1 && flush_i==0` 时才从 sequencer 取得新 item。取得之后，
该 item 在等待发送、拉高 valid、等待 ready 的任何阶段都属于当前 item。

每个采样沿按以下优先级处理：

```text
reset > flush > input handshake
```

规则如下：

1. reset 或 flush 与 `in_valid_i && in_ready_o` 同周期出现时，当前 item 被取消，不记为
   输入握手；
2. reset 和 flush 同时出现时，response 为 `FMA_DATA_CANCELED_BY_RESET`；
3. 仅 flush 出现时，response 为 `FMA_DATA_CANCELED_BY_FLUSH`；
4. 无 reset/flush 且完成握手时，response 为 `FMA_DATA_ACCEPTED`；
5. 取消后立即撤销 valid，不自动重发该 item；
6. 连续多个周期 flush 只会取消当前 item 一次，flush 为高期间不再取得新 item；
7. 尚留在 sequencer 中、driver 还未取得的后续 item 不被取消。

`flush_i` 是同步控制信号。它在下降沿被 control driver 拉高后，data driver 必须继续保持
当前 valid 和数据，直到下一上升沿按上述优先级判定取消；不能在 flush 的上升跳变发生时
提前撤销 valid。只有异步 reset 的 assertion 可以在两个采样沿之间立即取消当前 item。

输入 monitor 发布数据的条件必须是：

```systemverilog
rst_ni && !flush_i && in_valid_i && in_ready_o
```

输出 monitor 发布数据的条件必须是：

```systemverilog
rst_ni && !flush_i && out_valid_o && out_ready_i
```

即使 `NumPipeRegs=0`，reset/flush 与表面上的 valid-ready 同周期出现时，也不能生成输入
或输出 record。

## 5. 公共记录

环境按顺序工作的 DUT 应由scoreboard 的队列顺序直接检查。

- `fma_input_context`：原始 A/B/C、三个 boxing 位、raw op/mod、舍入模式、tag、mask、
  aux；
- `fma_expected_record`：input context、期望 result/status，以及复制的 sideband 和
  `extension_bit=1`；
- `fma_actual_record`：DUT result/status/extension bit/tag/mask/aux；
- `fma_checked_record`：通过比较的 input context 和实际输出；
- `fma_control_event`：RESET_ASSERT、RESET_DEASSERT 或 FLUSH。FLUSH 同时保存
  in_valid/in_ready/out_valid/out_ready/busy。

Input monitor 在 reset assert 和 deassert 时各发布一次事件；当 reset 已解除且 flush 连续
保持为高时，每个上升沿都发布一次 FLUSH。reset 为低期间不处理 flush，以体现 reset 的
更高优先级。FLUSH 事件保存的 valid、ready 和 busy 必须取 clocking block 在该上升沿
采样的值，即 DUT 同步清空流水线之前的接口状态；不能读取清空后已经变化的实时信号。

## 6. 操作解码

transaction 保存 raw `op_i` 和 `op_mod_i`。环境只接受下面 10 个控制编码，并将它们
解码为 7 种数值运算：

| raw `op_i` | `op_mod_i` | 数值运算 | 参考运算 |
|---|---:|---|---|
| FMADD | 0 | FMADD | `A*B+C`，只舍入一次 |
| FMADD | 1 | FMSUB | `A*B-C`，只舍入一次 |
| FNMSUB | 0 | FNMSUB | `-(A*B)+C`，只舍入一次 |
| FNMSUB | 1 | FNMADD | `-(A*B)-C`，只舍入一次 |
| ADD | 0/1 | ADD/SUB | `B+C` / `B-C` |
| ADDS | 0/1 | ADD/SUB | `B+C` / `B-C` |
| MUL | 0/1 | MUL | `A*B` |

ADD 和 ADDS 在这个单格式模块中执行相同的数值运算，因此功能覆盖将它们合并成
ADD/SUB，但覆盖保留二者。MUL 的两个 modifier 都送入 DUT并成对检查；当前
RTL 对二者都执行乘法。

ADD/ADDS 的原始 A 以及 MUL 的原始 C 仍要正常随机化、分类和覆盖。这样才能证明被
DUT 忽略的操作数数值与 boxing 状态不会错误地影响结果或 NV。

## 7. SoftFloat 参考模型

参考模型当前使用 Berkeley SoftFloat Release 3e.

构建必须使用 `RISCV` specialization。每次调用前执行：

```c
softfloat_roundingMode = ...;
softfloat_detectTininess = softfloat_tininess_afterRounding;
softfloat_exceptionFlags = 0;
```

五种模式映射如下：

| RTL | SoftFloat |
|---|---|
| RNE | `softfloat_round_near_even` |
| RTZ | `softfloat_round_minMag` |
| RDN | `softfloat_round_min` |
| RUP | `softfloat_round_max` |
| RMM | `softfloat_round_near_maxMag` |

统一 DPI 函数接收 format、七种数值运算之一、舍入模式和三个 64 位操作数，返回 64 位
结果、`{NV,DZ,OF,UF,NX}` 以及返回码。C 端按格式直接调用 `f16_*`、`f32_*` 或
`f64_*` 函数。FMA 必须调用对应的 `mulAdd`，不能用一次乘法加一次加法代替。

### 7.1 NaN-boxing 和被忽略操作数

参考组件先根据 op/mod 判断实际参与数值运算的操作数：

- 四种 FMA 使用 A、B、C；
- ADD/SUB 只使用 B、C；
- MUL 只使用 A、B。

实际参与运算且 `is_boxed_i==0` 的操作数替换为当前格式的 canonical quiet NaN；被忽略操作数无论其位模式和 boxing 如何都不会被送入参考运算。这样与 DUT 在操作数修改后的行为一致，同时保留 input context 中的原始值供覆盖率使用。

SoftFloat 只由一个同步 `fma_reference_model` 组件调用，避免同一进程中的全局
rounding mode 和 exception flags 被并发修改。不同格式的回归是独立仿真进程。

## 8. Scoreboard

Scoreboard 使用三个 typed analysis implementation：

- `scb_expected_imp` 接收参考结果；
- `scb_actual_imp` 接收 DUT 输出；
- `scb_control_imp` 接收 reset/flush。

内部只有 `expected_q` 和 `actual_q` 两个本地队列。写入队列前必须 clone record，防止发布者重复使用对象导致队列内容被修改。只按队首顺序配对，不用 tag 查找；tag 本身仍逐位比较，所以丢失、重复、乱序都能被发现。

reset assert 或任意 FLUSH 事件立即清空两个队列，reset deassert 不修改队列。

当 `NumPipeRegs=0` 时，同一仿真时刻可能先执行 output monitor 的回调，再执行 input monitor 和 reference 回调。actual 可以暂存在 `actual_q` 到当前 `$time` 的末尾；它只能和同一 `$time` 到达的 expected 配对。如果到时间片末尾仍没有 expected，必须报告unexpected output 并丢弃，不能等待将来的输入与它配对。

逐项比较：result、五个 status 位、extension bit、tag、mask 和 aux。比较通过后才生成`fma_checked_record` 并由 `scb_checked_data_ap` 发给 coverage；比较失败只增加错误计数，不采样 checked result coverage。`check_phase` 要求 mismatch 为 0 且两个队列为空。

## 9. 功能覆盖率

`fma_coverage` 只包含三个 covergroup：`input_cg`、`checked_result_cg` 和
`control_cg`。内部逻辑由 RTL 代码覆盖率补充。

### 9.1 输入覆盖

只在真实输入握手时采样：

- 10 个 op/mod 编码 × 5 个舍入模式；
- A、B、C 各自按原始位模式分成 12 类：±zero、±subnormal、±normal、±infinity、
  ±qNaN、±sNaN；
- 对每个操作数分别覆盖 `7种数值运算 × 12类 × boxed/unboxed`，即每个操作数 168 个
  组合，三个操作数共 504 个；
- `7种数值运算 × is_boxed_i[2:0]`，共 56 个组合；
- mask 为 0 和 1；
- tag 和 aux 参与逐项检查，但不做 256 值穷举覆盖。

错误 boxing 的操作数仍按其原始浮点位模式分类，不能先替换 NaN 再采样。

### 9.2 通过比较后的结果覆盖

结果边界共 17 个：

- +0、-0；
- 正负 min/middle/max subnormal；
- 正负 min/middle normal 和 max finite；
- +infinity、-infinity；
- 正 canonical qNaN。

status 只允许：无标志、NX、UF+NX、OF+NX、NV，即位模式 `00000`、`00001`、
`00011`、`00101`、`10000`。其他组合属于非法输出。

建立四个交叉：

1. 数值运算 × 结果类别；
2. 数值运算 × status 类别，ADD/SUB 的 UF+NX 不计入目标；
3. 舍入模式 × NX、UF+NX、OF+NX；
4. 合法结果类别 × status 类别。

结果与 status 的允许关系为：

| 结果 | 允许 status |
|---|---|
| ±zero | 无标志、UF+NX |
| subnormal | 无标志、UF+NX |
| min normal | 无标志、NX、UF+NX |
| middle normal | 无标志、NX |
| max finite | 无标志、NX、OF+NX |
| ±infinity | 无标志、OF+NX |
| canonical qNaN | 无标志、NV |

### 9.3 控制覆盖

直接采样 input monitor 的事件：

- reset assert、reset deassert、flush；
- flush 时输入分为：valid=0、valid=1且ready=0、valid=1且ready=1；
- flush 时输出采用同样三类；
- busy 独立覆盖 0 和 1。

不建立输入状态与输出状态的完整交叉，也不建立 flush 持续周期数 coverpoint。连续 flush
由定向 sequence 验证。

## 10. Stimulus

每个操作数独立选择生成方式：

- 50%：在该格式全部位模式上均匀随机；
- 50%：先均匀选择 12 个 sign/class 之一，再在该类内部随机。

三个 boxing 位、raw control、舍入模式和操作数生成方式彼此独立。sequence 在
`start_item` 之前等待输入间隔；transaction 中没有 gap 字段，因此等待期间 driver 不会
错误地把尚未发送的 item 当作当前 item。

定向特殊值至少包含：

- infinity × zero 与 qNaN、sNaN、错误 boxing 的 C 组合；
- qNaN/错误 boxing 与 infinity 组合；
- sNaN 与 infinity 组合；
- 多个 qNaN/sNaN 同时出现；
- 无穷乘积与相反符号无穷 C；
- 无穷乘积与相同符号无穷 C；
- ADD/ADDS 固定 B/C，遍历原始 A 的 12 类和 boxing；
- MUL 固定 A/B，遍历原始 C 的 12 类和 boxing，并成对使用两个 modifier。

这些输入不增加“内部特殊分支”功能 coverpoint，其正确性由 SoftFloat result/status 与
scoreboard 检查。

为使输出功能覆盖可由定向测试闭合，而不是依赖随机命中精确浮点位模式，还必须生成：

- 7 种数值运算各自产生全部 17 个指定结果，共 119 个“运算 × 结果”向量；
- 每种运算产生其可达到的 NX、UF+NX、OF+NX 和 NV；
- 五种舍入模式分别产生 NX、UF+NX 和 OF+NX；
- `result × status` 表中每个合法组合。特别地，舍入到最小 normal 且产生 UF+NX 的向量使用 `min_normal - 0.5*min_subnormal`：乘积项精确提供半个最小 subnormal RNE 将中点舍入为最小 normal，同时微小且不精确的结果置位 UF 和 NX。

## 11. 七个测试

1. `fma_smoke_test`：10 个 control × 5 个舍入模式，使用简单有限数和不同 sideband；所有八个流水配置都运行。
2. `fma_directed_test`：504 个操作数交叉、56 个 boxing 组合、特殊值优先级、舍入边界、
   状态和被忽略操作数；使用 `n0_before`。
3. `fma_flow_control_test`：连续输入、输入空拍、长短输出暂停、流水线填充/排空以及`NumPipeRegs=0` 同周期输入输出；所有八个配置都运行。
4. `fma_flush_test`：先在没有 traffic 时产生确定的 idle flush；随后根据实际接口状态等待输入握手、输出 valid 被阻塞以及输出握手，再分别产生 1/2/3 周期 flush，保证三类输入状态、三类输出状态和 busy=0/1 都被真实采样；最后发送已知运算检查恢复。
5. `fma_reset_test`：空闲和 busy 时异步 reset、输入/输出暂停、reset 与 flush 同时出现、多次 reset 及恢复。
6. `fma_random_data_test`：随机数据和有界随机 ready，不插入中途 reset/flush。
7. `fma_random_control_test`：随机 data/ready、低频 flush 和更低频 reset，检查取消、队列清除及恢复。

test 只负责配置、启动 virtual sequence 和结束排空；具体向量和并行控制由 sequence实现。virtual sequencer 保存 data、control、ready 三个 sequencer handle 和只读 vif，但不直接驱动接口。

### 11.1 结束条件

1. 停止生成新的 reset/flush，最终保持 `rst_ni=1, flush_i=0`；
2. data sequence 返回，所有已取得 item 都已收到完成或取消 response；
3. ready sequence 返回，最终保持 `out_ready_i=1`；
4. scoreboard 两个队列为空；
5. `busy_o==0 && out_valid_o==0 && scoreboard idle` 连续保持至少
   `NumPipeRegs+2` 个周期；
6. 默认 1000 周期内不能满足则 fatal。

## 12. Assertions

- 输入反压期间，valid 和全部输入内容保持稳定；reset/flush 周期排除；
- 输出反压期间，valid 和全部输出内容保持稳定；reset/flush 周期排除；
- valid 输出中的数据不能含 X/Z；
- 有效输出的 extension bit 必须为 1；
- status 只能是五种合法组合；
- NV 必须对应 canonical qNaN；
- DZ 必须为 0；UF 必须同时有 NX；OF 必须同时有 NX；
- NV 与其他异常标志互斥，OF 与 UF 互斥；
- 有效输入或有效输出存在时，busy 必须为 1；
- `early_out_valid_o` 按参数化流水线的接口含义严格检查。

当前 RTL 的 INSIDE 两级配置在 `early_out_valid_o` ready 索引上有已知问题。只把
`fma_flow_control_test + n2_inside` 的确定性触发项标为 XFAIL；smoke 不标 XFAIL。
checker 不能为迁就现有 RTL 而放宽。将来修复 DUT 后，该项会变成 XPASS，回归应失败
并要求删除 XFAIL 标记。本次环境实现不修改 DUT。XFAIL 只在以下条件同时满足时成立：
scoreboard 的 mismatch、unexpected output 和 pending 都为 0，UVM error/fatal 为 0，
没有 timeout，而且日志中的每个 assertion failure 都来自 `a_early_out_valid`。该条目中
任何其他失败都必须报告 FAIL，不能被 XFAIL 掩盖。

## 13. 回归和签核

每种格式的代表性矩阵为：

- smoke：全部八个配置；
- directed：`n0_before`；
- flow control：全部八个配置，其中 `n2_inside` 为已知 XFAIL；
- flush/reset：`n0_before`、`n2_before`、`n2_after`、`n4_dist`；
- random data：上述四个配置，n0/n4 默认各 20000，n2 before/after 各 5000；
- random control：n0/n4 各 10000 次操作尝试。

每种格式单独满足：

- 除声明的 XFAIL 外，0 UVM error/fatal、0 scoreboard mismatch、0 SVA failure、0 timeout；
- 仿真结束时 expected/actual 队列为空；
- mandatory functional coverage 100%；
- DUT hierarchy（包括其内部 `fpnew_rounding`）line/branch/condition 各不低于 95%，toggle 不低于 90%。

`signoff` suite 必须使用 `PROFILE=cov`。回归脚本在每种格式的测试结束后自动调用 URG，只合并本次运行中状态为 PASS 的 coverage database；XFAIL、FAIL 和 XPASS 数据均不参与合并。随后脚本自动执行上述代码覆盖率和三个 covergroup 100% 的门槛检查，任一门槛不满足时整个 signoff 返回失败。手工 `cov-report` 同样根据日志只选择普通 PASS，并明确排除 `n2_inside + fma_flow_control_test`。

代码覆盖率只收集 DUT hierarchy。允许明确说明并审查的排除项包括：ROD/DYN、
`reg_ena_i=1`、固定常量输出（例如 DZ、extension bit）和当前参数下未生成的 generate分支。其余未覆盖代码必须逐项分析，不能仅因总百分比达标而忽略。

SoftFloat adapter 自检必须先于 UVM 回归通过，并覆盖三种格式、五种舍入模式、RMM
中点、invalid、overflow 和 underflow。每个日志保留 FORMAT、CFG、TEST、SEED 和
NB_TXNS；报告和 coverage 数据库按格式分目录保存。
