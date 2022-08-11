---
title: "简易 DFT 玩具"
date: 2022-08-10T23:32:00+08:00
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

</div>
<!--endtoc-->

一直在用别人写好的 DFT 软件，对软件的运行过程略有兴趣，查阅资料弄懂了一些运行原理并参考了前人的 code 后，这次我们来自己写一个 DFT 的玩具～

<!--more-->


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
using Plots
using Printf
plotly()  # 使用 plotly() 作为绘图后端
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
function integrate(y::Matrix{Float64}, Δx::Float64) ::Vector{Float64}
    # y 是一个 ngrid x nlevel 的矩阵，其中每一列表示一个电子的波函数
    # Δx 表示空间格点的长度，前文中定义为 x[2] - x[1]
    return sum(y, dims=1) * Δx
end

function get_density(fn::Vector{Float64}, ψ::Matrix{Float64}, Δx::Float64) ::Vector{Float64}
    # fn 是长度为 nlevel 的向量，表示电子的占据数函数
    # ψ 是一个 ngrid x nlevel 的矩阵

    # 首先来归一化波函数
    norms = sum(ψ.^2, dims=1) * Δx
    ψ ./= sqrt.(norms)

    # 求电子密度函数
    ρ = sum(ψ.^2 .* fn', dims=2)

    return ρ
end
```


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
function get_hartree(ρ::Vector{Float64}, x::Vector{Float64}; eps=1e-4) ::Tuple{Float64, Vector{Float64}}
    Δx = x[2] - x[1]
    energy = sum((ρ * ρ' .* Δx^2) ./ sqrt((x' .- x).^2 + eps)) / 2
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
function hamiltonian(x::Vector{Float64}, ρ::Vector{Float64}, v_ext::Vector{Float64}) ::Matrix{Float64}
    Δx = x[2] - x[1]
    ex_energy, ex_potential = get_exchange(ρ, Δx)
    ha_energy, ha_potential = get_hartree(ρ, x)
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (2*Δx)

    # Hamiltonian
    H = -∇² + Diagonal(ex_potential + ha_potential + v_ext)

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
5.  使用波函数 \\(\phi\_i(x)\\) 构造电子密度 \\(\rho(x)\\) ，并返回第 2 步，直至求得本征值收敛。

上面的过程也叫做自洽迭代(self-consistency loop)。
