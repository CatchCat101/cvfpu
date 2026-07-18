# FPnew 单格式并行 FMA 微架构规格

## 1. 文档目的与适用范围

本文档规定 FPnew `ADDMUL` 操作组中单格式并行 FMA 单元的功能、接口、位宽、组合数据通路、特殊值处理、规格化、舍入、状态标志和弹性流水线行为。目标是使实现者仅依据本文档即可重新编码出与当前 `fpnew_fma` RTL 数值行为和时序接口兼容的 SystemVerilog 模块。

本文档对应以下实现：

- 主模块：[`../src/fpnew_fma.sv`](../src/fpnew_fma.sv)
- 输入分类：[`../src/fpnew_classifier.sv`](../src/fpnew_classifier.sv)
- 舍入单元：[`../src/fpnew_rounding.sv`](../src/fpnew_rounding.sv)
- 公共类型及格式定义：[`../src/fpnew_pkg.sv`](../src/fpnew_pkg.sv)

本文档只规定 `PARALLEL` 路径中的单格式 FMA。所有有效浮点操作数和结果都使用同一个参数化格式 `FpFormat`。混合源/目标格式 FMA、格式间指数重偏置和 super-format 数据通路属于 `fpnew_fma_multi`，不在本文档范围内。

本文档使用以下规范用语：

- “必须”：为获得兼容行为所必需。
- “应”：强烈建议遵守；偏离时必须证明接口和数值行为等价。
- “可以”：不影响规定行为的实现选择。
- “未定义”：调用方不得依赖其值，实现可以输出任意值或综合无关值。

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
zero:      数学值为零，内部指数按后文的专用规则赋值
```
问题：这里零的内部指数是零；而真实指数值不确定

有限非零数的数学值为：

```text
value = (-1)^sign * M * 2^(e-(p-1))
```
问题：这里的指数为什么不是 e 呢？

$ value = (-1)^{sign} \times M \times 2^{e}$

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
PRECISION_BITS    = MAN_BITS + 1
LOWER_SUM_WIDTH   = 2*PRECISION_BITS + 3
LZC_RESULT_WIDTH  = ceil(log2(LOWER_SUM_WIDTH))
EXP_WIDTH         = max(EXP_BITS + 2, LZC_RESULT_WIDTH)
SHIFT_AMOUNT_WIDTH= ceil(log2(3*PRECISION_BITS + 5))
SUM_WIDTH         = 3*PRECISION_BITS + 4
ADDER_WIDTH       = SUM_WIDTH + 1
```

其中：

- `EXP_WIDTH` 的信号必须按二进制补码有符号数解释；
- `SHIFT_AMOUNT_WIDTH` 的信号必须按无符号数解释；
- `SUM_WIDTH` 是 `product_shifted`、`addend_after_shift`、`addend_shifted` 和 `sum` 的宽度；
- `ADDER_WIDTH` 是 `sum_pos`、`sum_neg` 和 `sum_shifted` 的宽度。

以下说明使用 `p=PRECISION_BITS`，并将 `SUM_WIDTH` 位的定点向量称为“对齐有效数加减域”。它是将完整乘积与 C 对阶后执行加减的公共位坐标，不是最终浮点结果的尾数字段。

#### 4.2.1 `PRECISION_BITS`

浮点编码只保存 `MAN_BITS` 位小数字段（fraction）。正规数还有一个未存储的隐含最高位 `1`，子正规数在同一位置使用 `0`：

```text
正规数有效数:   {1'b1, fraction}
子正规数有效数: {1'b0, fraction}
```

所以参与乘法和加法的完整有效数宽度为：

```text
PRECISION_BITS = MAN_BITS + 1 = p
```

#### 4.2.2 `SUM_WIDTH` 以及高端 `p+2` 位的来源

两个 `p` 位有效数相乘产生未经截断的 `2p` 位乘积。乘积在对齐有效数加减域中左移 2 位：

