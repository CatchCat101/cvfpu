# `fpnew_fma` 单格式 UVM 验证环境

本目录验证一个 `fpnew_fma` 实例。一次编译只选择 FP16、FP32 或 FP64 之一，参考结果
由固定版本的 Berkeley SoftFloat 产生。FP8 和 FP16ALT 当前明确不支持。

完整的验证范围、覆盖率模型和回归矩阵见
[`docs/fpnew_fma_verification_plan.md`](../../docs/fpnew_fma_verification_plan.md)。

## 结构

```text
common/                 格式配置和公共记录
interface/              参数化 fma_if
agents/input/           data/control 两套 sequencer-driver 与 input monitor
agents/output/          ready sequencer-driver 与 output monitor
env/components/         SoftFloat reference、scoreboard、coverage
sequences/              data/control/ready/virtual sequences
tests/                  七个 test
assertions/             接口、状态和 early_out_valid 检查
dpi/softfloat/          统一 C adapter 和自检
top/                    DUT top
files/ mk/ cfg/ scripts/ 构建、回归和报告
```

数据连接为：输入 monitor 同时送 reference 和 input coverage；reference 送 expected；
输出 monitor 送 actual；scoreboard 比较通过后才送 checked result coverage。reset/flush
事件由 input monitor 直接同时送 scoreboard 和 coverage。

## 依赖

初始化子模块：

```sh
git submodule update --init --recursive
```

默认 SoftFloat 位于 `tb/berkeley-softfloat-3`，固定 commit
`a0c6494cdc11865811dec815d5c0049fba9d82a8`，使用 `RISCV` specialization。也可用
`SOFTFLOAT_DIR=/path/to/checkout` 指定相同版本；只有明确设置
`ALLOW_UNPINNED_REF=1` 才允许本地调试其他版本。

先检查依赖并运行 C adapter 自检：

```sh
make -C tb/fma_uvm doctor FORMAT=FP32 CFG=n0_before
make -C tb/fma_uvm selftest
```

## 单项运行

```sh
# FP16 smoke，无流水
make -C tb/fma_uvm smoke FORMAT=FP16 CFG=n0_before SEED=1

# FP32 定向覆盖
make -C tb/fma_uvm directed FORMAT=FP32 CFG=n0_before SEED=2

# FP64 随机数据，四级 distributed pipeline
make -C tb/fma_uvm random-data FORMAT=FP64 CFG=n4_dist \
  SEED=424242 NB_TXNS=20000

# flush / reset / flow / random control
make -C tb/fma_uvm flush FORMAT=FP32 CFG=n2_before
make -C tb/fma_uvm reset FORMAT=FP32 CFG=n2_after
make -C tb/fma_uvm flow FORMAT=FP32 CFG=n4_dist
make -C tb/fma_uvm random-control FORMAT=FP32 CFG=n4_dist NB_TXNS=10000
```

主要变量：

| 变量 | 取值 |
|---|---|
| `FORMAT` | `FP16`、`FP32`、`FP64` |
| `CFG` | `n0_before`、`n2_before`、`n2_inside`、`n2_after`、`n1_dist`～`n4_dist` |
| `PROFILE` | `fast`、`debug`、`cov` |
| `TEST` | 七个 test class 名 |
| `SEED` | 仿真随机种子 |
| `NB_TXNS` | 随机测试的操作次数 |

build、run、report 和 coverage 数据按 FORMAT/CFG/TEST 分目录保存，三种格式不会互相
覆盖或合并。

## 回归

```sh
# 三种格式的快速 smoke
make -C tb/fma_uvm regress SUITE=smoke FORMATS=FP16,FP32,FP64 JOBS=4

# 完整代表性矩阵并收集 coverage
make -C tb/fma_uvm regress SUITE=signoff FORMATS=FP16,FP32,FP64 \
  PROFILE=cov JOBS=4

# 单独检查某一格式的 coverage 门槛
make -C tb/fma_uvm cov-check FORMAT=FP32
```

只有 `fma_flow_control_test + n2_inside` 是当前已知 DUT
`early_out_valid_o` 问题的 XFAIL。XFAIL 运行不合并进通过项 coverage；如果 DUT 修复使
它通过，脚本报告 XPASS 并返回失败，提示移除旧标记。

XFAIL 只接受 `a_early_out_valid` 断言失败，同时要求 UVM、scoreboard 和排空检查全部
正常；同一条目中的数值错误、其他断言、fatal 或 timeout 仍报告 FAIL。`signoff` 强制
使用 `PROFILE=cov`，并在每种格式运行结束后自动执行 URG 合并和覆盖率门槛检查。

正常通过要求日志中 0 UVM error/fatal、0 mismatch、无 pending record、无 SVA failure
和 timeout。随机测试必须用 FORMAT/CFG/TEST/SEED/NB_TXNS 原样重放。
