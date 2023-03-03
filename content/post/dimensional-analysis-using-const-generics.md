---
title: "利用 Const Generics 实现编译期量纲分析"
date: 2023-02-27T22:39:00+08:00
tags: ["Posts", "Rust", "ConstGenerics"]
categories: ["Programming"]
draft: false
---

<div class="ox-hugo-toc toc">

<div class="heading">Table of Contents</div>

- [什么是量纲分析](#什么是量纲分析)
- [什么是 Const Generics](#什么是-const-generics)
- [如何使用 Const Generics 实现量纲分析](#如何使用-const-generics-实现量纲分析)

</div>
<!--endtoc-->

开学前折腾了一段时间的 Rust const generics ，也读了一些前人的代码，并自己写出了自己的编译期量纲分析代码，
因此吸收总结这一过程所得知识，产生了这篇博文。

<!--more-->


## 什么是量纲分析 {#什么是量纲分析}

这里浅薄地介绍一下什么是量纲分析。贴一下 Wiki 上关于量纲和量纲分析的定义：

1.  量纲是表示一个物理量由基本量组成的情况。确定若干个基本量后，每个派生量都可以表示为基本量的幂的乘积的形式，
    引入量纲分析可以进行量纲分析，这既是物理学的基础，又有很多重要的应用。通常一个物理量的量纲是由像质量、
    长度、时间、电荷量、温度一类的基础量纲结合而成；
2.  量纲分析是指对数学或者物理学中物理量的量纲可以用来分析或检验几个物理量之间的关系。
    在判断一个由推导获得的方程式或计算结果是否合理时，可以对等号两边的量纲进行化简，从而确认是否一致，这个过程
    即用到了量纲分析。对于较为复杂的情况，量纲分析也可以用来建立合理的假设，然后用严格的实验加以验证，或用已
    发展成功的理论来仔细推敲。

由于目前的基本物理量有七个，故在量纲中分别用七个字母表示它们的量纲，分别为：

-   长度（L）
-   质量（M）
-   温度（Θ）
-   电流（I）
-   时间（T）
-   物质的量（N）
-   发光强度（J）

任何一个物理量 \\(A\\) 都可以写出下列量纲式：
\\[
    \text{dim} A = L^{\alpha} M^{\beta} \Theta^{\gamma} I^{\delta} T^{\epsilon} N^{\zeta} J^{\eta}
\\]
如果一个物理量的量纲中所有的指数为 0 ，那么称它为无量纲量，常见的无量纲量有精细结构常数 \\(\alpha \approx 1/137\\) 、
雷诺数 \\(\text{Re} = \frac{\rho VL}{\mu} = \frac{VL}{\nu}\\) 以及各种比值、概率等。
两个物理量量纲一致是它们能够相加减的必要条件，而不是充要条件，比如力矩和能量的量纲都是 \\(F \cdot L\\) ，但这两个量显然无法相加减。物理量的乘除乘方开方则没有这个限制，直接按照相应的代数运算法则对各个基本量纲处理再化简即可。

值得注意的是，能放在指数和真数位置上的物理量一定是无量纲量。回想一下统计力学中几乎无处不在的
\\( \frac{E}{k\_{\mathrm{B}} T}\\) ，其中分母 \\(k\_B T\\) 的量纲是能量，刚好与分子上 \\(E\\) 相抵消，导致指数整体是一个无量纲量，进而使得 \\( \frac{E}{k\_{\mathrm{B}} T}\\) 这个整体也是一个无量纲量；又比如在化学反应中常见的公式
\\(\Delta G = \Delta G^{\ominus} + RT \ln K\\) ，其中化学平衡常数 \\(K\\) 处于真数的位置，它一定是一个无量纲量。

此时，我们可以大致总结一下量纲分析运算的规则：

1.  物理量的量纲由 7 个基本量纲构成；
2.  具有相同量纲的物理量才能相加减；
3.  物理量在乘除、乘方和开方时基本量纲的指数遵循代数运算法则；
4.  处于指数、真数位置的物理量是无量纲量。

这些规则是我们程序实现量纲分析的参考。


## 什么是 Const Generics {#什么是-const-generics}

Const generics 翻译过来即为常量泛型。在涉及 Rust 泛型代码时，如果泛型参数是一个常量值，而不是类型或生命周期参数等，那么这个泛型参数就称为常量泛型参数。例如下面一段代码就用到了泛型参数

```rust
struct Position<T, const N: usize> {    // N 即为常量泛型参数
    pos: [T; N]
}
```

上面代码中 `const N: usize` 中的 `const` 前缀很贴心地告诉你后面的 `N` 是一个泛型参数，而 `: usize` 则表明
`N` 的类型是 `usize` 。这段代码定义了一个泛型的 `struct` ，其中包含一个名为 `pos` 的数组成员，这个数组元素的类型由 `T` 决定，而长度由常量泛型参数 `N` 决定。注意，这里面的 `T` 和 `N` 都是编译期参数，也就是说它们在编译期就已经确定，由于 Rust 是一门静态语言，所有变量的类型在编译成机器码时都是可以被推导出来的，
我们不能用一个程序运行期的变量（比如一个用户输入的值）作为 `T` 或 `N` ，这是不被允许，并且编译器也无法做到的

那么 Rust 为什么要添加 `const generics` 这个特性呢？其中的原因在 [RFC#2000](https://rust-lang.github.io/rfcs/2000-const-generics.html) 已经写得很清楚了，简单来说就是
Rust 将 `[T; 1]` 、 `[T; 2]` 、 `[T;3]` ……这样不同长度的数组看做不同的类型，那么在实现一些操作时就会显得很脏，比如[早期版本的 Rust 标准库](https://doc.rust-lang.org/1.37.0/std/primitive.array.html#impl-Eq)在实现比较两个定长数组是否相等的特质 `Eq` 时就分别对 `[T; 0]` 、 `[T; 1]` 、
 `[T; 2]` 等等的定长数组各自实现，一直到 `[T; 32]` 。那么如果你有一个长度大于 32 的定长数组需要比较时怎么办？
比如这样的代码

```rust
fn compare(lhs: &[i32; 33], rhs: &[i32; 33]) -> bool {
    lhs == rhs
}
```

编译器会直接报错罢工，而如果把两个 `33` 全部换成 `32` 则可以正常编译，是不是感觉非常不可思议？当然这个问题在 2021
年 3 月份 [const generics 稳定后](https://blog.rust-lang.org/2021/02/26/const-generics-mvp-beta.html)就已经被解决了。在 Rustc 1.51 以后，你可以对任意长度的 `[T; LEN]` 运行比较，以及其它相关的操作，再也不用担心编译器摆烂。

除了解决定长数组的相关问题， const generics 还有其它很多有用的地方，比如可以实现编译期的计算（写 C++
的同学可能已经开始狂喜了，别高兴太早，用 ~~Ruast~~ 的 const generics 来写类似 C++ 的模板元编译期计算会非常地痛苦，
建议不要尝试）等。有一个相对关键的点在于，泛型参数只存在于编译期，也就是说在运行期这个参数不存在。这也意味着常量泛型参数自己并不占内存，比如

```rust
struct Foo<const N: usize> {
    value: i64,
}
```

这个结构体的大小用 `std::mem::size_of::<Foo<1>>()` 求出来是 `8` ，正好等于 `i64` 本身的大小；事实上，不管
`N` 取多少，甚至 `std::mem::size_of::<Foo<114514>>()` ，得到的仍然是 `8` ，这为编译器的优化提供了可能。

除此之外，当 `N` 不同时， `Foo<N>` 被认为是不同的类型。即使你分别为 `Foo<N1>` 和 `Foo<N2>` 分别实现了相同的特质（这里以 `Eq` 为例），那么当你写下 `Foo::<N1>::default() =` Foo::&lt;N2&gt;::default()= 这样的代码时，除非 `N1 =` N2=
否则编译器会报错提醒你：

```rust
#[derive(Default, PartialEq, Eq)]
struct Foo<const N: usize> {
    value: i64,
}

fn main() {
    println!("{}", Foo::<0>::default() == Foo::<1>::default());
}
// error[E0308]: mismatched types
//  --> src/main.rs:7:43
//   |
// 7 |     println!("{}", Foo::<0>::default() == Foo::<1>::default());
//   |                                           ^^^^^^^^^^^^^^^^^^^ expected `0`, found `1`
//   |
//   = note: expected struct `Foo<0>`
//              found struct `Foo<1>`
```

这个特性对于实现编译期量纲分析是至关重要的，可以说如果没有这个特性，编译期的量纲分析就无法实现。


## 如何使用 Const Generics 实现量纲分析 {#如何使用-const-generics-实现量纲分析}

在阐述如何使用 const generics 实现编译期量纲分析之前，我们先来了解一下运行期量纲分析有啥缺点。

为了描述量纲，我们需要定义一个结构体来储存七个基本量纲的指数，为了方便实现，这里直接取国际单位制：

```rust
#[derive(Default, PartialEq, Eq)]   // make SiUnit::default() and SiUnit == SiUnit possible
pub struct SiUnit {
      m: i8,    // meter
      s: i8,    // second
     kg: i8,    // kilogram
      c: i8,    // coulomb
     cd: i8,    // candela
    mol: i8,    // mole
      k: i8,    // kelvin
}

impl SiUnit {
    pub fn new() -> Self {
        SiUnit::default()
    }
}
```

然后这个结构体需要实现加减运算特质，以满足两个物理量乘除时对量纲的运算：

```rust
use std::ops::{Add, Sub, Mul, Div};   // required trait for overload of `+` and `-`.

impl Add for SiUnit {
    type Output = Self;     // required associate type
    fn add(self, rhs: Self) -> Self::Output {
        SiUnit {
              m: self.m    + rhs.m,
              s: self.s    + rhs.s,
             kg: self.kg   + rhs.kg,
              c: self.c    + rhs.c,
             cd: self.cd   + rhs.cd,
            mol: self.mol  + rhs.mol,
              k: self.k    + rhs.k,
        }
    }
}

impl Sub for SiUnit {
    type Output = Self;     // required associate type
    fn sub(self, rhs: Self) -> Self::Output {
        ...
    }
}
```

这样我们就可以直接执行 `SiUnit + SiUnit` 、 `SiUnit - SiUnit` 这样的操作了。

为了实现物理量的乘方开方运算，它还需要实现 `Mul` 和 `Div` 特质，与实现 `Add`
和 `Sub` 特质不同的是， `Mul` 和 `Div` 特质里的右操作数 `Rhs` 都是 `i8`
类型，而不是 `SiUnit` 本身，因为乘方开方的指数都是没有量纲的。

```rust
use std::ops::{Mul, Div};

impl Mul<i8> for SiUnit {
    type Output = Self;
    fn mul(self, rhs: i8) -> Self::Output {
        SiUnit {
              m: self.m    * rhs,
              s: self.s    * rhs,
             kg: self.kg   * rhs,
              c: self.c    * rhs,
             cd: self.cd   * rhs,
            mol: self.mol  * rhs,
              k: self.k    * rhs,
        }
    }
}

impl Div<i8> for SiUnit {
    type Output = Self;
    fn div(self, rhs: i8) -> Self::Output {
        SiUnit {
            ...
        }
    }
}
```

此时， `SiUnit` 可以进行 `SiUnit * 2` 、 `SiUnit / 2` 这样的运算了。那么把和一个值打包在一起就组成一个物理量了：

```rust
pub struct PhysicalQuantity<T> {
    value: T,
    unit:  SiUnit,
}
```

然后我们再为它实现各种运算操作，就可以用它代入各种公式求值了。那么这其中有什么问题呢？

1.  它占用的内存太多。用 `std::mem::size_of::<PhysicalQuantity<f64>>()` 查看一下这个结构体占用的内存，
    为 16 字节，这说明不参与值运算的 `unit` 成员就占用了一半的空间；如果对一个 `[PhysicalQuantity; len]`
    这样的数组运算，那么所有元素的 `unit` 成员就交错分布在真正需要运算的 `value` 成员中间，这对 CPU
    的缓存命中和 SIMD 优化是非常不利的，进而造成可观的性能损失；
2.  `PhysicalQuantity` 之间没有区分，也就是说 `unit` 不同的 `PhysicalQuantity` 被认为是同一个类型，
    当它们被放在同一个数组等线性表里时，编译器不会报错，而且人工检查也只能在运行时进行；
3.  `PhysicalQuantity` 在执行加减运算时需要手动检查 `unit` 是否一致；在执行乘除法时，需要对 `unit` 运行相应
    的运算，这些均在运行时进行，并且每个元素操作时都要做，这也会严重降低运行效率。