```text
| p+2 个高端空位 | 2p 位 product | 2 个低端精度预留位 |
```

因此：

```text
SUM_WIDTH = (p+2) + 2p + 2 = 3p+4
```

最低两位来自 `product << 2`，用于保留对阶和规格化后形成舍入判定位与粘滞信息（round/sticky）所需的低端精度。高端 `p+2` 位不是“C 的 `p` 位加两个与最低两位相同的舍入位”。它由 C 即将成为对阶指数基准时的极限布局决定。

当：

```text
exponent_difference = p+2
```

中间区域公式给出：

```text
addend_shamt = p+3-(p+2) = 1
```

此时 `SUM_WIDTH` 位域的布局为：

```text
bit  3p+3 | 3p+2 ........ 2p+3 | 2p+2 | 2p+1 ...... 2 | 1:0
           |                       |       |               |
   规格化最高位预留位置   C 的 p 位有效数    C 下方   2p 位 product   低端精度位
                                           精度位
```

所以 product 上方的 `p+2` 位可按该边界布局理解为：

```text
p+2 = 1 位规格化最高位预留位置 + p 位 C 有效数 + 1 位 C 下方低端精度位置
```

其中 C 下方的低端位置在 C 决定结果量级时充当首个舍入判定位置（round/guard），更低的乘积位汇入粘滞信息（sticky）。最高的一位为后续一位规格化调整预留位置；它不是加减器的 `sum_carry`。真正的进位/借位观察位由 `ADDER_WIDTH` 额外提供。

当指数差减小时，C 在此固定宽度域中向低位移动并与 `product` 重叠；当指数差大于 `p+2` 时，C 成为对阶指数基准，`product` 只影响低位精度和粘滞信息。

#### 4.2.3 `LOWER_SUM_WIDTH` 与 `LZC_RESULT_WIDTH`

`product` 为 `2p` 位，左移 2 位后最高可能位于 `sum[2p+1]`。与已对阶的 C 相加时还可能在其上方形成一位，因此 product-anchored 和有效数抵消路径需要检查：

```text
sum[2p+2:0]
```

该区域宽度为：

```text
LOWER_SUM_WIDTH = 2p+3
```

当 C 明显决定结果量级时，规格化位置由 `addend_shamt` 决定，不需要对更高的 C 所在区域执行前导零计数。只对低 `2p+3` 位使用 LZC 可以缩短前导零计数器的数据通路。

非零输入的前导零数量范围是：

```text
0 ... LOWER_SUM_WIDTH-1
```

全零情况由独立的 `lzc_zeroes` 信号表示，所以计数输出只需：

```text
LZC_RESULT_WIDTH = ceil(log2(LOWER_SUM_WIDTH))
```

#### 4.2.4 `EXP_WIDTH` 以及 LZC 大于乘积指数的情况

内部指数不仅保存原始 exponent，还要计算：

```text
exponent_product    = exponent_a + exponent_b - BIAS
exponent_difference = exponent_addend - exponent_product
normalized_exponent = exponent_product - leading_zero_count + 1
```

`EXP_BITS+2` 提供一个符号位和一个指数相加的增长位，使负指数差、低于最小正规数的中间指数以及两个原始 exponent 相加后的值都不会发生截断。`LZC_RESULT_WIDTH` 则保证指数规格化判断能够处理与前导零计数相同量级的修正。因此参考 RTL 取：

```text
EXP_WIDTH = max(EXP_BITS+2, LZC_RESULT_WIDTH)
```

`leading_zero_count` 与 `exponent_product` 没有前者必须较小的关系：前者是 `sum_lower` 固定位坐标中的零数量，后者是带偏置的乘积指数基准。由于 `sum_lower` 在 `product` 最高位以上本来就有结构性空位，没有抵消时 LZC 通常也为 1 或 2；而接近下溢边界时 `exponent_product` 可能只有 1、0 或负值。发生近似相等数相减时，抵消还会令 LZC 显著增加。

