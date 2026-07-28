# FPnew 单格式并行 FMA 微架构规格

## 1. 文档目的与适用范围

本文档规定 FPnew `ADDMUL` 操作组中单格式并行 FMA 单元的功能、接口、位宽、组合数据通路、特殊值处理、规格化、舍入、状态标志和弹性流水线行为。

本文档对应以下实现：

- 主模块：[`../src/fpnew_fma.sv`](../src/fpnew_fma.sv)
- 输入分类：[`../src/fpnew_classifier.sv`](../src/fpnew_classifier.sv)
- 舍入单元：[`../src/fpnew_rounding.sv`](../src/fpnew_rounding.sv)
- 公共类型及格式定义：[`../src/fpnew_pkg.sv`](../src/fpnew_pkg.sv)

## 2. 功能概述

单元以三个同格式浮点操作数 `A`、`B`、`C` 为输入，统一执行以下数学骨架：

```text
R = round_once(A' * B' + C')
```

其中 `A'`、`B'`、`C'` 由 `op_i` 和 `op_mod_i` 对原始操作数进行符号修改或常量替换得到。乘积必须在完整 `2p` 位精度下进入加法器，乘法后不得单独舍入；整个乘加只允许在最终结果处舍入一次。

单元必须支持：

- fused multiply-add/subtract 及其 negated 变体；
- 普通加法和减法；
- 普通乘法；
- normal、subnormal、零、无穷和 NaN；
- RNE、RTZ、RDN、RUP、RMM 和 ROD 舍入模式；
- NV、DZ、OF、UF、NX 状态标志；
- 可配置数量和位置的弹性流水寄存器；
- tag、mask 和 aux 旁带信息透传；
- valid/ready 反压和同步 flush。

### 2.1 总体架构图

下图展示输入处理、特殊值旁路、常规数值通路、三个可选流水区以及最终
result/status 选择之间的关系。灰色虚线框表示寄存器数量可以为零，其实际
分配由 `NumPipeRegs` 和 `PipeConfig` 决定。

![FPnew 单格式并行 FMA 总体架构](fig/fpnew_fma_arch_overview.svg)

可编辑源文件：[`fpnew_fma_arch.drawio`](fig/fpnew_fma_arch.drawio)。源文件还包含对阶/加减和
规格化/舍入两页详图。

## 3. 浮点格式模型

### 3.1 编码

`FpFormat` 提供：

```text
EXP_BITS = exp_bits(FpFormat)
MAN_BITS = man_bits(FpFormat)
WIDTH    = 1 + EXP_BITS + MAN_BITS
BIAS     = 2^(EXP_BITS-1) - 1
p        = PRECISION_BITS = MAN_BITS + 1
```

浮点位串必须按下列顺序解释：

```text
[WIDTH-1]                         sign
[WIDTH-2 : MAN_BITS]              encoded exponent E
[MAN_BITS-1 : 0]                  fraction F
```

内部可以定义等价的 packed struct：

```systemverilog
typedef struct packed {
  logic                sign;
  logic [EXP_BITS-1:0] exponent;
  logic [MAN_BITS-1:0] mantissa;
} fp_t;
```

### 3.2 数值解释

对正确 NaN-box 的有限输入，定义 `p` 位整数有效尾数 `M`：

```text
normal:    M = {1'b1, F}
subnormal: M = {1'b0, F}
zero:      M = 0
```

定义有效无偏指数：

```text
normal:    e = E - BIAS
subnormal: e = 1 - BIAS
zero:      数学值为零，偏置指数为0，但运算中间指数按后文的专用规则赋值
```

有限非零数的数学值为：

```text
value = (-1)^sign * M * 2^(e-(p-1))
```

$ value = (-1)^{sign} \times M \times 2^{e-(p-1)} $

### 3.3 参数约束

实现至少必须满足：

- `EXP_BITS >= 2`；
- `MAN_BITS >= 1`，因为 canonical qNaN 使用最高 fraction 位作为 quiet 位；
- 指数采用对称 bias，即 `2^(EXP_BITS-1)-1`；
- `NumPipeRegs >= 0`；
- `PipeConfig` 只能取 `BEFORE`、`AFTER`、`INSIDE` 或 `DISTRIBUTED`。

### 3.4 当前预定义格式对应位宽

| 格式 | `EXP_BITS` | `MAN_BITS` | `PRECISION_BITS(p)` | `WIDTH` | `BIAS` | `LOWER_SUM_WIDTH` | `EXP_WIDTH` | 对齐有效数宽度 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FP32 | 8 | 23 | 24 | 32 | 127 | 51 | 10 | 76 |
| FP64 | 11 | 52 | 53 | 64 | 1023 | 109 | 13 | 163 |
| FP16 | 5 | 10 | 11 | 16 | 15 | 25 | 7 | 37 |
| FP8 | 5 | 2 | 3 | 8 | 15 | 9 | 7 | 13 |
| FP16ALT | 8 | 7 | 8 | 16 | 127 | 19 | 10 | 28 |

表中的“对齐有效数宽度”为 `3p+4` 位，用于保存对阶后的乘积与 C 以及两者的加减结果，不含加减器额外的进位/借位观察位。

表中各个参数值的计算方式在`4.2 数据通路常量`一节。

## 4. 参数和派生常量

### 4.1 模块参数

| 参数 | 类型 | 含义 |
|---|---|---|
| `FpFormat` | `fp_format_e` | 本实例唯一支持的浮点格式 |
| `NumPipeRegs` | `int unsigned` | 数据通路中插入的寄存器总数 |
| `PipeConfig` | `pipe_config_t` | 寄存器放置策略 |
| `TagType` | type parameter | tag 旁带类型 |
| `AuxType` | type parameter | aux 旁带类型 |

### 4.2 数据通路常量

实现必须使用下列常量关系：

```text
// 加上隐含位
PRECISION_BITS    = MAN_BITS + 1
// | 1位加法运算可能的进位carry | 2p位乘积尾数 | 2位G/R |
LOWER_SUM_WIDTH   = 2*PRECISION_BITS + 3
// 前导0计数器的取值范围：[ 0 ... LOWER_SUM_WIDTH-1 ]，
// LOWER_SUM_WIDTH全为0时，LZC单独有信号指示，故只需对LOWER_SUM_WIDTH取对数
LZC_RESULT_WIDTH  = ceil(log2(LOWER_SUM_WIDTH))
// 1. 两个 EXP_BITS 位指数相加，需要增加一位；
// 2. 减去 BIAS 或计算指数差后，结果可能为负，需要符号位。
EXP_WIDTH         = EXP_BITS + 2
// 加数C的最大移位量为3p+4，故取对数时需对3p+5取对数
SHIFT_AMOUNT_WIDTH= ceil(log2(3*PRECISION_BITS + 5))
// 保存普通加法结果或减法后的绝对值；
// | 加数C的p位尾数 | 2位G/R | 乘积尾数2p位 | 2位G/R |
SUM_WIDTH         = 3*PRECISION_BITS + 4
// 观察减法 carry/borrow，并据此选择差值绝对值和最终符号
// 或保存大规格化左移后可能到达 sum_shifted[SUM_WIDTH] 的最高非零位
// 最终 `sum` 仍只保留低 `SUM_WIDTH` 位；额外最高位属于控制和规格化信息，
// 不属于最终有效数字段
ADDER_WIDTH       = SUM_WIDTH + 1
```

