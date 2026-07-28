# FMA 设计权衡：双路尾数加减结构

## 1. 文档目的

本文档说明单格式并行 `fpnew_fma` 为什么在尾数有效减法中同时计算两个方向的差，以及这种结构在时序、面积、功耗和验证方面的权衡。

对应 RTL 位于 `src/fpnew_fma.sv` 的 `sum_pos`、`sum_neg`、`sum_carry`、`sum` 和 `final_sign` 逻辑。本文中的“双路”指 RTL 同时描述两个算术结果，不规定综合工具必须使用某一种具体的 gate-level 加法器结构。

## 2. 需要解决的问题

完成乘法和对阶后，数据通路需要处理：

```text
effective_subtraction == 0: |product| + |C|
effective_subtraction == 1: |product| - |C|
```

有效加法中，结果绝对值直接是两个对阶尾数之和。

有效减法中，后续规格化逻辑需要的是非负结果：

```text
abs(|product| - |C|)
```

但是，只根据指数差不能在所有情况下确定两个对阶尾数谁更大。指数接近或相等时，必须继续比较尾数；C 被移出的低位中是否存在 `1` 也会影响严格的大小关系。

因此，设计必须同时完成：

1. 计算尾数差的绝对值；
2. 判断乘积和 C 中哪个绝对值更大；
3. 选择结果符号。

## 3. RTL 采用的双路计算

定义：

```text
W = SUM_WIDTH
P = product_shifted
H = addend_after_shift
S = sticky_before_add
```

`P` 和 `H` 都是 `W` 位对阶尾数。`S` 是 C 被移出低位的 OR-reduction。

### 3.1 `sum_pos`

```systemverilog
addend_shifted  = effective_subtraction ? ~H : H;
inject_carry_in = effective_subtraction && !S;

sum_pos = P + addend_shifted + inject_carry_in;
```

- 有效加法时，`sum_pos` 计算 `P+H`。
- 有效减法时，`sum_pos` 计算与完整 `P-C` 相容的保留位，并通过最高位 `sum_carry` 给出 carry-out。

### 3.2 `sum_neg`

```systemverilog
sum_neg = H - P;
```

`sum_neg` 是反方向的差。只有在有效减法且 C 更大时，它才被选为结果绝对值。C 被移出的低位仍由 `sticky_before_add` 保留，供最终舍入使用。

RTL 直接使用 SystemVerilog `-` 运算符。这已经完整规定了减法功能；综合工具可以将它实现为 adder/subtractor cell，也可以实现为对 P 执行 `two's complement` 后相加。手工改写为 `H + ~P + 1` 时，必须保证取反和加法均使用 `ADDER_WIDTH` 位，否则可能改变最高位。

### 3.3 结果选择

```systemverilog
sum_carry = sum_pos[W];

sum = (effective_subtraction && !sum_carry)
        ? sum_neg[W-1:0]
        : sum_pos[W-1:0];
```

有效减法时：

```text
sum_carry == 1: 选择 P-C
sum_carry == 0: 选择 C-P
```

有效加法时始终选择 `sum_pos`，`sum_neg` 的结果不被使用。

## 4. `sum_carry` 同时完成大小判断

将 C 的完整对阶尾数写成：

```text
|C| = H + f
```

其中 `f` 由被移出的低位组成，满足：

```text
S == 0: f = 0
S == 1: 0 < f < 1
```

P 在相同截断位置以下没有被省略的非零位，因此可以把 P 视为该单位下的整数。

### 4.1 `S==0`

```text
sum_pos = P + ~H + 1
        = 2^W + P - H
```

因此：

```text
sum_carry == 1 <=> P >= H
```

若 `P==H`，则两个完整对阶尾数相等，结果为：

```text
sum_carry = 1
sum       = 0
```

### 4.2 `S==1`

```text
sum_pos = P + ~H
        = 2^W + P - H - 1
```

因此：

```text
sum_carry == 1 <=> P >= H+1
```

由于 `H < |C| < H+1`，上式等价于：

```text
sum_carry == 1 <=> P > |C|
```

特别地，如果 `P==H` 但 `S==1`，只是保留部分相等，完整 C 仍大于 P：

```text
sum_carry = 0
sum_neg   = 0
sticky_before_add = 1
```

`sum_neg` 中的零和单独保留的 sticky 共同表示差值位于当前保留范围以下，不表示完整差值为零。

综合两种情况：

```text
sum_carry == 1 <=> |product| >= |C|  〈比较完整对阶尾数〉
sum_carry == 0 <=> |product| <  |C|
```

完整对阶尾数相等必须同时满足：

```text
P == H && S == 0
```

这是 `two's complement` 减法中 carry-out 与 borrow 的关系：

- `carry-out==1`：没有发生 borrow，被减数不小于减数；
- `carry-out==0`：发生 borrow，被减数小于减数。

## 5. 不同实现方案的权衡

### 5.1 方案 A：单减法器后计算绝对值

首先计算：

```text
D = P-C
```

若 carry-out 表明 `D<0`，再计算：

```text
abs(D) = ~D + 1
```

组合路径为：

```text
减法器 -> carry-out 判断 -> 条件取反 -> incrementer -> 结果
```

优点：

- 可以减少一条并行的全宽减法路径；
- 在允许多周期或较低频率时，可以复用算术资源。

缺点：

- 负差必须在减法后再通过一次全宽 `two's complement` 转换为绝对值；
- 加长从尾数减法到规格化输入的 critical path；
- 若不增加流水级，会限制最高工作频率。

### 5.2 方案 B：先比较大小，再交换操作数

首先比较 P 和完整 C，再将较大值放在减法器左侧：