例如 FP32 中：

```text
A = 2^-126                         // 最小正规数
B = 1.0
C = -(2^-126 - 2^-149)            // 最大子正规数取负
```

精确结果为 `2^-149`，即最小子正规数。此时：

```text
p                  = 24
exponent_product   = 1
product_shifted    = 2^48
addend_after_shift = 2^48 - 2^25
sum                = 2^25
leading_zero_count = 25            // 在 sum_lower[50:0] 中计数
```

RTL 实际判断的是：

```text
exponent_product - leading_zero_count + 1 >= 0
```

而不是简单比较 `leading_zero_count <= exponent_product`。若该表达式为负，完全消除前导零会要求负的带偏置指数（biased exponent），结果必须进入子正规数/零路径：

```text
normalized_exponent = 0
norm_shamt = p+2+exponent_product
```

这会把左移量限制在最小指数边界，未能消除的前导零保留在最终 fraction 中。`leading_zero_count` 转成有符号值时必须先补一个零符号位，避免将其最高有效位误解释为负号。

#### 4.2.5 `SHIFT_AMOUNT_WIDTH`

`addend_shamt` 和 `norm_shamt` 都是无符号左/右移量，最大合法值为整个 `SUM_WIDTH`：

```text
maximum shift amount = 3p+4
```

需要编码包含零在内的 `0 ... 3p+4`，共 `3p+5` 个值，因此：

```text
SHIFT_AMOUNT_WIDTH = ceil(log2(3p+5))
```

这里的 `+5` 表示移位量可取值的数量，不表示数据通路额外增加 5 位。

#### 4.2.6 `ADDER_WIDTH`

乘积和 C 在 `SUM_WIDTH` 位域中对阶，但加减器必须额外保留一个最高位：

```text
ADDER_WIDTH = SUM_WIDTH+1
```

该位用于：

- 在补码减法中通过 `sum_carry` 判断 `|A*B|` 与 `|C|` 的大小；
- 保留加减法临时进位/借位；
- 在规格化移位后检测结果是否进入额外最高位，并据此右移一位、指数加一。

最终 `sum` 仍只保留低 `SUM_WIDTH` 位；额外最高位属于控制和规格化信息，不属于最终有效数字段。

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

接口契约只定义 `MUL/op_mod=0`。当前数据通路会在 MUL 分支覆盖 C，因此 `op_mod=1` 对结果没有实际影响，但调用方不应依赖未定义组合。

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

### 9.3 旁路要求

特殊值事务仍必须携带正确的 tag、mask、aux 和流水线 valid。常规有限数数据通路可以同时组合计算，但最终结果和状态必须由 `result_is_special` 选择特殊路径。

## 10. 常规路径：初始指数

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

`sum_pos` 在有效加法时表示 `|A*B|+|C|`；在有效减法时，其低 `SUM_WIDTH` 位表示 `|A*B|-|C|` 的补码结果，`sum_carry` 用于判断大小关系。

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

有效加法不应溢出 `SUM_WIDTH` 的有效范围，额外 carry 位只用于统一宽度和减法大小判断。

### 12.4 最终未舍入符号

必须实现与下式等价的逻辑：

```text
if !effective_subtraction:
    final_sign = tentative_sign
else if sum_carry == tentative_sign:
    final_sign = 1
else:
    final_sign = 0
```

在有效减法情况下，也可理解为：