### 4.3 流水线寄存器分配

定义：

```text
if PipeConfig == BEFORE:
    NUM_INP_REGS = NumPipeRegs
else if PipeConfig == DISTRIBUTED:
    NUM_INP_REGS = floor((NumPipeRegs + 1)/3)
else:
    NUM_INP_REGS = 0

if PipeConfig == INSIDE:
    NUM_MID_REGS = NumPipeRegs
else if PipeConfig == DISTRIBUTED:
    NUM_MID_REGS = floor((NumPipeRegs + 2)/3)
else:
    NUM_MID_REGS = 0

if PipeConfig == AFTER:
    NUM_OUT_REGS = NumPipeRegs
else if PipeConfig == DISTRIBUTED:
    NUM_OUT_REGS = floor(NumPipeRegs/3)
else:
    NUM_OUT_REGS = 0
```

必须保证：

```text
NUM_INP_REGS + NUM_MID_REGS + NUM_OUT_REGS = NumPipeRegs
```

`DISTRIBUTED` 按“内部、输入、输出”的顺序循环增加寄存器。例如：

| `NumPipeRegs` | 输入 | 内部 | 输出 |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 1 | 0 | 1 | 0 |
| 2 | 1 | 1 | 0 |
| 3 | 1 | 1 | 1 |
| 4 | 1 | 2 | 1 |
| 5 | 2 | 2 | 1 |
| 6 | 2 | 2 | 2 |

外部寄存器使能端口宽度为：

```text
ExtRegEnaWidth = (NumPipeRegs == 0) ? 1 : NumPipeRegs
```

当 `NumPipeRegs==0` 时，`reg_ena_i[0]` 不参与任何功能。

## 5. 接口规格

### 5.1 端口

| 端口 | 方向 | 类型/宽度 | 规定行为 |
|---|---|---|---|
| `clk_i` | 输入 | `logic` | 所有寄存器使用上升沿 |
| `rst_ni` | 输入 | `logic` | 低有效异步复位 |
| `operands_i` | 输入 | `[2:0][WIDTH-1:0]` | 原始 A、B、C；索引 0、1、2 分别对应 A、B、C |
| `is_boxed_i` | 输入 | `[2:0]` | 每个操作数是否正确 NaN-boxed |
| `rnd_mode_i` | 输入 | `roundmode_e` | 舍入模式 |
| `op_i` | 输入 | `operation_e` | 操作选择 |
| `op_mod_i` | 输入 | `logic` | 操作修改位，主要控制 C 取反 |
| `tag_i` | 输入 | `TagType` | 原样随事务传输 |
| `mask_i` | 输入 | `logic` | 原样随事务传输，FMA 内部不屏蔽计算 |
| `aux_i` | 输入 | `AuxType` | 原样随事务传输 |
| `in_valid_i` | 输入 | `logic` | 输入事务有效 |
| `in_ready_o` | 输出 | `logic` | 输入端可接收事务 |
| `flush_i` | 输入 | `logic` | 同步清除流水线 valid 状态 |
| `result_o` | 输出 | `[WIDTH-1:0]` | 浮点结果 |
| `status_o` | 输出 | `status_t` | `{NV,DZ,OF,UF,NX}` |
| `extension_bit_o` | 输出 | `logic` | 恒为 1，用于上层 NaN-box |
| `tag_o` | 输出 | `TagType` | 对应输入事务的 tag |
| `mask_o` | 输出 | `logic` | 对应输入事务的 mask |
| `aux_o` | 输出 | `AuxType` | 对应输入事务的 aux |
| `out_valid_o` | 输出 | `logic` | 输出事务有效 |
| `out_ready_i` | 输入 | `logic` | 下游可接收输出 |
| `busy_o` | 输出 | `logic` | 任一组合入口或寄存器级持有有效事务 |
| `reg_ena_i` | 输入 | `[ExtRegEnaWidth-1:0]` | 仅覆盖 payload 寄存器使能，不改变 valid |
| `early_out_valid_o` | 输出 | `logic` | 提前指示当前或下一拍输出占用，详见第 19.6 节 |

### 5.2 valid/ready 契约

输入事务在某个 `clk_i` 上升沿满足以下条件时被接收：

```text
in_valid_i && in_ready_o
```

输出事务在某个上升沿满足以下条件时被下游接收：

```text
out_valid_o && out_ready_i
```

调用方必须在 `valid==1 && ready==0` 时保持对应 payload 稳定。实现必须通过反压保证已进入寄存器流水线的 payload 在输出停顿时不会被覆盖。若 `NumPipeRegs==0`，反压为从 `out_ready_i` 到 `in_ready_o` 的组合路径。

无停顿时：

- 允许每周期接收一个事务；
- 从输入握手到输出可用的寄存器延迟为 `NumPipeRegs` 个周期；
- 当 `NumPipeRegs==0` 时，结果和 `out_valid_o` 为组合输出。

## 6. 输入分类

### 6.1 分类规则

每个原始操作数都必须先按 `FpFormat` 和对应 `is_boxed_i` 分类。设 `E` 为 exponent，`F` 为 fraction，`boxed` 为对应的 boxing 位：1表示对应操作数正确NaN-Boxing，0表示对应操作数不正确NaN-Boxing。

```text
is_normal    = boxed && E != 0 && E != all_ones
is_zero      = boxed && E == 0 && F == 0
is_subnormal = boxed && E == 0 && F != 0
is_inf       = boxed && E == all_ones && F == 0
is_nan       = !boxed || (E == all_ones && F != 0)
is_signalling= boxed && is_nan && F[MAN_BITS-1] == 0
is_quiet     = is_nan && !is_signalling
is_boxed     = boxed
```

不正确 NaN-box 的操作数必须被视为 quiet NaN：

```text
is_nan       = 1
is_signalling= 0
is_quiet     = 1
```

### 6.2 分类与操作改写顺序

必须先分类原始输入，再执行第 7 节的操作数改写。若操作改写用常量替换某个操作数，必须同时用该常量的已知分类替换原始分类：

- ADD/ADDS 替换 A 后，原始 `operands_i[0]` 的所有分类和特殊值都必须被忽略；
- MUL 替换 C 后，原始 `operands_i[2]` 的所有分类和特殊值都必须被忽略。

## 7. 操作译码与操作数改写

### 7.1 默认操作数

