---
title: "简易 DFT 玩具"
date: 2022-08-14T22:13:00+08:00
tags: ["Posts", "Julia", "FiniteDifferenceMethod", "DensityFunctionalTheory"]
categories: ["Physics"]
draft: false
mathjax: true
markup: "goldmark"
---

<div class="ox-hugo-toc toc">

<div class="heading">Table of Contents</div>

- [理论基础](#理论基础)
- [程序实现](#程序实现)
    - [\\(\nabla^2\\) 的矩阵表示](#nabla-2-的矩阵表示)
    - [势能的表示](#势能的表示)
        - [外场势能 \\(v\_\text{ext}(\mathbf r)\\)](#外场势能-v-text-ext--mathbf-r)
        - [电子密度 \\(\rho(\mathbf r)\\)](#电子密度-rho--mathbf-r)
        - [库仑势 \\(v\_\text{Ha}(\mathbf r)\\)](#库仑势-v-text-ha--mathbf-r)
        - [交换关联势](#交换关联势)
    - [Hamiltonian 的构造](#hamiltonian-的构造)
    - [KS 方程的迭代求解](#ks-方程的迭代求解)
- [总结与拓展](#总结与拓展)

</div>
<!--endtoc-->

一直在用别人写好的 DFT 软件，对软件的运行过程略有兴趣，查阅资料弄懂了一些运行原理并参考了前人的程序后，这次我们来自己写一个 DFT 的玩具～

<!--more-->

**首先感谢一个 GitHub 上的仓库，为本文的代码提供了参考[^fn:1]。**


## 理论基础 {#理论基础}

我们的目标是求解 Kohn-Sham 方程。

对于 Kohn-Sham 方程，系统的能量包含下面几个部分

\\[
E[\rho] = T\_s[\rho] + \int d\mathbf r v\_\text{ext}(\mathbf r) \rho(\mathbf r) + E\_\text{Ha} [\rho] + E\_\text{xc}[\rho]
\\]

其中 \\(T\_s\\) 是 Kohm-Sham 动能项，它的表达形式为

\\[
T\_s[\rho] = \sum\_{i=1}^{N} \int d\mathbf r \varphi^\*(\mathbf r) \left( -\frac{\hbar^2}{2m}
\nabla^2 \right) \varphi\_i( r)
\\]

\\(v\_\text{ext}(\mathbf r)\\) 是外场作用在系统所有电子上的势能，这里“外”是指除所研究电子以外，
电子与原子核的相互作用也算在这一项内；

\\(E\_\text{H}[\rho]\\) 为 Hartree 能，也就是电子-电子的库仑相互作用项

\\[
E\_\text{H}[\rho] = \frac{e^2}{8\pi\epsilon} \int d\mathbf r \int d\mathbf{r'} \frac{\rho(\mathbf r)
\rho(\mathbf {r'})}{|\mathbf r - \mathbf{r'}|}
\\]

\\(E\_\text{xc}[\rho]\\) 是交换关联能，这里为了简便处理，只使用 LDA 近似处理交换项，忽略关联项。
在 LDA 近似下

\\[
E\_\text{x}^\text{LDA}[\rho] = -\frac 34 (\frac 3\pi)^{1/3} \int \rho^{4/3} d \mathbf r
\\]

上面式子中 \\(\rho\\) 代表系统的电子密度，它是通过下面方式计算得到：
令一系列正交归一的占据态电子轨道为 \\(\varphi\_i\\)，则体系的电子密度为
\\[
\rho(\mathbf r) = \sum\_i^N |\varphi\_i(\mathbf r)|^2
\\]

上面的式子表示的都是能量，现在将它们对应到 Kohn-Sham 方程的 Hamiltonian 中

\\[
\hat{H}\_\text{KS} \Psi = E\_\text{KS} \Psi
\\]

-   显然动能算符是 \\(-\frac{\hbar^2}{2m}\nabla^2\\)
-   外场作用算符为 \\(v\_\text{ext}(\mathbf r) = \frac{\delta \int d\mathbf r v\_\text{ext}(\mathbf r) \rho(\mathbf r)}{\delta \rho}\\)
-   Hartree 作用算符为 \\(v\_\text{Ha}(\mathbf r) = \frac{\delta E\_\text{Ha}[\rho]}{\delta \rho}
        = \frac{e^2 \Delta V}{4\pi \epsilon} \int\frac{\rho(\mathbf r')}{\sqrt{(\mathbf r - \mathbf r')^2}} d\mathbf r'\\)
-   交换项算符为 \\(v\_\text{x}(\mathbf r) = \frac{\delta E\_\text{x}[\rho]}{\delta \rho} = -(\frac 3\pi)^{1/3} \rho^{1/3}\\)

此时 KS 方程和 Hamiltonian 可以展开为

\\[\begin{aligned}
\hat{H}\_\text{KS} &={} -\frac{\hbar^2}{2m}\nabla^2 + v(\mathbf r) \\\\
                  &={} -\frac{\hbar^2}{2m}\nabla^2 + v\_\text{ext}(\mathbf r) +
                        v\_\text{Ha}(\mathbf r) + v\_\text{x}(\mathbf r) \\\\
                  &={} -\frac{\hbar^2}{2m}\nabla^2 + v\_\text{ext}(\mathbf r) +
                    \frac{e^2}{4\pi \epsilon} \int\frac{\rho(\mathbf r')}{\sqrt{(\mathbf r - \mathbf r')^2}} d\mathbf r'
                    -(\frac 3\pi)^{1/3} \rho^{1/3}
\end{aligned}\\]

将 KS 方程的 Hamiltonian 写成矩阵形式，并对角化，即可得到 KS 轨道 \\(\varphi\_i\\) 和它们对应的能量 \\(E\_i\\) 。


## 程序实现 {#程序实现}

为方便起见，这里依然使用 Julia 来实现，请确保机器上的 Julia 已经装上了 Arpack 和 Plots 库。

```julia
using LinearAlgebra
using Arpack
using Printf
using PlotlyJS
```

同时既然是玩具，这里就在一维的空间里计算电子的波函数。这里用到的大部分基础知识在上篇文章
《使用数值方法求解单电子 Schrodinger 方程》 里都能找到（尤其是一维势箱模型系统的求解部分），
因此下面的介绍会有所简化。

这里在 \\([-5, 5]\\) 之间均匀取 200 个格点来表示整个系统所在的空间。

```julia
ngrid = 200
x = LinRange(-5, 5, ngrid)
```


### \\(\nabla^2\\) 的矩阵表示 {#nabla-2-的矩阵表示}

这个算符的矩阵表示在上一篇博客里已经讲过了，这里不再赘述:

\\[
\frac{d^2}{dx^2} = \frac{1}{\Delta x^2} \begin{bmatrix}
    -2 & 1 &   &  &   \newline
     1 & -2 & 1 &  &   \newline
      & 1 & -2 & \ddots &   \newline
      &   & \ddots & \ddots  & 1 \newline
      &   &   & 1 & -2
\end{bmatrix}
\\]

写成代码的形式即为

```julia
Δx = x[2] - x[1]
∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (2*Δx)
```


### 势能的表示 {#势能的表示}

一般情况下， Hamiltonian 里势能部分的贡献直接体现在对角线上，这里只给出一维形式的势能函数，然后会在所有势能计算好后一并加到 Hamiltonian 里。除此之外，由于取了模型势，电子质量和一些物理常数就直接取为 1 ，比如
\\(\frac{e^2}{8\pi\epsilon}\\) 和 \\(\frac{\hbar^2}{2m\_e}\\) 等。


#### 外场势能 \\(v\_\text{ext}(\mathbf r)\\) {#外场势能-v-text-ext--mathbf-r}

这里我们选择三个外场模型：无相互作用系统、无限深势阱系统和谐振子系统。

<!--list-separator-->

-  一维势箱系统

    在没有周期性边界条件的情况下， \\(v\_\text{ext}(x) = 0\\)

<!--list-separator-->

-  无限深势阱系统

    这里的“无限深”也等价于周围的墙壁无限高，即
    \\[
        v\_\text{ext}(x) = \begin{cases}
            \infty & x < -d \\\\
            0 & -d \le x \le d \\\\
            \infty & x > d
        \end{cases}
    \\]
    其中 \\(d\\) 就是中间势阱宽度，程序中取为 2 。 由于程序中无法直接表示值 \\(\infty\\) ，因此使用一个非常大的正实数来代替，
    这里取 \\(1.0\times 10^10\\) 这个值。

    ```julia
    V_well = fill(1e10, ngrid)
    @. V_well[-2 <= x <= 2] = 0
    ```

<!--list-separator-->

-  谐振子系统

    谐振子系统的势能是一条抛物线
    \\[
        v\_\text{ext}(x) = kx^2
    \\]

    出于简化的目的，这里 \\(k\\) 直接取为 1 。

    ```julia
    V_harm = x.^2
    ```

    以上三种势能函数画出来如下图所示：

    {{< figure src="/ox-hugo/simple-dft-potentials.svg" >}}


#### 电子密度 \\(\rho(\mathbf r)\\) {#电子密度-rho--mathbf-r}

Kohn-Sham 方程中包含电子之间库仑相互作用项（也称作 Hartree 项），和交换关联项，
而这两者都是电子密度的泛函，因此需要计算电子密度函数 \\(\rho(\mathbf r)\\) ：

首先应保证每个电子的波函数是正交归一的

\\[
\langle \phi\_i | \phi\_i \rangle = 1
\\]

然后电子密度函数为

\\[
\rho(x) = \sum\_n f\_n |\phi(x)|^2
\\]

其中 \\(f\_n\\) 表示第 \\(n\\) 个能级上的电子占据数，本文的体系目前暂不考虑电子的自旋，故
\\(f\_n\\) 的最大值可达到 2 。

根据上面公式，可以写出下面的代码

```julia
function get_density(fn::Vector{Float64}, ψ::Matrix{Float64}, Δx::Float64) ::Vector{Float64}
    # fn 是长度为 nlevel 的向量，表示电子的占据数函数
    # ψ 是一个 ngrid x nlevel 的矩阵

    # 首先来归一化波函数
    norms = sum(ψ.^2, dims=1) * Δx
    ψ ./= sqrt.(norms)

    # 求电子密度函数
    ρ = sum(ψ.^2 .* fn', dims=2)
    ρ = dropdims(ρ; dims=2)

    return ρ
end
```

我们求解不包含库仑势和交换关联势的 Schrodinger 方程后，求得波函数和电子密度如下图所示

{{< figure src="/ox-hugo/simple-dft-psi_rho.svg" >}}


#### 库仑势 \\(v\_\text{Ha}(\mathbf r)\\) {#库仑势-v-text-ha--mathbf-r}

库仑势的公式为：

\\[
v\_\text{Ha}(x) = \frac{e^2 \Delta x}{4\pi \epsilon} \int\frac{\rho(x')}{\sqrt{(x - x')^2}} dx'
\\]

在程序实现时，限于积分精度和除零的问题，分母中的 \\(\sqrt{(x - x')^2}\\) 需要加上一个小量 \\(\varepsilon\\)
避免除零的出现

\\[
v\_\text{Ha} = \int \frac{n\_j \Delta x}{\sqrt{(x - x')^2 + \varepsilon}} dx'
\\]

```julia
function get_hartree(ρ::Vector{Float64}, x::Vector{Float64}; eps=1e-1) ::Tuple{Float64, Vector{Float64}}
    Δx = x[2] - x[1]
    energy = sum((ρ * ρ' .* Δx^2) ./ sqrt.((x' .- x).^2 .+ eps)) / 2
    potential = collect(Iterators.flatten((sum(ρ' .* Δx ./ sqrt.((x' .- x).^2 .+ eps), dims=2))))
    return (energy, potential)
end
```


#### 交换关联势 {#交换关联势}

首先忽略关联势，使用 LDA 近似，得到交换势为

\\[
v\_\text{x}^\text{LDA}[\rho] = -\sqrt[3]{3\rho / \pi}
\\]

那么使用代码表示出来就很简单了：

```julia
function get_exchange(ρ::Vector{Float64}, Δx::Float64) ::Tuple{Float64, Vector{Float64}}
    energy = -3.0/4.0 * cbrt(3.0/π) * sum(ρ.^(4.0/3.0)) * Δx
    potential = -cbrt(3.0/π) .* (cbrt.(ρ))
    return (energy, potential)
end
```


### Hamiltonian 的构造 {#hamiltonian-的构造}

上面说到 Hamiltonian 里势能的部分体现在对角线上

\\[\hat{H} = \frac{1}{(\Delta x)^2}
\begin{bmatrix}
    -2 & 1 &   &  &   \newline
     1 & -2 & 1 &  &   \newline
      & 1 & -2 & \ddots &   \newline
      &   & \ddots & \ddots  & 1 \newline
      &   &   & 1 & -2
\end{bmatrix} +
\begin{bmatrix}
V\_1 & & & \newline
& V\_2 & & \newline
& & \ddots & \newline
& & & V\_n
\end{bmatrix} \\]

用代码写出来

```julia
function get_hamiltonian(x::Vector{Float64}, ρ::Vector{Float64},
                         v_ext::Vector{Float64}) ::Matrix{Float64}
    Δx = x[2] - x[1]
    ex_energy, ex_potential = get_exchange(ρ, Δx)
    ha_energy, ha_potential = get_hartree(ρ, x)
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)

    # Hamiltonian
    H = -∇²./2 + Diagonal(ex_potential .+ ha_potential .+ v_ext)

    return H
end
```

对这个 Hamiltonian 对角化，可以得到一系列波函数 \\(\phi\_i(x)\\) 。

```julia
E, ψ = eigs(H, nev=nlevel, which=:LM, sigma=0)  # 这个函数需要 using Arpack
```


### KS 方程的迭代求解 {#ks-方程的迭代求解}

电子密度 \\(\rho(x)\\) 依赖于波函数 \\(\phi\_i(x)\\) ，而求解 \\(\phi\_i(x)\\) 所用的 Hamiltonian 又反过来依赖于 \\(\rho(x)\\) ，
这意味着我们不能一次性求得正确的波函数 \\(\phi\_i(x)\\) ， 因此我们需要用迭代的方法来求解：

1.  先猜一个初始电荷密度 \\(\rho(x)\\) ；
2.  用 \\(\rho(x)\\) 构造 Hartree 势和交换关联势，然后构造 Hamiltonian ；
3.  对角化 Hamiltonian 求得本征值 \\(E\_i\\) 和波函数 \\(\phi\_i(x)\\) ；
4.  判断此次求得本征值 \\(E\_i\\) 与上一次结果相差是否足够小，如果是，则停止计算，否则进入第 5 步；
5.  使用波函数 \\(\phi\_i(x)\\) 构造电子密度 \\(\rho(x)\\) ，并返回第 2 步。

上面的过程也叫做自洽迭代(self-consistency loop)。

到这一步，我们把所有代码整合起来运行一下，便能得到一个简易的 DFT 玩具

```julia
#!/usr/bin/env julia

using LinearAlgebra
using Arpack
using Formatting
using Plots

# Some functions
function get_density(fn::Vector{Float64}, ψ::Matrix{Float64}, Δx::Float64) ::Vector{Float64}
    # fn 是长度为 nlevel 的向量，表示电子的占据数函数
    # ψ 是一个 ngrid x nlevel 的矩阵

    # 首先来归一化波函数
    norms = sum(ψ.^2, dims=1) * Δx
    ψ ./= sqrt.(norms)

    # 求电子密度函数
    ρ = sum(ψ.^2 .* fn', dims=2)
    ρ = dropdims(ρ; dims=2)

    return ρ
end

function get_hartree(ρ::Vector{Float64}, x::Vector{Float64}; eps=1e-1) ::Tuple{Float64, Vector{Float64}}
    Δx = x[2] - x[1]
    energy = sum((ρ * ρ' .* Δx^2) ./ sqrt.((x' .- x).^2 .+ eps)) / 2
    potential = collect(Iterators.flatten((sum(ρ' .* Δx ./ sqrt.((x' .- x).^2 .+ eps), dims=2))))
    return (energy, potential)
end

function get_exchange(ρ::Vector{Float64}, Δx::Float64) ::Tuple{Float64, Vector{Float64}}
    energy = -3.0/4.0 * cbrt(3.0/π) * sum(ρ.^(4.0/3.0)) * Δx
    potential = -cbrt(3.0/π) .* (cbrt.(ρ))
    return (energy, potential)
end

function get_hamiltonian(x::Vector{Float64}, ρ::Vector{Float64},
                         v_ext::Vector{Float64}) ::Matrix{Float64}
    Δx = x[2] - x[1]
    ex_energy, ex_potential = get_exchange(ρ, Δx)
    ha_energy, ha_potential = get_hartree(ρ, x)
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)

    # Hamiltonian
    H = -∇²./2 + Diagonal(ex_potential .+ ha_potential .+ v_ext)

    return H
end

if abspath(PROGRAM_FILE) == @__FILE__
    ngrid = 200
    nlevel = 20
    nelect = 17

    x = collect(LinRange(-5, 5, ngrid))
    Δx = x[2] - x[1]
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)

    # V_ext
    V_empty = zeros(ngrid)
    V_well = fill(1e10, ngrid); @. V_well[-2 <= x <= 2] = 0;
    V_harm = x.^2

    # construct fn
    fn = zeros(nlevel)
    fn[1:(nelect÷2)] .= 2
    if 1 == nelect % 2
        fn[nelect÷2+1] = 1
    end

    max_iter = 1000
    E_threshold = 1E-5

    log0 = Dict("E" => [Inf], "ΔE" => [Inf])  # Use `log0` instead of `log` to avoid confict

    # 使用自由电子的波函数做为初始猜测的电子波函数，可以加速收敛
    E, ψ = eigs(-∇²./2.0, nev=nlevel, which=:LM, sigma=0)
    ρ = get_density(fn, ψ, Δx)

    for i in 1:max_iter
        H = get_hamiltonian(x, ρ, V_harm)

        E0, ψ0 = eigs(H, nev=nlevel, which=:LM, sigma=0)
        E .= E0
        ψ .= ψ0

        E_tot = sum(E .* fn)  # 求占据态电子能量之和
        ΔE = E_tot - log0["E"][end]
        push!(log0["E"], E_tot)
        push!(log0["ΔE"], ΔE)
        printfmtln("step: {:5d} E: {:10.4f} ΔE {:14.10f}", i, log0["E"][end], log0["ΔE"][end])

        # 判断基能量是否收敛
        if abs(ΔE) < E_threshold
            println("converged!")
            break
        end

        # 更新电子密度
        ρ .= get_density(fn, ψ, Δx)
    end

    p = plot(x, ψ[:, 1:5], label=sprintf1.("%.3f", E[1:5]'), title="ψ")
end
```

它运行时会出现下面的日志输出（以 \\(V\_\text{ext} = V\_\text{empty}\\) 为例）：

```text
step:     1 E:   191.3250 ΔE           -Inf
step:     2 E:   188.6149 ΔE  -2.7101725428
step:     3 E:   189.9835 ΔE   1.3686497726
step:     4 E:   189.2422 ΔE  -0.7413493772
step:     5 E:   189.7313 ΔE   0.4891692181
step:     6 E:   189.4190 ΔE  -0.3123247101
step:     7 E:   189.6381 ΔE   0.2191170430
step:     8 E:   189.4893 ΔE  -0.1488193569
step:     9 E:   189.5950 ΔE   0.1057145189
step:    10 E:   189.5214 ΔE  -0.0735956265
step:    11 E:   189.5738 ΔE   0.0523625987
step:    12 E:   189.5369 ΔE  -0.0368426628
step:    13 E:   189.5631 ΔE   0.0262003363
step:    14 E:   189.5446 ΔE  -0.0185224236
step:    15 E:   189.5578 ΔE   0.0131633325
step:    16 E:   189.5484 ΔE  -0.0093260810
step:    17 E:   189.5551 ΔE   0.0066245797
step:    18 E:   189.5504 ΔE  -0.0046981797
step:    19 E:   189.5537 ΔE   0.0033362576
step:    20 E:   189.5513 ΔE  -0.0023672119
step:    21 E:   189.5530 ΔE   0.0016807098
step:    22 E:   189.5518 ΔE  -0.0011928024
step:    23 E:   189.5527 ΔE   0.0008468043
step:    24 E:   189.5521 ΔE  -0.0006010437
step:    25 E:   189.5525 ΔE   0.0004266762
step:    26 E:   189.5522 ΔE  -0.0003028617
step:    27 E:   189.5524 ΔE   0.0002149933
step:    28 E:   189.5523 ΔE  -0.0001526097
step:    29 E:   189.5524 ΔE   0.0001083320
step:    30 E:   189.5523 ΔE  -0.0000768987
step:    31 E:   189.5523 ΔE   0.0000545872
step:    32 E:   189.5523 ΔE  -0.0000387486
step:    33 E:   189.5523 ΔE   0.0000275059
step:    34 E:   189.5523 ΔE  -0.0000195251
step:    35 E:   189.5523 ΔE   0.0000138599
step:    36 E:   189.5523 ΔE  -0.0000098385
converged!
```

和前面一样，把波函数和电子密度函数画出来，如下图所示：

{{< figure src="/ox-hugo/simple-dft-psi_rho_dft.svg" >}}

下面以 \\(V\_\text{empty}\\) 为例，对比一下原来的波函数与 DFT 方法算出的 KS 波函数的变化：

{{< figure src="/ox-hugo/simple-dft-psi_org_dft.svg" >}}

可以看到， KS 波函数的空间分布与原来无相互作用波函数空间分布差别很大， KS 波函数的波包的顶点都发生了偏移，说明库仑相互作用和交换相互作用影响较大。例如 \\(\psi\_1\\) ，无相互作用体系里波函数分布最大的地方在 \\(x=0\\) 处，但 KS 波函数里空间分布最大的地方在 \\(x=\pm 4.2\\) 处左右，表明其它能级更高的电子对它的分布也产生了显著的影响。除此之外，波函数的本征值也变化巨大。实际上这里的对比不太严谨：原来无相互作用体系的波函数是一个电子在不同能级的波函数，而 KS 波函数则被当成是一个含有 N 个电子的体系里每个电子的波函数，这两者概念上的差异不能忽略。

需要注意的是，尽管我们习惯用 KS 轨道表示真实体系里每个电子的轨道，但 KS 轨道实质上仍是单粒子
Schrodinger 方程的解，它能否代替体系真实的波函数仍需要 check ，本人不认为这两者等价。比如在
 Ren Xinguo 老师的课件[^fn:2]
 里是这样描述的

> KS orbitals are auxiliary variables, and have no strict physical meaning (except for HOMO and LUMO).

即除了 HOMO 和 LUMO 之外， KS 波函数仅仅作为计算电子密度函数 \\(\rho(\text r)\\) 的辅助函数之用。
HOMO 和 LUMO 在一定程度上可以视作体系的真实轨道，此时体系的第一电离能即为 HOMO 的能量（Janak theorem, 1978）：

\\[
I = E\_0(N-1) - E\_0(N) = -\epsilon\_N
\\]

下面来看一下电子密度函数的变化：

{{< figure src="/ox-hugo/simple-dft-rho_org_dft.svg" >}}

很明显，经过自洽迭代后，体系的电子密度分布也发生了变化，对比占据态轨道的变化而言，电子密度的变化还是比较小的。

如果考虑电子的自旋，我们需要修改交换关联泛函，即使用考虑电子自旋的 LSDA 泛函，此时体系的波函数表示也需要随之修改， \\(\psi\_i(x)\\) 变为 \\(\psi\_i(x, \sigma)\\) ，即增加了一个自旋维度 \\(\sigma\\) 。
具体的泛函形式比较复杂，这里作为一个 toy 介绍就不展开了，如果有兴趣可以去看 [Ren Xinguo 老师的课件](http://lqcc.ustc.edu.cn/renxg/plus/list.php?tid=7)。


## 总结与拓展 {#总结与拓展}

我们实现了一个简单的 DFT 计算程序，它可以使用自定义的外场势能函数，考虑 Hartree 势，并使用 LDA 近似。
通过求解 KS 方程，我们得到了 KS 波函数，并与无相互作用体系的波函数作对比，发现波函数的分布发生了显著的变化，同时波函数的能量也发生了不小的变化。在实现的过程中，本人对那句“通过 DFT 将多体系统映射到单粒子系统”
可能有了一些很浅薄的理解。

尽管这是一个很简单的 toy ，但它也是包含了 DFT 计算所需的各种常见操作，比如构造电子密度函数，比如自洽迭代求解 KS 方程，再比如求 Hartree 势函数、使用 LDA 近似等等，这些都可以在常见的 DFT 软件里找到，那么此次 DIY 的过程也能加强对其它成熟 DFT 软件里运行时做了什么有了大概了理解。如果有人想要进一步拓展这个 toy ，我想到了以下几个方向：

-   考虑上下自旋，使用 LSDA 近似
-   使用 GGA 泛函（比如 PBE 泛函）
-   考虑外加电场，这个比较好办，直接在修改外场势函数即可
-   考虑外加磁场，这个需要修改 Hamiltonian 中的动能项表达式，添加矢势项
-   考虑相对论效应，使用 Dirac 方程代替 Schrodinger 方程，看是否能算出自旋轨道耦合效应
-   ......

出于精力限制，本人可能没动力继续往下扩展，读者如果有兴趣，可以自行尝试。

[^fn:1]: tamuhey 的代码 <https://github.com/tamuhey/python_1d_dft>
[^fn:2]: 任老师的课件 <http://lqcc.ustc.edu.cn/renxg/plus/list.php?tid=7>