```text
sum_carry==1: final_sign = tentative_sign
sum_carry==0: final_sign = !tentative_sign
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

### 15.2 舍入增量

定义保留结果最低位：

```text
LSB = pre_round_abs[0]
inexact_remainder = round_bit || sticky_bit
```

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

为与参考 RTL 在 subnormal/最小 normal 边界处保持一致，必须使用以下完整表达式，而不能只判断舍入后 exponent 是否为零：

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

`sum_sticky_bits[2*MAN_BITS+4]` 正好是 `sum_sticky_bits` 的最高位，因为：

```text
width(sum_sticky_bits) = 2p+3 = 2*MAN_BITS+5
```

该边界逻辑用于识别未受限结果处于最小 normal 阈值以下、但舍入编码恰好进位到最小 normal 的情形。

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
- 精确 subnormal 可以不置 `UF`，因为 `UF` 必须与 `NX` 同时成立；
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

## 20. 组合数据通路伪代码

以下伪代码汇总数值核心。它不包含第 18 节的寄存器数组，但信号必须在规定切分点随 valid 一起流水。

```text
class_a, class_b, class_c = classify(raw_a, raw_b, raw_c, is_boxed)

a = raw_a
b = raw_b
c = raw_c
c.sign ^= op_mod

case op:
  FMADD:
    no additional change
  FNMSUB:
    a.sign = !a.sign
  ADD, ADDS:
    a = +1.0
    class_a = normal
  MUL:
    c = (rnd_mode == RDN) ? +0.0 : -0.0
    class_c = zero
  default:
    undefined

sp  = a.sign XOR b.sign
sub = sp XOR c.sign

special_result, special_status, is_special = special_case_tree(...)

ea = zero_extend_signed(a.exponent)
eb = zero_extend_signed(b.exponent)
ec = zero_extend_signed(c.exponent)

eadd = ec + !class_c.is_normal
eprod = (class_a.is_zero || class_b.is_zero)
      ? 2-BIAS
      : ea + class_a.is_subnormal
           + eb + class_b.is_subnormal - BIAS
ediff = eadd-eprod
etent = (ediff > 0) ? eadd : eprod

ma = {class_a.is_normal, a.fraction}
mb = {class_b.is_normal, b.fraction}
mc = {class_c.is_normal, c.fraction}

product = ma*mb
product_shifted = zero_extend(product) << 2

addend_shamt = saturating_alignment_shift(ediff)
addend_after_shift, shifted_out = align(mc, addend_shamt)
sticky_before = OR(shifted_out)

addend_shifted = sub ? NOT(addend_after_shift) : addend_after_shift
carry_in = sub && !sticky_before

sum_pos = product_shifted + addend_shifted + carry_in
sum_neg = addend_after_shift - product_shifted
carry   = MSB(sum_pos)
sum     = (sub && !carry) ? low(sum_neg) : low(sum_pos)
sign    = choose_sign(sub, carry, sp)

// optional internal pipeline here

lzc, empty = leading_zero_count(sum[2p+2:0])
norm_shift, norm_exp = choose_normalization_shift(...)
sum_shifted = zero_extend(sum) << norm_shift
final_mantissa, sum_sticky_bits, final_exp = small_normalize(...)
sticky = OR(sum_sticky_bits) || sticky_before

pre_abs, RS, pre_sign, of_before = assemble_for_round(...)
round_up = rounding_decision(pre_abs[0], RS, pre_sign, rnd_mode)
rounded_abs = pre_abs + round_up
rounded_sign = fix_exact_zero_sign(...)

regular_result = {rounded_sign, rounded_abs}
regular_status = classify_status(...)