输入流水线末端的三个操作数先映射为：

```text
operand_a = operands[0]
operand_b = operands[1]
operand_c = operands[2]
info_a    = classify(operands[0])
info_b    = classify(operands[1])
info_c    = classify(operands[2])
```

随后，在操作译码之前必须首先执行：

```text
operand_c.sign ^= op_mod
```

### 7.2 操作表

| `op_i` | `op_mod_i` | 操作数改写 | 数学语义 |
|---|---:|---|---|
| `FMADD` | 0 | 不再修改 | `A*B + C` |
| `FMADD` | 1 | C 符号取反 | `A*B - C` |
| `FNMSUB` | 0 | A 符号取反 | `-(A*B) + C` |
| `FNMSUB` | 1 | 先取反 C，再取反 A | `-(A*B) - C` |
| `ADD` | 0 | A 替换为 `+1.0` | `B + C` |
| `ADD` | 1 | C 符号取反，A 替换为 `+1.0` | `B - C` |
| `ADDS` | 0 | 与 ADD 相同 | `B + C` |
| `ADDS` | 1 | 与 ADD 相同 | `B - C` |
| `MUL` | 0 | C 替换为规定符号的零 | `A*B` |

单格式模块中 `ADD` 与 `ADDS` 的数值行为完全一致；二者的差别只在多格式上层如何解释源格式。

### 7.3 ADD/ADDS 常量

ADD 或 ADDS 必须设置：

```text
operand_a.sign     = 0
operand_a.exponent = BIAS
operand_a.mantissa = 0

info_a.is_normal = 1
info_a.is_boxed  = 1
info_a 其他字段  = 0
```

即 A 精确等于 `+1.0`。

### 7.4 MUL 的加数零

MUL 必须覆盖之前对 C 做的符号修改，并设置：

```text
if rnd_mode == RDN:
    operand_c = +0
else:
    operand_c = -0

info_c.is_zero = 1
info_c.is_boxed= 1
info_c 其他字段= 0
```

该选择用于保证零乘积符号正确：

- RDN 下通过 `product + (+0)` 配合精确零规则产生正确符号；
- 其他舍入模式下通过 `product + (-0)` 保持乘积零的符号。

接口契约只定义 `MUL/op_mod=0`。当前数据通路会在 MUL 分支根据舍入模式将 C设置为正零或负零， `op_mod=1` 对结果没有实际影响，但调用方不应依赖未定义组合。

### 7.5 非法操作码

除 `FMADD`、`FNMSUB`、`ADD`、`ADDS`、`MUL` 之外的 `op_i` 对本模块无效。若无效操作仍以 `in_valid_i=1` 发射，则数值结果和状态为未定义；实现可以向内部操作数和分类传播综合无关值。

## 8. 派生控制信号

操作改写后必须计算：

```text
any_operand_inf = info_a.is_inf || info_b.is_inf || info_c.is_inf
any_operand_nan = info_a.is_nan || info_b.is_nan || info_c.is_nan
signalling_nan  = info_a.is_signalling || info_b.is_signalling || info_c.is_signalling

tentative_sign       = operand_a.sign ^ operand_b.sign
effective_subtraction= tentative_sign ^ operand_c.sign
```

`tentative_sign` 是乘积符号。`effective_subtraction==1` 表示乘积与加数 C 的符号不同，因此尾数路径必须执行绝对值减法。

## 9. 特殊值处理

### 9.1 默认值

特殊值组合逻辑默认必须设置：

```text
special_result = canonical_qNaN
special_status = 0
result_is_special = 0
```

canonical qNaN 编码必须为：

```text
sign     = 0
exponent = all_ones
fraction = 1 << (MAN_BITS-1)
```

### 9.2 优先级

特殊值判断必须严格使用下列从高到低的优先级。

该优先级不是为了任意选择一个“先匹配”的条件，也不只是为了避免多个条件同时驱动结果。它是浮点体系结构对重叠特殊值组合所规定语义的硬件化表达。FMA 是一次不可分割的浮点运算，同一组输入可能同时满足“乘数构成无穷乘零”“某个输入为 NaN”和“某个输入为无穷”等多个分类条件；实现必须按照体系结构规定，为整个输入组合确定唯一的结果和状态标志。

