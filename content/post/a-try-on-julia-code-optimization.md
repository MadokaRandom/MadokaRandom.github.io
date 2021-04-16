---
title: "记一次 Julia 代码性能优化过程"
date: 2021-04-16T13:06:00+08:00
tags: ["Posts", "Julia", "Optimization", "ParallelProgramming"]
categories: ["Programming"]
draft: false
weight: 1
---

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [运行环境](#运行环境)
- [优化过程](#优化过程)
    - [原始版本](#原始版本)
    - [使用 C-ffi 的 `rgamma` 与 `rnorm`](#使用-c-ffi-的-rgamma-与-rnorm)
    - [去除外部依赖](#去除外部依赖)
    - [内存分配情况分析](#内存分配情况分析)
    - [去除内层循环的内存分配](#去除内层循环的内存分配)
    - [去除外层循环的内存分配](#去除外层循环的内存分配)
    - [使用多线程加速](#使用多线程加速)
- [总结](#总结)

</div>
<!--endtoc-->

这是和某三爷讨论后对交流内容的整理。

<!--more-->

众所周知， Julia 是一种高级通用动态编程语言，它专为科学计算而生。为了方便科研人员使用，它的语法被设计得很像 MATLAB ，但比 MATLAB 更合理（譬如数组引用使用 `[]`
，而不是 `()` ）。作为一门很年轻的语言，它吸收了前辈们的很多优点，也有着自己的特色，但最受人青睐的一点在于：尽管它是一门动态语言，却宣称拥有 C/C++ 一般的性能。
一般而言，动态语言的表现能力更为出色，能用更少的代码做更多的事，开发效率高；而静态语言的编译器后端更容易优化，运行效率高。Julia 有动态性，开发效率毋庸置疑，一些测评也显示 Julia 确实拥有很强的性能，但这是否意味着你随手写的一段代码就能有很高并且达到预期的性能？我看未必。


## 运行环境 {#运行环境}

| Processor | Intel Core i5 9600KF |
|-----------|----------------------|
| Memory    | 16GB 3200MHz         |
| OS        | macOS 10.15.6        |
| Julia     | 1.5.1                |


## 优化过程 {#优化过程}


### 原始版本[^fn:1] {#原始版本}

废话不多说，直接开始正题，先来看今天的主角[^fn:2]

```ess-julia
using Rmath;
using BenchmarkTools;

function JGibbs1(N::Int, thin::Int)
    mat = zeros(Float64, N, 2)
    x   = 0.
    y   = 0.
    for i = 1:N
        for j = 1:thin
            x = rgamma(1, 3, 1/(y*y + 4))[1]
            y = rnorm(1, 1/(x+1), 1/sqrt(2(x + 1)))[1]
        end
        mat[i,:] = [x,y]
    end
    mat
end;

@btime JGibbs1(20000, 200);
```

这是一段关于 Gibbs 采样的代码，它主要由两个循环组成，外部循环一次产生两个值，内部循环是迭代式的，即下一次循环要用到上次循环的结果。很明显它引入了 R 的库，并用
R 的 `rgamma` 和 `rnorm` 实现，那么它的性能是怎样的呢？

```text
  501.798 ms (8020002 allocations: 734.56 MiB)
```

根据原文的说法，它的性能已经比 `Rgibbs` 快 17 倍，比 `RCgibbs` 快 13 倍，已经是比较令人满意的结果了。


### 使用 C-ffi 的 `rgamma` 与 `rnorm`[^fn:1] {#使用-c-ffi-的-rgamma-与-rnorm}

由于直接用 R 写的代码可能并不是最快的，而且它还在内层循环里，所以我们有理由相信使用 C-ffi[^fn:3] 版的 `rgamma` 与 `rnorm` 会更快。

```ess-julia
using Rmath
import Rmath: libRmath
using BenchmarkTools
function JGibbs2(N::Int, thin::Int)
    mat = zeros(Float64, N, 2)
    x   = 0.
    y   = 0.
    for i = 1:N
        for j = 1:thin
            x = ccall((:rgamma, libRmath), Float64, (Float64, Float64), 3., 1/(y*y + 4))
            y = ccall((:rnorm, libRmath), Float64, (Float64, Float64), 1/(x+1), 1/sqrt(2*(x + 1)))
        end
        mat[i,:] = [x,y]
    end
    mat
end

@btime JGibbs2(20000, 200);
```

```text
JGibbs2 (generic function with 1 method)
  259.387 ms (20002 allocations: 2.14 MiB)
```

果然，使用 C-ffi 版的函数后性能又提升了一倍！


### 去除外部依赖[^fn:1] {#去除外部依赖}

尽管使用 C 的实现后， `JGibbs` 性能提升巨大，但依赖外部库多少有点让人感觉不爽，
毕竟它和 Julia 所宣称的高性能关系不是很大（核心部分是 C 的贡献，而不是 Julia）。
既然 Julia 也是高性能语言，何不拿纯 Julia 写一个 `JGibbs` 来比比？

Julia 是为科学计算而生，它的社区维护了一个统计学库 `Distributions` ，里面包含了
`gamma` 与 `norm` 分布的函数，可以用来替换 `rgamma` 和 `rnorm` ，写完之后是这个样子：

```ess-julia
using BenchmarkTools;
using Distributions;

function JGibbs3(N::Int, thin::Int)
    mat = zeros(Float64, N, 2)
    x   = 0.
    y   = 0.
    for i = 1:N
        for j = 1:thin
            x = rand(Gamma(3, 1/(y^2 + 4)), 1)[1]
            y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))), 1)[1]
        end
        mat[i,:] = [x,y]
    end
    mat
end

@btime JGibbs3(20000, 200);
```

```text
JGibbs3 (generic function with 1 method)
  550.624 ms (8020002 allocations: 734.56 MiB)
```

咦？看起来它还没有使用 R-ffi 的函数快！

那么问题出在哪呢？仔细看结果，除了时间之外还有两个数据，一个是执行一次该函数时所分配内存的次数，另一个是函数执行期间分配内存的总量。我们回头看一下使用 C-ffi 的版本，它的测试结果显示除了性能更强外，内存分配的次数和总量也更少！而且 8020002
恰好是 20002 的 400 倍左右，正好是 `thin=200` 的 2 倍。据此，我们可以猜想，在
`for j=1:thin ... end` 内部存在不必要的内存分配。

下面来进行验证。


### 内存分配情况分析 {#内存分配情况分析}

取出循环内的一行代码，对它进行 profile ：

```ess-julia
using BenchmarkTools;
using Distributions;

@btime rand(Gamma(1.0, 1.0), 1)[1];
```

```text
  39.136 ns (1 allocation: 96 bytes)
```

奇怪，一个只返回一个 Float64 值的函数怎么会存在内存分配？仔细看 `[1]` 这个细节，
问题可能出在这里。通过查看文档，发现 `rand(Gamma(...), 1)` 中最后一个参数表示返回一个一维的 Array ，并且 Array 的大小是 1 ：

```ess-julia
using BenchmarkTools;
using Distributions;

@btime rand(Gamma(1.0, 1.0), 1)
```

```text
  37.541 ns (1 allocation: 96 bytes)
1-element Array{Float64,1}:
 0.2929698750637693
```

一个 Float64 的值有 64 位，共 8 字节（bytes），而刚刚代码中所返回只有一个
Float64 元素的 Array 竟然有 96 字节！既然我们每次只需要返回一个值，那为什么要画蛇添足去生成一个 Array 呢，直接调用只生成一个值的原型不好吗？

```ess-julia
using BenchmarkTools;
using Distributions;

@btime rand(Gamma(1.0, 1.0), 1)
@btime rand(Gamma(1.0, 1.0))
```

```text
  37.217 ns (1 allocation: 96 bytes)
1-element Array{Float64,1}:
 0.9938638399122478
  8.116 ns (0 allocations: 0 bytes)
1.8038508272928604
```

看，直接使用 `rand(Gamma(...))` 耗时只有 `rand(Gamma(...), 1)` 的 22% ，并且内存的分配是 0 ！

有了这些结论，我们对 `JGibbs3` 修改后，有了下面的代码。


### 去除内层循环的内存分配 {#去除内层循环的内存分配}

```ess-julia
using BenchmarkTools;
using Distributions;

function JGibbs4(N::Int, thin::Int)
    mat = zeros(Float64, N, 2)
    x   = 0.
    y   = 0.
    for i = 1:N
        for j = 1:thin
            x = rand(Gamma(3, 1/(y*y + 4)))
            y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))))
        end
        mat[i,:] = [x,y]
    end
    mat
end

@btime JGibbs4(20000, 200);
```

```text
JGibbs4 (generic function with 1 method)
  251.144 ms (20002 allocations: 2.14 MiB)
```

这个耗时结果就正常多了，而且比调用 C-ffi 的版本还快了一丢丢；内存的分配也没那么夸张了。


### 去除外层循环的内存分配 {#去除外层循环的内存分配}

但这并不是它的性能极限：它依然有 20002 次的内存分配。仔细观察外层循环部分，只有一个 `mat[i,:] = [x,y]` ，通常人们会认为编译器把它循环展开，不涉及内存分配，但事实并非如此：

```ess-julia
using BenchmarkTools

mat = zeros(Int, 2, 2);
@btime mat[1, :] = [1, 2];
@btime mat[:, 1] = [1, 2];
@btime begin
    mat[1, 1] = 1;
    mat[1, 2] = 2;
    end;
@btime begin
    mat[1, 1] = 1;
    mat[2, 1] = 2;
    end;
```

```text
  259.485 ns (2 allocations: 112 bytes)
  220.621 ns (2 allocations: 112 bytes)
  28.665 ns (0 allocations: 0 bytes)
  27.603 ns (0 allocations: 0 bytes)
```

我们可以得出三个结论：

1.  在使用切片赋值时会涉及内存分配，直接使用循环则不会；
2.  小矩阵赋值时使用循环甚至手动展开循环性能更高；
3.  Julia 的 Array 使用列主序，对第一个维度操作比对其它维度操作性能更高，但提升幅
    度有限。

于是我们把 `JGibbs4` 中外层循环的矩阵赋值展开，得到 `JGibbs5`

```ess-julia
using BenchmarkTools;
using Distributions;

function JGibbs5(N::Int, thin::Int)
    mat = zeros(Float64, N, 2)
    x   = 0.
    y   = 0.
    for i = 1:N
        for j = 1:thin
            x = rand(Gamma(3, 1/(y*y + 4)))
            y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))))
        end
        mat[i,1] = x;
        mat[i,2] = y;
    end
    mat
end

@btime JGibbs5(20000, 200);
```

```text
JGibbs5 (generic function with 1 method)
  229.861 ms (2 allocations: 312.58 KiB)
```

它比 `JGibbs4` 又快了 20ms ！而且其中内存分配只有两次，已经相当令人满意了。如果要进一步压榨它的性能潜力，我们可以交换 `mat` 的行列，使外层循环每次赋值时都在访问第一个维度，限于篇幅原因，这里就不展开了。


### 使用多线程加速 {#使用多线程加速}

上面使用的方法都是在一个线程内操作，现在的机器普遍都用上的多核处理器，而超算上更是单节点上配备了数十个处理器，如此多的计算资源不利用好岂不是暴殄天物。

那么 `JGibbs` 函数能被并行化吗？答案是肯定的。

它的内层循环粒度太小，线程切换的耗时占比太高，因此内层循环不适合并行化。而外层循环的粒度适中，我们试试将它并行化。

<!--list-separator-->

-  直接使用 `Threads.@threads`

    Julia 原生支持多线程编程，并且提供了 `Threads.@threads` 宏来方便对循环并行化，于
    是就有了下面的代码

    ```ess-julia
    println("nthreads = ", Threads.nthreads())

    using BenchmarkTools;
    using Distributions;

    function JGibbs6(N::Int, thin::Int)
        mat = zeros(Float64, N, 2)
        x   = 0.
        y   = 0.
        Threads.@threads for i = 1:N
            for j = 1:thin
                x = rand(Gamma(3, 1/(y*y + 4)))
                y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))))
            end
            mat[i,1] = x;
            mat[i,2] = y;
        end
        mat
    end

    @btime JGibbs6(20000, 200);
    ```

    ```text
    nthreads = 6
    JGibbs6 (generic function with 1 method)
      420.151 ms (52000035 allocations: 915.84 MiB)
    ```

    [^fn:4]

    这个结果很离谱。先不谈运行时间，单看它的内存分配量就知道它绝对是有问题的（至于为
    什么多出来这么多的内存分配，我也还在寻找原因，如果您有什么见解，请务必发邮件告诉
    我 ^\_^）， `Julia` 一共开了 6 个线程来加速，但结果显示它反而使运行效率降低了，问
    题出在哪呢？仔细看代码

    ```ess-julia
        x   = 0.
        y   = 0.
        Threads.@threads for i = 1:N
            for j = 1:thin
                x = rand(Gamma(3, 1/(y*y + 4)))
                y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))))
            end
            ...
        end
    ```

    每个线程内，都要对全局变量 `x` 和 `y` 进行修改，并且还要读取它们的值，这显然存在
    竞争的现象。那如果把 `x` 和 `y` 移动到每个线程内部定义呢？

    ```ess-julia
    println("nthreads = ", Threads.nthreads())

    using BenchmarkTools;
    using Distributions;

    function JGibbs6_1(N::Int, thin::Int)
        mat = zeros(Float64, N, 2)
        Threads.@threads for i = 1:N
            x   = rand()
            y   = rand()
            for j = 1:thin
                x = rand(Gamma(3, 1/(y*y + 4)))
                y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))))
            end
            mat[i,1] = x;
            mat[i,2] = y;
        end
        mat
    end

    @btime JGibbs6_1(20000, 200);
    ```

    ```text
    nthreads = 6
    JGibbs6_1 (generic function with 1 method)
      39.926 ms (33 allocations: 316.75 KiB)
    ```

    这个结果相当令人满意了，内存的分配降低很多，看来读写全局的变量对并发程序性能影响
    还是不容忽略！

<!--list-separator-->

-  对外层循环分组后并行

    除了直接用 `@threads` ，我们还可以手动对外部循环分组嘛，然后每个线程分配到一小段
    连续的外层循环，相当于粒度更大。

    `Iterators` 提供了对 `Array` 分组的方法：

    ```text
    help?> Iterators.partition
      partition(collection, n)

      Iterate over a collection n elements at a time.

      Examples
      ≡≡≡≡≡≡≡≡≡≡

      julia> collect(Iterators.partition([1,2,3,4,5], 2))
      3-element Array{SubArray{Int64,1,Array{Int64,1},Tuple{UnitRange{Int64}},true},1}:
       [1, 2]
       [3, 4]
       [5]
    ```

    利用这个函数，我们对外层循环的下标分组，然后每个线程只操作一组下标，这样有效避免了数据竞争发生。

    ```ess-julia
    using BenchmarkTools;
    using Distributions;

    println("nthreads = ", Threads.nthreads())

    function JGibbs7(N::Int, thin::Int)
      nt = Threads.nthreads()

      # mat = zeros(Float64, N, 2)
      mat = zeros(Float64, N, 2)

      # partition
      parts = Iterators.partition(1:N, N ÷ Threads.nthreads() + 1) |> collect

      Threads.@threads for p in parts
        x   = 0.
        y   = 0.
        for i in p
          for j in 1:thin
            x = rand(Gamma(3, 1/(y^2 + 4)))
            y = rand(Normal(1/(x + 1), 1/sqrt(2*(x + 1))))
          end
          mat[i,1] = x
          mat[i,2] = y
        end
      end

      mat
    end

    @btime JGibbs7(20000, 200);
    ```

    ```text
    nthreads = 6
    JGibbs7 (generic function with 1 method)
      41.631 ms (34 allocations: 316.91 KiB)
    ```

    这个结果和 `JGibbs6_1` 相差不大，都是已经充分利用了 6 个线程的计算资源。


## 总结 {#总结}

本文从一名用户的角度，浅显地阐述了如何对一个函数进行优化，以及如何使用各类工具来帮助我们分析程序的运行状况。我得出以下几个结论，供大家参考：

1.  使用纯 Julia 编写的程序性能的 **上限** 很高，完全不输于调用 FFI ，因此大家对此
    不应有过多的顾虑，直接用就完事了；
2.  尽管我们认为处理器的计算是耗时大头，程序运行时的内存反复分配也可能成为程序运
    行的瓶颈；
3.  在使用并发加速时应格外小心是否存在竞争的风险，能做到内聚就尽量做到内聚，否则
    将来总会掉到坑里；
4.  想发挥出 Julia 真正的性能，还是需要下一些功夫的，随手一写还真不一定比其它语言
    快；好在 Julia 社区提供了实用的性能分析工具，大大简化了优化的流程，这一点我十
    分赞赏。

[^fn:1]: 代码来自三爷的 gist : <https://gist.github.com/MitsuhaMiyamizu/5edf031a36cfb260381a70060a3fea4a>
[^fn:2]: 这里使用 BenchmarkTools 中的 `@btime` 而不是 `@time` 是因为后者并不能将代 码编译的时间去掉，前者则能多次执行，取耗时最小值，有效避免了 AOT 对计时的影响。
[^fn:3]: ffi 即 Foreign function interface ，用于跨语言调函数，详见 <https://en.wikipedia.org/wiki/Foreign%5Ffunction%5Finterface>
[^fn:4]: 我在启动 `julia` 前对环境变量进行了修改 `export JULIA_NUM_THREADS=6` ，这 样 Julia 在运行时支持最大 6 个线程操作。