result = is_special ? special_result : regular_result
status = is_special ? special_status : regular_status
```

## 21. 必须保持的实现不变量

重新编码 RTL 时必须保持以下不变量：

1. 乘积以完整 `2p` 位进入加减法，乘法后不单独舍入。
2. 对阶丢失位同时影响 sticky 和减法补码进位。
3. `exponent_difference` 始终定义为“加数指数减乘积指数”。
4. 有效减法必须能够在 `product-C` 与 `C-product` 之间选择正绝对值。
5. 大抵消路径必须检查低 `2p+3` 位的前导零。
6. 最终舍入仅执行一次。
7. overflow 时必须通过“最大有限值 + RS=11”进入统一舍入器。
8. underflow 必须使用第 16.3 节的最小 normal 边界表达式，并与 NX 相与。
9. NaN 输出必须为 canonical qNaN，不传播 payload。
10. `inf*0` 的 invalid 优先级高于 C 为 quiet NaN。
11. 特殊结果只选择特殊状态，不与常规状态合并。
12. tag、mask、aux 必须与结果保持事务级同步。
13. 每个流水级必须能够独立停顿，不能只实现全流水统一 clock-enable。
14. flush 必须清除所有实际 valid 寄存器。
15. `extension_bit_o` 恒为 1。

## 22. 验证要求

### 22.1 基本操作

每种受支持格式和每种合法舍入模式至少覆盖：

- FMADD、FMSUB、FNMSUB、FNMADD；
- ADD、SUB、ADDS；
- MUL；
- 正负操作数的所有符号组合；
- 结果恰好可表示和不可精确表示两类。

### 22.2 特殊值优先级

必须定向验证：

- `inf*0 + finite`；
- `inf*0 + qNaN`，仍必须置 NV；
- qNaN 与 sNaN；
- 未 NaN-box 输入，产生 canonical qNaN 且不因 boxing 本身置 NV；
- `+inf + -inf` 和 `-inf + +inf` 的有效减法；
- 无穷乘积与同号无穷有效加法；
- 有限乘积加正/负无穷；
- ADD 忽略原始 A 的 NaN/Inf；
- MUL 忽略原始 C 的 NaN/Inf。

### 22.3 零和符号

必须覆盖：

- `+0 + +0`、`-0 + -0`、`+0 + -0`；
- 精确抵消在 RDN 和非 RDN 模式下的零符号；
- 正负零乘正负有限数；
- MUL 在所有舍入模式下保持乘积零符号；
- subnormal 相消为零。

### 22.4 对阶、sticky 和抵消

必须覆盖指数差边界：

```text
ediff = -(2p+1), -(2p), 0, 1, 2, p+2, p+3
```

并分别验证：

- 移出位全零与存在 1；
- 有效加法和有效减法；
- `inject_carry_in` 在 sticky 变化时翻转；
- C 极小但通过 sticky 改变最终舍入；
- 乘积与 C 只差 1 ulp 或更小；
- 严重抵消后结果为 normal、subnormal 和零。

### 22.5 舍入和状态

每种舍入模式必须覆盖 `{R,S}=00/01/10/11`，RNE 的 tie case 还要分别覆盖保留 LSB 为 0 和 1。

必须覆盖：

- 最大有限值附近向 infinity 或最大有限值舍入；
- 正负 overflow 在 RDN/RUP 下的方向差异；
- 精确 subnormal，不置 UF/NX；
- 非精确 subnormal，同时置 UF/NX；
- 最大 subnormal 舍入到最小 normal 的边界；
- 最小 normal 邻域中第 16.3 节 underflow 附加条件；
- ROD 使非精确结果最低位为 1。

### 22.6 流水和握手

至少对以下配置运行随机反压：

- `NumPipeRegs=0, BEFORE`；
- `NumPipeRegs=1, INSIDE`；
- `NumPipeRegs=2, DISTRIBUTED`；
- `NumPipeRegs=3, DISTRIBUTED`；
- `NumPipeRegs>=2, BEFORE/INSIDE/AFTER`。

检查：

- 无反压时每周期一个事务；
- 任意反压下不丢失、不重复、不重排本实例内事务；
- 输出停顿时 payload 稳定；
- tag、mask、aux 与数据对应；
- flush 后所有在途 valid 消失；
- reset 后 valid 和 busy 清零；
- 各物理寄存器的 `reg_ena_i` 索引映射正确；
- `early_out_valid_o` 按所选兼容语义验证。

### 22.7 建议断言

实现中建议加入或在验证环境绑定以下性质：

```text
out_valid && !out_ready |=> $stable({result,status,tag,mask,aux,out_valid})