尤其是，[RISC-V F 扩展](https://docs.riscv.org/reference/isa/unpriv/f-st-ext.html)明确规定：融合乘加的两个乘数分别为无穷和零时必须置位 invalid operation，即使加数是 quiet NaN。因此，本模块必须让“无穷乘零”先于通常的 NaN 传播规则。RISC-V 默认采用 canonical NaN，本模块也因此输出固定的 canonical qNaN，而不传播输入 NaN 的 payload 或符号。

优先级不能任意交换。下列重叠组合说明了各层顺序的必要性：

| 重叠输入组合 | 必须采用的分支 | 结果 | `NV` | 若错误地采用较低优先级 |
|---|---|---|---:|---|
| `Inf * 0 + qNaN` | 无穷乘零 | canonical qNaN | 1 | 若先按 qNaN 处理，会错误地得到 `NV=0` |
| 任一有效输入为 sNaN，同时另一输入为无穷 | NaN | canonical qNaN | 1 | 若先传播无穷，会错误地输出无穷并丢失 `NV` |
| 任一有效输入为 qNaN，同时另一输入为无穷 | NaN | canonical qNaN | 0 | 若先传播无穷，会错误地输出无穷 |
| 无穷乘积与反号无穷 C 相加 | 无穷分支中的无效无穷抵消 | canonical qNaN | 1 | 若按普通无穷传播，会错误地输出无穷且不置 `NV` |

这里的“有效输入”是指经过第 7 章操作选择和操作数改写后仍参与当前操作的输入。例如，`ADD/ADDS` 已用 `+1.0` 替换 A，原始 A 的 NaN、无穷和 NaN-boxing 错误都不得参与本节判断；`MUL` 已用规定符号的零替换 C，原始 C 的特殊值同样不得参与判断。

#### 优先级 1：无穷乘零

条件：

```text
(info_a.is_inf && info_b.is_zero) ||
(info_a.is_zero && info_b.is_inf)
```

结果：

```text
result_is_special = 1
special_result    = canonical_qNaN
special_status.NV = 1
其他状态位         = 0
```

该条件优先于任何 C 的 NaN，包括 quiet NaN。

#### 优先级 2：任一输入为 NaN

条件：

```text
any_operand_nan == 1
```

结果：

```text
result_is_special = 1
special_result    = canonical_qNaN
special_status.NV = signalling_nan
其他状态位         = 0
```

不传播 NaN payload 和 NaN 符号。

#### 优先级 3：任一输入为无穷

首先判断无穷乘积与无穷加数的有效减法：

```text
(info_a.is_inf || info_b.is_inf) &&
info_c.is_inf &&
effective_subtraction
```

若成立：

```text
result_is_special = 1
special_result    = canonical_qNaN
special_status.NV = 1
```

否则，如果 A 或 B 为无穷，输出乘积符号的无穷：

```text
sign     = operand_a.sign ^ operand_b.sign
exponent = all_ones
fraction = 0
status   = 0
```

否则 C 必为无穷，输出 C 符号的无穷：

```text
sign     = operand_c.sign
exponent = all_ones
fraction = 0
status   = 0
```

### 9.3 `NV` 的完整置位规则

`NV` 表示 IEEE 754 invalid operation。它必须按照与第 9.2 节完全相同的优先级计算，而不能把各个候选条件简单地做逻辑 OR：

```text
if 无穷乘零:
    NV = 1
else if any_operand_nan:
    NV = signalling_nan
else if 无穷乘积与无穷 C 构成有效减法:
    NV = 1
else:
    NV = 0
```

不能简单 OR 的原因是：若存在 qNaN，同时由其余操作数的无穷分类和符号使第三层的无穷抵消候选条件也为真，NaN 分支仍必须先产生 canonical qNaN 且保持 `NV=0`；只有不存在任何 NaN、实际进入无穷处理分支时，无穷抵消条件才置位 `NV`。

因此，本模块中特殊值路径置位 `NV` 的情况只有：

1. 改写后的 A、B 构成 `Inf * 0` 或 `0 * Inf`；
2. 未命中上一条，并且任一改写后仍有效的操作数为 signalling NaN；
3. 未命中前两条，并且 A 或 B 使乘积为无穷、C 也为无穷，且乘积符号与 C 的符号相反。


### 9.4 RTL 中处理顺序的表达

本节存在两种不同的“顺序”，编码时必须分别表达：

1. **数据流顺序由信号依赖表达。** 原始操作数先由分类器产生 `info_q`；操作选择逻辑读取原始操作数和 `info_q`，产生改写后的 `operand_a/b/c` 和 `info_a/b/c`；派生控制信号及特殊值处理逻辑只能读取这些改写后的信号。其组合依赖关系为：

   ```text
   原始操作数/is_boxed
       -> 分类器 info_q
       -> 操作选择与操作数/分类改写
       -> operand_a/b/c、info_a/b/c
       -> 特殊值条件
       -> special_result、special_status、result_is_special
   ```

### 9.5 旁路要求

特殊值事务仍必须携带正确的 tag、mask、aux 和流水线 valid。常规有限数数据通路可以同时组合计算，但最终结果和状态必须由 `result_is_special` 选择特殊路径。

## 10. 常规路径：初始指数

下图将第 10～13 章中的指数计算、乘积布局、C 的对阶、sticky 生成、双路加法器、
绝对值与符号选择及内部流水切分点连成完整数据流。

![FPnew 单格式 FMA 指数、对阶与双路尾数加减](fig/fpnew_fma_arch_align_add.svg)

### 10.1 有符号容器

原始 exponent 必须先零扩展，再按 `EXP_WIDTH` 位有符号数参与运算：

```text
exponent_a = signed(zero_extend(operand_a.exponent))
exponent_b = signed(zero_extend(operand_b.exponent))
exponent_c = signed(zero_extend(operand_c.exponent))
```

不得直接把原始 exponent 当作 `EXP_BITS` 位有符号数。

### 10.2 加数内部指数

```text
exponent_addend = exponent_c + (!info_c.is_normal ? 1 : 0)
```

因此：

- normal C：使用编码指数 `E_c`；
- subnormal C：使用 1；
- zero C：也使用 1；
- 特殊值指数无须具有数学意义，因为结果会被特殊路径旁路。

### 10.3 乘积内部指数

```text
if info_a.is_zero || info_b.is_zero:
    exponent_product = 2 - BIAS
else:
    exponent_product = exponent_a
                     + (info_a.is_subnormal ? 1 : 0)
                     + exponent_b
                     + (info_b.is_subnormal ? 1 : 0)
                     - BIAS
```

所有加减必须在 `EXP_WIDTH` 位有符号域中完成，或使用更宽临时量后证明最终转换等价。

### 10.4 指数差与锚点指数

```text
exponent_difference = exponent_addend - exponent_product

if exponent_difference > 0:
    tentative_exponent = exponent_addend
else:
    tentative_exponent = exponent_product
```

指数差定义方向不可颠倒：正数表示 C 的指数更大。

## 11. 常规路径：尾数乘法和对阶

### 11.1 尾数构造

```text
mantissa_a = {info_a.is_normal, operand_a.mantissa}
mantissa_b = {info_b.is_normal, operand_b.mantissa}
mantissa_c = {info_c.is_normal, operand_c.mantissa}
```

每个尾数均为 `p` 位无符号数。

### 11.2 完整精度乘法

```text
product = mantissa_a * mantissa_b
```

`product` 必须为 `2p` 位。乘法结果不得截断、规格化或舍入。

### 11.3 乘积在对齐有效数加减域中的布局

定义 `SUM_WIDTH=3p+4`。乘积必须零扩展到 `SUM_WIDTH` 位并左移 2 位：

```text
product_shifted = zero_extend(product, SUM_WIDTH) << 2
```

位布局为：

```text
| p+2 个高位 0 | 2p 位 product | 2 个低位 0 |
```

低端两位为后续 round/sticky 精度预留。

### 11.4 C 的右移量

`addend_shamt` 为 `SHIFT_AMOUNT_WIDTH` 位无符号数，必须按下式饱和计算：

```text
if exponent_difference <= -(2p+1):
    addend_shamt = 3p+4
else if exponent_difference <= p+2:
    addend_shamt = p+3-exponent_difference
else:
    addend_shamt = 0
```

三种区域分别表示：

- product-anchored 且 C 极小：C 只影响 sticky；
- 乘积和 C 在对齐有效数加减域中有重叠；
- addend-anchored 且 C 极大：乘积只位于低端区域。

### 11.5 C 的对阶和 sticky

对阶必须等价于以下显式宽度算法，以避免移位表达式的语言宽度歧义：

```text
ADDEND_WIDE_WIDTH = 4p+4

addend_wide_before_shift = zero_extend(mantissa_c, 4p+4) << (3p+4)
addend_wide_after_shift  = addend_wide_before_shift >> addend_shamt

addend_after_shift = addend_wide_after_shift[4p+3 : p]  // 3p+4 位
addend_sticky_bits = addend_wide_after_shift[p-1 : 0]   // p 位
sticky_before_add  = OR-reduction(addend_sticky_bits)
```

等价的 SystemVerilog 连接赋值为：

```systemverilog
assign {addend_after_shift, addend_sticky_bits} =
    (mantissa_c << (3*p + 4)) >> addend_shamt;
```

但重写 RTL 时应显式控制中间表达式宽度为 `4p+4` 位。

`sticky_before_add` 不得直接写入 `addend_after_shift[0]`。它必须独立保存，并在减法补码进位和最终 sticky 计算中使用。

## 12. 常规路径：尾数加减和符号

### 12.1 加数取反和补码进位

```text
if effective_subtraction:
    addend_shifted = bitwise_not(addend_after_shift)
else:
    addend_shifted = addend_after_shift

inject_carry_in = effective_subtraction && !sticky_before_add
```

`inject_carry_in` 的 sticky 条件是数值正确性的必要部分：

- 被移出的低位全零时，保留部分的二补码需要 `+1`；
- 被移出的低位存在 1 时，完整负数的低位补码进位尚未越过截断边界，保留部分不得再加 1。

### 12.2 并行正和与反向差

两个操作数必须先零扩展到 `ADDER_WIDTH=SUM_WIDTH+1` 位。

```text
sum_pos = zero_extend(product_shifted, ADDER_WIDTH)
        + zero_extend(addend_shifted, ADDER_WIDTH)
        + inject_carry_in

sum_carry = sum_pos[SUM_WIDTH]

sum_neg = zero_extend(addend_after_shift, ADDER_WIDTH)
        - zero_extend(product_shifted, ADDER_WIDTH)
```

`sum_pos` 在有效加法时表示 `|A*B|+|C|`；在有效减法时，其低 `SUM_WIDTH` 位表示 `|A*B|-|C|` 的补码结果，`sum_carry` 用于判断大小关系，若`sum_carry = 1`，则乘积尾数`不小于`加数尾数；若`sum_carry = 0`，则乘积尾数`小于`加数尾数。

### 12.3 绝对值选择

```text
if effective_subtraction && !sum_carry:
    sum = sum_neg[SUM_WIDTH-1:0]
else:
    sum = sum_pos[SUM_WIDTH-1:0]
```

有效减法中：

- `sum_carry==1` 表示乘积绝对值不小于 C 的绝对值；
- `sum_carry==0` 表示 C 的绝对值更大，此时选择 `C-product`；
- 相等时按 `sum_carry==1` 路径产生精确零。

有效加法不应溢出 `SUM_WIDTH` 的有效范围，额外 carry 位只用于减法大小判断。

### 12.4 最终未舍入符号

必须实现与下式等价的逻辑：

```text
// addition occurs
if !effective_subtraction:
    final_sign = tentative_sign
// substraction occurs
else if sum_carry == tentative_sign:
    final_sign = 1
else:
    final_sign = 0
```

在有效减法情况下，也可理解为：

```text
sum_carry==1, product is bigger: final_sign = tentative_sign
sum_carry==0, addend is bigger: final_sign = !tentative_sign
```

精确零时该符号只是暂定值；最终舍入模块必须按第 15.4 节修正零符号。

## 13. 内部流水线切分点

内部流水线位于尾数加减之后、前导零检测和规格化之前。

进入内部流水线的 payload 必须包含：

```text
effective_subtraction
exponent_product
exponent_difference
tentative_exponent
addend_shamt
sticky_before_add
sum
final_sign
rnd_mode
result_is_special
special_result
special_status
tag
mask
aux
valid
```

原始操作数、完整乘积和分类信息不需要跨过此切分点。

若 `NUM_MID_REGS==0`，以上信号直接组合连接到规格化路径。若大于零，则按第 18 节的统一弹性流水规则传递。

## 14. 规格化

下图将第 14～17 章中的 LZC、规格化移位量、大移位与小规格化、`R/S/T`、
`fpnew_rounding`、OF/UF/NX 生成及 special/regular 结果选择连成完整数据流。图的下半部
单独展开了从 subnormal 舍入到最小 normal 时的 tininess-after-rounding 判断。

![FPnew 单格式 FMA 规格化、舍入与状态位](fig/fpnew_fma_arch_norm_round.svg)

### 14.1 前导零检测输入

只对 `sum` 的低 `LOWER_SUM_WIDTH=2p+3` 位进行前导零检测：

```text
sum_lower = sum[2p+2 : 0]
```

LZC 必须从 `sum_lower` 的最高位向最低位计数：

```text
leading_zero_count = sum_lower 中首个 1 之前的 0 的个数
lzc_zeroes         = (sum_lower == 0)
```

`leading_zero_count` 使用 `LZC_RESULT_WIDTH` 位无符号数；参与指数计算前必须零扩展一位并转为有符号数：

```text
leading_zero_count_sgn = signed({1'b0, leading_zero_count})
```

### 14.2 大规格化移位量

首先判定是否需要 product-anchored/cancellation 路径：

```text
use_product_anchor =
    (exponent_difference <= 0) ||
    (effective_subtraction && exponent_difference <= 2)
```

若 `use_product_anchor==1`，再判定结果是否可按正常路径定位：

```text
normal_candidate =
    (exponent_product - leading_zero_count_sgn + 1 >= 0) &&
    !lzc_zeroes
```

若为正常候选：

```text
norm_shamt = p + 2 + leading_zero_count
normalized_exponent = exponent_product - leading_zero_count_sgn + 1
```

否则按 subnormal/zero 路径：

```text
norm_shamt = unsigned(p + 2 + exponent_product)
normalized_exponent = 0
```

其中右式必须先按有符号数求和，再转换为 `SHIFT_AMOUNT_WIDTH` 位无符号移位量，与参考 RTL 的定宽转换一致。

若 `use_product_anchor==0`，使用 addend-anchored 路径：

```text
norm_shamt = addend_shamt
normalized_exponent = tentative_exponent
```

### 14.3 大移位

`sum` 必须先零扩展到 `ADDER_WIDTH=SUM_WIDTH+1` 位，再左移：

```text
sum_shifted = zero_extend(sum, ADDER_WIDTH) << norm_shamt
```

### 14.4 小规格化

定义：

```text
final_mantissa  宽度 = p+1
sum_sticky_bits 宽度 = 2p+3
```

两者连接后的总宽度为 `SUM_WIDTH=3p+4`。默认丢弃 `sum_shifted` 的额外最高位：

```text
{final_mantissa, sum_sticky_bits} = sum_shifted[SUM_WIDTH-1:0]
final_exponent = normalized_exponent
```

随后按以下优先级修正。

#### 情况 1：规格化结果产生额外 carry

```text
if sum_shifted[SUM_WIDTH] == 1:
    {final_mantissa, sum_sticky_bits} =
        (sum_shifted >> 1)[SUM_WIDTH-1:0]
    final_exponent = normalized_exponent + 1
```

#### 情况 2：最高有效位置已经为 1

```text
else if sum_shifted[SUM_WIDTH-1] == 1:
    保持默认值
```

#### 情况 3：还需要左移一位，且结果尚非 subnormal

```text
else if normalized_exponent > 1:
    {final_mantissa, sum_sticky_bits} =
        (sum_shifted << 1)[SUM_WIDTH-1:0]
    final_exponent = normalized_exponent - 1
```

#### 情况 4：结果为 subnormal 或零

```text
else:
    保持默认尾数分割
    final_exponent = 0
```

### 14.5 最终 sticky

```text
sticky_after_norm = OR-reduction(sum_sticky_bits) || sticky_before_add
```

不得遗漏对阶阶段产生的 `sticky_before_add`。

## 15. 舍入

### 15.1 舍入前分类与打包

舍入前溢出条件：

```text
of_before_round = final_exponent >= 2^EXP_BITS - 1
```

参考实现还计算：

```text
uf_before_round = (final_exponent == 0)
```

该信号不直接参与最终状态，可以作为内部诊断信号省略。

舍入前符号：

```text
pre_round_sign = final_sign
```

若 `of_before_round==0`：

```text
pre_round_exponent = final_exponent[EXP_BITS-1:0]
pre_round_mantissa = final_mantissa[MAN_BITS:1]
round_bit          = final_mantissa[0]
sticky_bit         = sticky_after_norm
```

`final_mantissa` 的位含义为：

```text
[p]                 规格化隐含位，不写入 fraction
[p-1 : 1]           MAN_BITS 位待输出 fraction
[0]                  round bit
```

若 `of_before_round==1`，必须先构造最大有限值并强制舍入信息：

```text
pre_round_exponent = 2^EXP_BITS - 2
pre_round_mantissa = all_ones
round_bit          = 1
sticky_bit         = 1
```

最后：

```text
pre_round_abs = {pre_round_exponent, pre_round_mantissa}
RS            = {round_bit, sticky_bit}
```

`pre_round_abs` 宽度为 `EXP_BITS+MAN_BITS`，不包含 sign 和隐含位。

### 15.2 舍入模式与舍入增量

定义保留结果最低位：

```text
LSB = pre_round_abs[0]
inexact_remainder = round_bit || sticky_bit
```

`LSB` 是 Least Significant Bit，即保留结果的最低位。`RS` 中的 R 是 round bit，S 是 sticky bit。本节使用的舍入模式缩写和编码如下：

| 编码 | 缩写 | 英文原文 | 含义 |
|---:|---|---|---|
| `000` | RNE | Round to Nearest, ties to Even | 舍入到最近的可表示值；恰好位于两个可表示值中间时，选择保留结果 LSB 为 `0` 的值 |
| `001` | RTZ | Round Toward Zero | 向零方向舍入，直接丢弃未保留位 |
| `010` | RDN | Round Down, toward Negative Infinity | 向负无穷方向舍入 |
| `011` | RUP | Round Up, toward Positive Infinity | 向正无穷方向舍入 |
| `100` | RMM | Round to Nearest, ties to Maximum Magnitude | 舍入到最近的可表示值；恰好居中时，选择绝对值较大的值，即远离零 |
| `101` | ROD | Round to Odd | 如果被舍弃部分非零，则使保留结果的 LSB 为 `1`；该模式是本仓库的扩展，`fpnew_pkg` 明确标注其不属于 RISC-V FP-SPEC 定义的舍入模式 |
| `111` | DYN | Dynamic Rounding Mode | 动态舍入模式编码，它不是具体舍入算法；调用方必须在进入本单元前将其解析为其他合法静态模式 |

`round_up` 表示是否对不包含 sign 的 `pre_round_abs` 加 `1`，即增加一个当前保留精度的 ulp（unit in the last place）。它不能一律理解为浮点数值向正方向增大：对负数而言，绝对值加 `1` 使结果更负。

`round_up` 必须按下表产生：

| 舍入模式 | `round_up` |
|---|---|
| RNE | `RS==10 ? LSB : RS==11 ? 1 : 0` |
| RTZ | `0` |
| RDN | `inexact_remainder && pre_round_sign` |
| RUP | `inexact_remainder && !pre_round_sign` |
| RMM | `round_bit` |
| ROD | `!LSB && inexact_remainder` |

RNE 的完整 `{R,S}` 行为为：

| `RS` | 含义 | `round_up` |
|---|---|---:|
| 00 | 精确 | 0 |
| 01 | 小于半个 ulp | 0 |
| 10 | 恰好半个 ulp | `LSB`，得到偶数 |
| 11 | 大于半个 ulp | 1 |

`DYN` 和其他非法编码不在本单元内解析，结果为未定义。调用方必须在进入本单元前把动态舍入模式解析成合法静态模式。

### 15.3 执行舍入

```text
rounded_abs = pre_round_abs + round_up
```

加法宽度必须保持为 `EXP_BITS+MAN_BITS`。fraction 进位到 exponent、最大有限数进位到 infinity 都由该无符号加法自然完成。

### 15.4 精确零符号

```text
exact_zero = (pre_round_abs == 0) && (RS == 00)
```

最终符号：

```text
if exact_zero && effective_subtraction:
    rounded_sign = (rnd_mode == RDN)
else:
    rounded_sign = pre_round_sign
```

因此有效减法精确抵消时：

- RDN 输出 `-0`；
- 其他合法模式输出 `+0`。

非有效减法得到的零保留 `pre_round_sign`，用于同号零相加和零乘积场景。

## 16. 舍入后分类和状态标志

### 16.1 exponent 切片

```text
pre_exp     = pre_round_abs[EXP_BITS+MAN_BITS-1 : MAN_BITS]
rounded_exp = rounded_abs [EXP_BITS+MAN_BITS-1 : MAN_BITS]
```

### 16.2 舍入后 overflow

```text
of_after_round = (rounded_exp == all_ones)
```

### 16.3 舍入后 underflow 判定

本模块采用 tininess-after-rounding（舍入后微小性检查）生成
underflow 状态。该检查不能简化为“最终结果是 subnormal 时才是
tiny”，因为在最大 subnormal 与最小 normal 之间，一个按 `p` 位有效
数字舍入后仍然小于最小 normal 的结果，可能通过实际 subnormal 的按`p-1`位有效数字舍入进位而得到最小 normal 编码。

#### 16.3.1 舍入后微小性检查的对象

设精确数学结果为 `x`，`p = MAN_BITS+1`。舍入后微小性检查按以下顺序
理解：

1. 暂时允许 exponent 小于 `emin`；
2. 使用当前 `rnd_mode`，将 `x` 按 normal 的 `p` 位有效数字舍入；
3. 检查上述 `p` 位舍入结果是否仍严格小于最小 normal：

```text
minimum_normal = 1.000...000 * 2^emin
```

若非零的 `p` 位舍入结果仍小于 `minimum_normal`，则结果是 tiny。

暂时允许 exponent 小于 `emin` 的目的，是在判断 tiny 前仍然保留 normal
的 `p` 位有效数字。如果先把 exponent 限制在目标格式的取值范围内，小于
最小 normal 的数只能使用 subnormal 编码；在此边界上只能保留 fraction
中的 `p-1` 位有效数字，原本的第 `p` 位有效数字会被当成 round bit。
这种 subnormal 舍入可能进位到最小 normal，从而使最终编码无法单独说明
按 `p` 位有效数字舍入后的结果是否仍然 tiny。

`rounded_abs` 仍然是按目标格式生成的正确最终结果。上述 exponent 不受下限
约束的假设只用于微小性检查，不用于生成输出编码。RTL 也不需要真正执行
第二次舍入，而是通过 `R`、`S`、`T` 和 `rnd_mode` 直接得到等价的判断结果。

#### 16.3.2 `R`、`S` 和 `T`

```text
R = round_sticky_bits[1] = final_mantissa[0]
S = round_sticky_bits[0] = sticky_after_norm
T = sum_sticky_bits[2*MAN_BITS + 4]
```

`sum_sticky_bits[2*MAN_BITS+4]` 是 `sum_sticky_bits` 的最高位，因为：

```text
width(sum_sticky_bits) = 2p+3 = 2*MAN_BITS+5
```

`T` 是紧接在 `R` 之后的位；`S` 则是 `T`、`T` 之后的所有位以及
`sticky_before_add_q` 的 OR 结果：

```text
S = T
  | OR(sum_sticky_bits[2*MAN_BITS+3 : 0])
  | sticky_before_add_q
```

#### 16.3.3 舍入后 exponent 仍为零

```text
rounded_exp == 0
```

最终编码为 zero 或 subnormal。RTL 在此情形下直接置位 `uf_after_round`。
最终 `UF` 还要与 `NX` 相与，因此：

- 不精确舍入得到的 zero 或 subnormal 置位 `UF`；
- 精确 zero 和精确 subnormal 的 `NX=0`，不置位 `UF`。

#### 16.3.4 从 subnormal 进位到最小 normal

边界情形为：

```text
(pre_exp == 0) && (rounded_exp == 1)
```

由于 `rounded_abs = pre_round_abs + round_up`，exponent 从零变为一意味着
`pre_round_mantissa` 全为 `1` 且 `round_up=1`。因此最终结果正好是最小
normal。但该进位仅由实际 subnormal 舍入使用 `p-1` 位有效数字所导致，
所以还需要判断按 `p` 位有效数字舍入时能否产生同样的进位。

在实际 subnormal 舍入中，位序列可写为：

```text
 0.[p-1 位全 1] | R | T lower...  * 2^emin
```

暂时允许 exponent 小于 `emin` 并将该序列左移一位：

```text
 1.[p-2 位全 1] R | T | lower... * 2^(emin-1)
```

此时原来的 `R` 成为第 `p` 位有效数字，原来的 `T` 成为新的 round bit。
然后根据当前 `rnd_mode` 判断这 `p` 位有效数字能否进位：

- 若舍入使全 `1` 的 `p` 位有效数字进位为
  `10.000...000 * 2^(emin-1) = 1.000...000 * 2^emin`，则不 tiny；
- 若不产生该进位，结果仍为 `1.xxx...xxx * 2^(emin-1)`，严格小于
  最小 normal，因此仍然 tiny。

边界情形中的判断式为：

```text
boundary_is_tiny =
    (RS != 2'b11)
    || (!T && (rnd_mode == RNE || rnd_mode == RMM))
```

各项条件的原因如下：

- `RS=00`：在 `pre_exp==0 && rounded_exp==1` 的前提下实际不可达，因为没有需要
  舍入的非零位，`round_up` 不可能为一。`RS!=11` 在布尔表达式中对它的
  覆盖不影响可达输入的结果；
- `RS=01`：左移后的第 `p` 位有效数字 `R` 为零。即使舍入加一，也只会
  将该位从零变为一，不会使整个 `p` 位尾数进位，因此 tiny；
- `RS=10`：左移后保留的 `p` 位全为一，但 `S=0` 说明 `T` 和之后的所有位
  均为零。这个 `p` 位结果是精确的，不会加一，因此 tiny；
- `RS=11`：左移后保留的 `p` 位全为一，并且其后存在非零位。对于
  RNE 和 RMM，`T` 是新的 round bit：
  - `T=0` 表示小于半个 `p` 位结果的 ulp，不加一，因此 tiny；
  - `T=1` 表示恰好等于或大于半个 ulp。RNE 在恰好一半时因保留结果的
    LSB（即 `R`）为一而加一，RMM 也加一；全一结果因此产生进位，
    结果达到最小 normal，不 tiny。

对于 RUP 或 RDN，只有向绝对值增大的方向舍入才能使该边界情形的
`rounded_exp` 从零变为一。当 `RS=11` 时，该舍入同样会对左移后的全一
`p` 位结果加一，所以不 tiny。RTZ 不加一；ROD 在
`pre_round_mantissa` 全一时也不加一，因此它们不会进入该 exponent 从零变为一
的边界情形。

#### 16.3.5 RTL 表达式

完整实现必须使用以下表达式，而不能只判断舍入后 exponent 是否为零：

```text
uf_after_round =
    (rounded_exp == 0)
    ||
    (
      (pre_exp == 0)
      && (rounded_exp == 1)
      &&
      (
        (RS != 2'b11)
        ||
        (
          !sum_sticky_bits[2*MAN_BITS + 4]
          && (rnd_mode == RNE || rnd_mode == RMM)
        )
      )
    )
```

### 16.4 常规路径状态

状态位必须按下式生成：

```text
regular_status.NV = 0
regular_status.DZ = 0
regular_status.OF = of_before_round || of_after_round
regular_status.NX = (round_bit || sticky_bit)
                  || of_before_round
                  || of_after_round
regular_status.UF = uf_after_round && regular_status.NX
```

要求：

- FMA 永远不置 `DZ`；
- 精确 zero 和精确 subnormal 不置 `UF`，因为 `UF` 必须与 `NX` 同时成立；
- overflow 必须同时置 `OF` 和 `NX`；
- 常规有限路径不置 `NV`。

### 16.5 常规结果

```text
regular_result = {rounded_sign, rounded_abs}
```

## 17. 最终结果选择

在内部流水线之后，必须按事务对应的 `result_is_special` 选择：

```text
if result_is_special:
    result_d = special_result
    status_d = special_status
else:
    result_d = regular_result
    status_d = regular_status
```

特殊路径的状态不得与常规路径状态做 OR。例如 signalling NaN 事务只能输出特殊路径规定的 `NV`，不得附带常规路径组合计算产生的 OF、UF 或 NX。

## 18. 弹性流水线

### 18.1 通用一级结构

输入、内部和输出三个流水区都必须使用相同的弹性级规则。对某一区域的第 `i` 个寄存器，数组索引 `i` 表示寄存器之前的信号，`i+1` 表示寄存器之后的信号。

组合 ready：

```text
ready[i] = ready[i+1] || !valid_q[i+1]
```

含义是：

- 后一级能继续前进时，本级可覆盖后一级；
- 后一级当前是 bubble 时，本级也可写入；
- 后一级持有有效数据且不能前进时，本级必须停顿。

### 18.2 valid 寄存器

每个 valid 寄存器必须：

- 在 `rst_ni==0` 时异步清零；
- 在上升沿 `flush_i==1` 时同步清零，flush 优先于普通装载；
- 否则在 `ready[i]==1` 时装载 `valid_q[i]`；
- 在 `ready[i]==0` 时保持。

等价伪代码：

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)
    valid_q[i+1] <= 1'b0;
  else if (flush_i)
    valid_q[i+1] <= 1'b0;
  else if (ready[i])
    valid_q[i+1] <= valid_q[i];