```text
幅值比较 -> 操作数 MUX -> 减法器 -> 结果
```

优点：

- 只需要一个全宽减法器；
- 减法器直接输出非负结果，不需要减法后再计算绝对值。

缺点：

- 比较器、操作数 MUX 和减法器串联；
- 比较必须包含 `sticky_before_add`，不能只比较 P 和 H；
- 全宽比较器和减法器内部都需要传播大小关系，串联实现会增加 critical path。

### 5.3 方案 C：当前 RTL 的双路并行计算

同时计算：

```text
P-C
C-P
```

等待 `sum_pos` 的 carry-out 后，只需要用一个 MUX 选择已经计算好的非负差。

优点：

- 从对阶尾数到结果绝对值的主要路径是一次加/减法和一个 MUX；
- 不需要在减法后串联 `two's complement` 转换；
- `sum_carry` 同时提供大小判断，不需要单独串联全宽比较器；
- 适合在尾数加减之后设置流水切分点。

缺点：

- 需要同时实现两条全宽算术路径，增加面积；
- 即使执行有效加法，RTL 中 `sum_neg` 仍可能随输入翻转，增加动态功耗；
- 两条路径的布局布线和结果 MUX 也会带来额外面积和延迟；
- 是否共享部分逻辑、是否使用专用 arithmetic cell，由综合约束和标准单元库决定，不能只根据 RTL 语句确定最终物理结构。

### 5.4 权衡汇总

| 方案 | 主要组合路径 | 算术资源 | 时序特点 | 功耗特点 |
|---|---|---|---|---|
| 单减法后计算绝对值 | 减法 -> 条件取反 -> `+1` | 可复用一条加减资源 | 负差路径较长 | 资源较少，但内部翻转仍取决于实现 |
| 先比较再减 | 比较 -> MUX -> 减法 | 一个比较器和一个减法器 | 前置逻辑与减法串联 | 通常低于双路同时计算 |
| 双路并行计算 | 加/减法 -> MUX | 两条全宽算术路径 | 较适合高频单周期尾数加减 | 面积和动态功耗通常更高 |

实际 PPA（power, performance, area）结果取决于目标工艺、标准单元库、时钟约束、流水配置和综合工具。本文档只说明可以从 RTL 确定的结构性权衡，不在没有综合报告的情况下给出具体 PPA 数字。

## 6. 符号处理

对有效减法：

```text
sum_carry == 1: 结果符号 = 乘积符号
sum_carry == 0: 结果符号 = C 的符号
```

因为 `effective_subtraction==1` 时乘积与 C 的符号相反，所以也可以写成：

```text
sum_carry == 1: final_sign = tentative_sign
sum_carry == 0: final_sign = !tentative_sign
```

双路计算因此不仅生成结果绝对值，也提供最终符号所需的大小判断。如果完整差值为零，最终零的符号仍由 `fpnew_rounding` 中针对 `exact zero` 的逻辑处理。

## 7. RTL 编码约束

重新实现该结构时，必须保持以下行为：

1. `sum_pos`、`sum_neg` 必须使用 `ADDER_WIDTH=SUM_WIDTH+1` 位进行运算；
2. `sum_carry` 必须取自 `sum_pos[SUM_WIDTH]`；
3. 有效减法时，`inject_carry_in` 必须等于 `!sticky_before_add`；
4. `sum_neg` 使用未取反的 `addend_after_shift`，不使用 `addend_shifted`；
5. 只有 `effective_subtraction && !sum_carry` 时选择 `sum_neg`；
6. 相等必须指完整对阶尾数相等，条件为 `P==H && sticky_before_add==0`；
7. `sticky_before_add` 必须继续传递到规格化和舍入逻辑，不得因 `sum_neg==0` 而丢失。

## 8. 验证重点

至少覆盖以下场景：

| 场景 | 期望 `sum_carry` | 期望选择 | 其他检查 |
|---|---:|---|---|
| 有效加法 | 不用于选择减法方向 | `sum_pos` | 结果符号为共同符号 |
| `P>H`，`S==0` | 1 | `P-C` | 符号为乘积符号 |
| `P<H`，`S==0` | 0 | `C-P` | 符号为 C 符号 |
| `P==H`，`S==0` | 1 | `P-C` | 完整差值为零，检查 `exact zero` 符号 |
| `P==H`，`S==1` | 0 | `C-P` | `sum_neg==0` 但 sticky 仍为 1 |
| `P==H+1`，`S==1` | 1 | `P-C` | 乘积只比完整 C 大不足 1 个保留单位 |
| 结果发生长串抵消 | 由完整大小关系决定 | 与符号一致的非负差 | 检查 LZC、规格化和舍入 |

对内部信号可以添加与下列行为等价的 assertion：

```text
effective_subtraction && (P==H) && !S
  -> sum_carry && (sum==0)

effective_subtraction && (P==H) && S
  -> !sum_carry && (sum_neg==0) && sticky_before_add

effective_subtraction && sum_carry
  -> final_sign == tentative_sign

effective_subtraction && !sum_carry
  -> final_sign == !tentative_sign
```

## 9. 结论

双路并行计算的目的是避免将“大小判断”或“负差转换为绝对值”串联在一次全宽减法之后。它用第二条全宽减法路径换取更短的组合逻辑路径，并使用 `sum_pos` 的 carry-out 同时完成大小判断和符号选择。

因此，该结构的核心权衡是：

```text
更短的 critical path 和更高的目标时钟频率
                     <->
更多的全宽算术资源、面积和动态功耗
```

当流水线能够每周期接收一笔事务时，提高时钟频率才会进一步提高单位时间的吞吐率；双路结构本身不改变“每周期最多接收一笔事务”的接口能力。