accepted_input_count - flushed_input_count - accepted_output_count
    == number_of_valid_transactions_in_pipeline

status.UF -> status.NX
status.OF -> status.NX
special_result_is_nan -> result == canonical_qNaN
extension_bit_o == 1
```

对于 `reg_ena_i` 非零的测试，应对稳定性断言增加相应环境假设。

## 23. RTL 编码检查清单

编码完成后，设计评审必须逐项确认：

- [ ] 所有指数临时量的 signed/unsigned 类型与第 10 节一致。
- [ ] 所有可变移位的左操作数已显式扩展到规定宽度。
- [ ] `product` 恰为 `2p` 位。
- [ ] `product_shifted` 和 `sum` 恰为 `3p+4` 位。
- [ ] `sum_pos`、`sum_neg`、`sum_shifted` 恰为 `3p+5` 位。
- [ ] C 对阶临时域恰为 `4p+4` 位。
- [ ] sticky 没有直接并入 addend LSB。
- [ ] 减法 carry-in 使用 `sub && !sticky_before_add`。
- [ ] 特殊值 if/else 优先级与第 9 节完全一致。
- [ ] LZC 的 empty 输出参与 normal/subnormal 路径选择。
- [ ] 小规格化判断顺序为 carry、主 MSB、可左移、subnormal。
- [ ] 舍入前 overflow 使用最大有限值和 `RS=11`。
- [ ] 精确零符号使用 effective subtraction 和 RDN。
- [ ] UF 使用完整边界表达式并与 NX 相与。
- [ ] 特殊路径状态覆盖而不是 OR 常规状态。
- [ ] 三个流水区的 valid、ready 和 payload 规则一致。
- [ ] `reg_ena_i` 只覆盖 payload enable。
- [ ] 输出反压时所有事务字段稳定。
- [ ] `extension_bit_o` 恒为 1。

## 24. 与上层集成的约束

本模块通常由 `fpnew_opgroup_fmt_slice` 的一个 lane 实例化。上层必须保证：

- 只把 `FpFormat` 对应宽度的 lane 数据送入本模块；
- 标量窄格式的 `is_boxed_i` 已由顶层检查；
- SIMD lane 输入的 boxing 位按架构要求置为有效；
- 只发射 ADDMUL 操作组支持的操作码；
- `rnd_mode_i` 已解析，不把 DYN 直接送入数值核心；
- mask 只用于上层合并状态，本模块仍计算被 mask lane；
- 若多个格式或操作组存在不同延迟，上层使用 tag 识别返回事务；
- 单格式 `PARALLEL` 实例不用于 `src_fmt != dst_fmt` 的混合格式 FMA。

## 25. 规格追踪表

| 规格内容 | 参考 RTL 区域 |
|---|---|
| 参数和端口 | `fpnew_fma.sv` 模块声明 |
| 流水线分配 | `fpnew_fma.sv` Constants/Pipelines |
| 输入流水线 | `fpnew_fma.sv` Input pipeline |
| 分类规则 | `fpnew_classifier.sv` Classify Input |
| 操作译码 | `fpnew_fma.sv` Operation selection and operand adjustment |
| 特殊值 | `fpnew_fma.sv` Special case handling |
| 指数路径 | `fpnew_fma.sv` Initial exponent data path |
| 乘积和对阶 | `fpnew_fma.sv` Product/Addend data path |
| 加减和符号 | `fpnew_fma.sv` Adder |
| 内部流水线 | `fpnew_fma.sv` Internal pipeline |
| 规格化 | `fpnew_fma.sv` Normalization |
| 舍入和标志 | `fpnew_fma.sv` Rounding and classification；`fpnew_rounding.sv` |
| 输出流水线 | `fpnew_fma.sv` Output Pipeline |
| 顶层 lane 集成 | `fpnew_opgroup_fmt_slice.sv` ADDMUL lane instance |