end
```

### 18.3 payload 寄存器

第 `i` 个物理寄存器对应的全局 `reg_ena_i` 索引定义为：

```text
输入区第 i 级: reg_index = i
内部区第 i 级: reg_index = NUM_INP_REGS + i
输出区第 i 级: reg_index = NUM_INP_REGS + NUM_MID_REGS + i
```

payload 装载使能：

```text
payload_enable = (ready[i] && valid_q[i]) || reg_ena_i[reg_index]
```

payload 在 `payload_enable==1` 时装载前一级数据，否则保持。`reg_ena_i` 不得改变 valid 寄存器。

正常集成时 `reg_ena_i` 应绑为零。若外部强制使能在一个被反压的有效级上更新 payload，外部必须自行保证事务稳定性；否则会破坏 valid/ready 协议。

### 18.4 输入流水区 payload

输入流水区必须携带：

```text
operands[2:0]
is_boxed[2:0]
rnd_mode
op
op_mod
tag
mask
aux
valid
```

区域入口：

```text
inp[0].payload = 模块输入
inp[0].valid   = in_valid_i
in_ready_o     = inp_ready[0]
```

区域末端 ready 连接内部区入口：

```text
inp_ready[NUM_INP_REGS] = mid_ready[0]
```

### 18.5 输出流水区 payload

输出流水区必须携带：

```text
result
status
tag
mask
aux
valid
```

连接关系：

```text
out[0].result = result_d
out[0].status = status_d
out[0].tag    = mid_end.tag
out[0].mask   = mid_end.mask
out[0].aux    = mid_end.aux
out[0].valid  = mid_end.valid

mid_ready[NUM_MID_REGS] = out_ready[0]
out_ready[NUM_OUT_REGS]  = out_ready_i
```

模块输出取输出区最后一个元素。

### 18.6 reset payload 值

为与参考实现保持结构兼容，寄存器异步复位值应为：

- operands、boxing、op_mod、mask、普通逻辑和状态：零；
- rounding mode：RNE；
- operation：FMADD；
- tag：`TagType'('0)`；
- aux：`AuxType'('0)`。

valid 为零时 payload 不具有功能意义，因此等价实现可以使用其他安全复位值，但不得改变 valid、busy 或接口行为。

## 19. 输出辅助信号

### 19.1 NaN-box 扩展位

```text
extension_bit_o = 1
```

该单元始终产生浮点结果；上层在把窄格式 lane 扩展到更宽数据通路时使用 1 填充高位。

### 19.2 tag、mask 和 aux

三个旁带字段不得被 FMA 修改：

```text
tag_o  = 与 result_o 同一事务的 tag_i
mask_o = 与 result_o 同一事务的 mask_i
aux_o  = 与 result_o 同一事务的 aux_i
```

`mask_i` 不抑制本模块内部运算或状态生成。上层 slice 在合并 SIMD lane 状态时才使用 `mask_o`。

### 19.3 busy

```text
busy_o = OR-reduction(
    所有输入区 valid 元素,
    所有内部区 valid 元素,
    所有输出区 valid 元素
)
```

数组索引 0 是组合入口，因此当 `in_valid_i==1` 时，即使还未完成输入握手，`busy_o` 也可以为 1。当所有寄存器数为零时，`busy_o` 等价于组合事务 valid。

### 19.4 flush

`flush_i` 只同步清除实际存在的流水 valid 寄存器，不要求清除 payload。若 `NumPipeRegs==0`，模块内部没有可清除状态，因此 `flush_i` 对组合 `out_valid_o` 和结果没有直接作用；上层必须负责不把被 flush 的组合事务当成有效提交。

### 19.5 反压下输出稳定性

当：

```text
out_valid_o==1 && out_ready_i==0
```

且 `reg_ena_i` 未违规强制覆盖时，以下信号必须保持稳定直到输出握手或 flush/reset：

```text
result_o, status_o, tag_o, mask_o, aux_o, out_valid_o
```

### 19.6 early_out_valid

参考实现按照最靠近输出端且实际存在的流水区生成该信号。

若存在输出寄存器：

```text
early_out_valid_o =
    (out_valid[NUM_OUT_REGS] && !out_ready[NUM_OUT_REGS])
    || out_valid[NUM_OUT_REGS-1]
```

若不存在输出寄存器但存在内部寄存器，当前 RTL 的逐位兼容表达式为：

```text
early_out_valid_o =
    (mid_valid[NUM_MID_REGS] && !mid_ready[NUM_OUT_REGS])
    || mid_valid[NUM_MID_REGS-1]
```

该分支中 `NUM_OUT_REGS==0`，因此当前实现实际读取 `mid_ready[0]`。从“末级停顿或倒数第二级有效”的接口意图看，使用 `mid_ready[NUM_MID_REGS]` 更自然；这是当前 RTL 的一个兼容性注意点。若目标是 bit-for-bit 复刻当前实现，应使用上式；若目标是重新定义并修正 early-valid 协议，应单独评审后同步修改规格、RTL 和验证环境。该差异不影响数值结果和 `out_valid_o`。

若只有输入寄存器：

```text
early_out_valid_o =
    (inp_valid[NUM_INP_REGS] && !inp_ready[NUM_INP_REGS])
    || inp_valid[NUM_INP_REGS-1]
```

若没有任何寄存器：

```text
early_out_valid_o = 0
```

## 21. 与上层集成的约束

本模块通常由 `fpnew_opgroup_fmt_slice` 的一个 lane 实例化。上层必须保证：

- 只把 `FpFormat` 对应宽度的 lane 数据送入本模块；
- 标量窄格式的 `is_boxed_i` 已由顶层检查；
- SIMD lane 输入的 boxing 位按架构要求置为有效；
- 只发射 ADDMUL 操作组支持的操作码；
- `rnd_mode_i` 已解析，不把 DYN 直接送入数值核心；
- mask 只用于上层合并状态，本模块仍计算被 mask lane；
- 若多个格式或操作组存在不同延迟，上层使用 tag 识别返回事务；
- 单格式 `PARALLEL` 实例不用于 `src_fmt != dst_fmt` 的混合格式 FMA。


