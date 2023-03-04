---
title: "利用 Const Generics 实现编译期量纲分析"
date: 2023-03-04T22:46:00+08:00
tags: ["Posts", "Rust", "ConstGenerics"]
categories: ["Programming"]
draft: false
---

<div class="ox-hugo-toc toc">

<div class="heading">Table of Contents</div>

- [什么是量纲分析](#什么是量纲分析)
- [什么是 Const Generics](#什么是-const-generics)
- [如何使用 Const Generics 实现量纲分析](#如何使用-const-generics-实现量纲分析)
    - [运行期量纲分析](#运行期量纲分析)
    - [利用 const generics 实现编译期的量纲分析](#利用-const-generics-实现编译期的量纲分析)
        - [`SiUnit` 的编译期运算](#siunit-的编译期运算)
        - [`PhysicalQuantity` 的加减法运算](#physicalquantity-的加减法运算)
        - [`PhysicalQuantity` 的乘除法运算](#physicalquantity-的乘除法运算)
        - [`PhysicalQuantity` 的乘方开方运算](#physicalquantity-的乘方开方运算)
        - [无量纲数及常系数的特殊处理](#无量纲数及常系数的特殊处理)
        - [其它实现](#其它实现)
- [总结](#总结)

</div>
<!--endtoc-->

开学前折腾了一段时间的 Rust const generics ，也读了一些前人的代码，并自己写出了自己的编译期量纲分析代码，
因此吸收总结这一过程所得知识，产生了这篇博文。本文的实现全部代码在[这里](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=4807be24f1e6493bcc5c7cb86457439c)。

<!--more-->


## 什么是量纲分析 {#什么是量纲分析}

这里浅薄地介绍一下什么是量纲分析。贴一下 Wiki[^fn:1] 上关于量纲和量纲分析的定义：

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


### 运行期量纲分析 {#运行期量纲分析}

为了描述量纲，我们需要定义一个结构体来储存七个基本量纲的指数，为了方便实现，这里直接取国际单位制：

```rust
#[derive(Default, PartialEq, Eq, Clone, Copy)]   // make SiUnit::default() and SiUnit == SiUnit possible
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

如此这些缺陷在 const generics 的加持下都可以解决。


### 利用 const generics 实现编译期的量纲分析 {#利用-const-generics-实现编译期的量纲分析}

为了让编译器在编译期帮助我们推导量纲，我们可以利用 const generics ，把量纲信息放在泛型参数里，如下所示：

```rust
#![feature(adt_const_params)]

use num::Num;

#[derive(PartialEq)]
pub struct PhysicalQuantity<T, const U: SiUnit>
where T: Num
{
    value: T,
}

impl<T, const U: SiUnit> PhysicalQuantity<T, U>
where T: Num,
{
    pub fn new(value: T) -> Self {
        Self { value }
    }
}
```

需要注意的是，在现在 Rustc 最新稳定版(1.67)里，只能支持整数、 `bool` 以及 `char` 作为 const generic params ，
想要放结构体进去需要切换到 nightly 频道，并在代码开头加上 `#![feature(adt_const_params)]` 来开启 `adt_const_params`
这个 feature ，从而支持把 `SiUnit` 放到泛型参数里。此时，运行 `std::mem::size_of<PhysicalQuantity<f64, SiUnit::default()>>()` ，
输出为 8 ，说明没有多余的空间占用，第一个问题得以解决。

为了方便起见，我们定义一些类型别名

```rust
const METER: SiUnit = SiUnit {
      m: 1,
      s: 0,
     kg: 0,
      c: 0,
     cd: 0,
    mol: 0,
      k: 0,
};
type Meter<T> = PhysicalQuantity<T, Meter>;

const METER_PER_SEC: SiUnit = SiUnit {
      m:  1,
      s: -1,
     kg:  0,
      c:  0,
     cd:  0,
    mol:  0,
      k:  0,
};
type Mps<T> = PhysicalQuantity<T, METER_PER_SEC>;
```

然后比较一个两个量纲不同的量，看会有什么反应

```rust
let a = Meter::<f64> { value: 1.0 };
let b = Mps::<f64> {value: 2.0};
assert_ne!(a, b);   // cannot compile
// error[E0308]: mismatched types
//   --> src/main.rs:54:5
//    |
// 54 |     assert_ne!(a, b);   // cannot compile
//    |     ^^^^^^^^^^^^^^^^ expected `SiUnit { m: 1, s: 0, kg: 0, c: 0, cd: 0, mol: 0, k: 0 }`, found `SiUnit { m: 1, s: -1, kg: 0, c: 0, cd: 0, mol: 0, k: 0 }`
//    |
//    = note: expected struct `PhysicalQuantity<_, SiUnit { m: 1, s: 0, kg: 0, c: 0, cd: 0, mol: 0, k: 0 }>`
//               found struct `PhysicalQuantity<_, SiUnit { m: 1, s: -1, kg: 0, c: 0, cd: 0, mol: 0, k: 0 }>`
//    = note: this error originates in the macro `assert_ne` (in Nightly builds, run with -Z macro-backtrace for more info)

// For more information about this error, try `rustc --explain E0308`.
```

此时，编译器拒绝编译，并给出了错误信息，其中明确说明参数 `b` 存在类型错误，从而避免用户强行将两者放在一起比较。
这也表明只要量纲一致，那么类型肯定一致；反之如果量纲不一致，类型也一定不同，这可以将用户的编码错误提前到编译期暴露出来。
以上只是一个示例，下面我们来为 `PhysicalQuantity` 实现更多功能。


#### `SiUnit` 的编译期运算 {#siunit-的编译期运算}

首先，我们需要在编译期对 `SiUnit` 进行运算，之前的 `impl Add for SiUnit { ... }` 是为 `SiUnit` 实现一个函数，
然而这个函数只能在运行期跑，如何解决？这里就要用到 nightly 的另一个不稳定特性 `const_trait_impl` ，然后
`impl const Add for SiUnit` 就可以了：

```rust
#![feature(const_trait_impl)]

impl const Add for SiUnit { ... }
impl const Sub for SiUnit { ... }
impl const Mul<i8> for SiUnit { ... }
impl const Div<i8> for SiUnit { ... }
```


#### `PhysicalQuantity` 的加减法运算 {#physicalquantity-的加减法运算}

然后我们来考虑为 `PhysicalQuantity` 实现各种运算。我们先为它实现最为简单的加减运算，由于加减运算的两个操作数量纲一致，
类型肯定相同，那么实现加减法就不需要对 `SiUnit` 进行运算：

```rust
impl<T, const U: SiUnit> Add for PhysicalQuantity<T, U>
where T: Num,
{
    type Output = PhysicalQuantity<T, U>;
    fn add(self, rhs: Self) -> Self::Output {
        Self::Output {
            value: self.value + rhs.value
        }
    }
}

impl<T, const U: SiUnit> Sub for PhysicalQuantity<T, U>
where T: Num,
{
    type Output = PhysicalQuantity<T, U>;
    fn sub(self, rhs: Self) -> Self::Output {
        Self::Output {
            value: self.value - rhs.value
        }
    }
}
```


#### `PhysicalQuantity` 的乘除法运算 {#physicalquantity-的乘除法运算}

而 `PhysicalQuantity` 的乘除法不要求左右操作数量纲一致，并且产生的结果可能有着第三种量纲，因此在实现乘除法的特质时会稍微麻烦一点，也会用到本文提到的第三个不稳定特性 `const_trait_impl` ，它支持在 const generic params 里写表达式，
而这个表达式则需要用花括号包起来，比如像 `PhysicalQuantity<T, {U+V}>` 这样：

```rust
#![feature(generic_const_exprs)]

impl<T, const U: SiUnit, const V: SiUnit> Mul<PhysicalQuantity<T, V>> for PhysicalQuantity<T, U>
where
    T: Num,
    PhysicalQuantity<T, {U+V}>:,    // generic_const_exprs used
{
    type Output = PhysicalQuantity<T, {U+V}>;
    fn mul(self, rhs: PhysicalQuantity<T, V>) -> Self::Output {
        Self::Output {
            value: self.value * rhs.value
        }
    }
}


impl<T, const U: SiUnit, const V: SiUnit> Div<PhysicalQuantity<T, V>> for PhysicalQuantity<T, U>
where
    T: Num,
    PhysicalQuantity<T, {U-V}>:,    // generic_const_exprs used
{
    type Output = PhysicalQuantity<T, {U-V}>;
    fn div(self, rhs: PhysicalQuantity<T, V>) -> Self::Output {
        Self::Output {
            value: self.value / rhs.value
        }
    }
}
```

上面的代码的每个特质的实现中，除了 `T` 之外，一共有三个泛型，分别是 `U` 、 `V` 和 `U±V` ，而在 `impl<>` 只能写 `U` 和 `V`
这两个参数（ `U` 属于 `PhysicalQuantity` ， `V` 存在于 `Mul<Rhs>` 中的 `Rhs` 内），那么 `U±V` 就只能放在 `where` 里进行约束了。

那么，为什么不直接 `where {U±V}:,` 这样来约束呢，那是因为现在编译器还不够强，不支持这样写，如果 `U` 和 `V` 是 `usize` 类型，
官方支持 `where [(); {U±V}]:,` 这样来进行约束。但不幸的是，这里的 `U` 和 `V` 是 `SiUnit` 类型，除非你为它实现了转换到 `usize`
的特质，然后写 `where [(); {U±V}.into::<usize>()]:,` 这样的约束条件。除了这个选择，我们可以直接约束 `PhysicalQuantity<T, {U±V}>`
这个类型本身，幸运的是， rustc 确实接受这样的写法，谢天谢地。

顺便吐槽一下， `generic_const_exprs` 所支持的表达式十分有限，甚至当 `U` 和 `V` 为 `usize` 时， `{U+V}` 和 `{V+U}` 被认为是不等价的，
这也意味着我们在写表达式时需要十分小心表达式的顺序，如果写错的话，编译器吐出来的东西可能会非常难看……

言归正传，经过上面的实现后，我们可以对不同量纲的物理量进行乘除运算了，比如：

```rust
let a = Meter::<f64> { value: 1.0 };
let b = Mps::<f64> { value: 2.0 };
let c = a / b;
println!("type: {}, value: {}", std::any::type_name_of_val(&c), c.value);
// type: playground::PhysicalQuantity<f64, playground::SiUnit { m: 0, s: 1, kg: 0, c: 0, cd: 0, mol: 0, k: 0 }>, value: 0.5
```

在打印出 `c` 的类型后，它的量纲确实是时间，说明我们的实现是正确的。


#### `PhysicalQuantity` 的乘方开方运算 {#physicalquantity-的乘方开方运算}

到现在为止，我们已经为 `PhysicalQuantity<T, U>` 实现了四则运算。相比于前面的实现，乘方、开方的运算要更麻烦一些，因为返回值的量纲取决于指数，等于说返回的类型取决于指数，这要求我们必须把指数放在 `const generics param` 的位置上，否则存在于运行期的指数无论如何也无法让编译器在编译期推导出返回类型。特质 `num::pow::Pow` 定义了 `.pow()` 函数，但这个函数的签名中指数存在于第二个函数参数的位置上，而不是常量泛型参数的位置上，因此不能使用；尽管如此，我们仍可以照猫画虎，仿照 `num::pow::Pow`
来自己定义一个特质 `Power` ：

```rust
pub trait PowerI<const power: i8> {
    type Output;    // 关联类型
    fn powi(self) -> Self::Output;
}
```

然后为 `PhysicalQuantity` 实现它

```rust
impl<T, const U: SiUnit, const power: i8> PowerI<power> for PhysicalQuantity<T, U>
where
    T: Num + Pow<i8, Output = T>,
    PhysicalQuantity<T, {U*power}>:,
{
    type Output = PhysicalQuantity<T, {U*power}>;
    fn powi(self) -> Self::Output {
        Self::Output {
            value: self.value.pow(power)
        }
    }
}
```

最后，我们应该怎样调用它呢？经过与 rustc 的搏斗，我发现主要有以下两种写法：

1.  `let f2 = <Meter<f64> as PowerI<2>>::powi(f);`
2.  `let f2 = PowerI::<2>::powi(f);`

第 1 种写法看着就令人头疼，第 2 种写法稍微好一些，但也只是五十步笑百步。造成写法如此难看的原因是指数 `power`
被放在了 `trait` 的泛型参数里，而不是 `fn powi<power>(self) ...`  这个函数的泛型参数里。但是，如果将 `power`
写在 `fn powi()` 里，那么当你在实现时不得不面对 [E0207 错误](https://doc.rust-lang.org/error_codes/E0207.html) ：

```rust
pub trait PowerI {
    type Output;
    fn powi<const power: i8>(self) -> Self::Output;
}

impl<T, const U: SiUnit, const power: i8> PowerI for PhysicalQuantity<T, U>
where
    T: Num + Pow<i8, Output = T>,
    PhysicalQuantity<T, {U*power}>:,
{
    type Output = PhysicalQuantity<T, {U*power}>;
    fn powi(self) -> Self::Output
    {
        Self::Output {
            value: self.value.pow(power)
        }
    }
}
//     |
// 182 | impl<T, const U: SiUnit, const power: i8> PowerI for PhysicalQuantity<T, U>
//     |                          ^^^^^^^^^^^^^^^ unconstrained const parameter
//     |
//     = note: expressions using a const parameter must map each value to a distinct output value
//     = note: proving the result of expressions other than the parameter are unique is not supported
```

这个报错告诉我们常量泛型参数 `power` 必须出现在 `impl<...> Trait<...> for Object<...>` 的后两个尖括号内，
或者直接出现 `where` 约束的从句里，以表达式的形式出现则不被接受。上面代码里就是因为
`where PhysicalQuantity<T, {U*power}>` 中 `power` 是以表达式的形式出现而被拒绝编译，以笔者水平，看来这条路是走不通了。

那有没有简单、直接点的实现，让我们可以 `f.powi::<power>()` 呢？当然有的，直接 `impl` ，给 `PhysicalQuantity`
添加方法即可：

```rust
impl<T, const U: SiUnit> PhysicalQuantity<T, U>
where
    T: Num + Pow<i8, Output = T>,
{
    fn powi<const power: i8>(self) -> PhysicalQuantity<T, {U*power}> {
        PhysicalQuantity::<T, {U*power}> {
            value: self.value.pow(power)
        }
    }
}
```

这样就能使用 `let f2 = f.powi::<2>()` 来求得 `f` 的平方了，看起来这样的实现既简单，效果也好 ~~所谓大道至简，也不过如此吧2333~~ 。
至于开方，它和乘方的实现几乎一致，这里限制 `T` 为浮点数类型，为了使返回类型 `T` 与输入类型 `T` 一致：

```rust
impl<T, const U: SiUnit> PhysicalQuantity<T, U>
where
    T: Float + From<f64>,
{
    fn nth_root<const root: i8>(self) -> PhysicalQuantity<T, {U/root}> {
        PhysicalQuantity::<T, {U/root}> {
            value: self.value.powf((1.0f64 / root as f64).into())
        }
    }
}
```

然后就可以 `f.nth_root::<3>()` 来求 `f` 的立方根了。


#### 无量纲数及常系数的特殊处理 {#无量纲数及常系数的特殊处理}

有时公式中还会出现无量纲系数直接相乘的情况，比如 \\(\frac{1}{4\pi \epsilon}\\) ，
这时如果把 \\(4\pi\\) 手动写成 `PhysicalQuantity::<T, U>::new(4.0 * pi)` 的形式，未免过于冗长。这种情况下，我们需要为直接数
`T` 实现到无量纲 `PhysicalQuantity` 类型的转换特质：

```rust
const DIMENSIONLESS: SiUnit = SiUnit {
      m: 0,
      s: 0,
     kg: 0,
      c: 0,
     cd: 0,
    mol: 0,
      k: 0,
};
type Dimensionless<T> = PhysicalQuantity<T, DIMENSIONLESS>;

impl<T> From<T> for Dimensionless<T>
where T: Num,
{
    fn from(value: T) -> Dimensionless<T> {
        Dimensionless::<T> { value }
    }
}
```

然后就可以这样写了：

```rust
let d = c * 4.0.into();
println!("type: {}, value: {}", std::any::type_name_of_val(&d), d.value);
// type: playground::PhysicalQuantity<f64, playground::SiUnit { m: 0, s: 1, kg: 0, c: 0, cd: 0, mol: 0, k: 0 }>, value: 2
```

注意，这里还有一个坑， `let d = 4.0.into() * c` 是无法编译的，因为 `a * b` 运算具体调用哪个函数首先取决于 `a` 的类型，编译器会查找左操作数类型与 `a`
一致的函数，然后在其中查找右操作数类型与 `b` 一致的函数 `mul(type_a, type_b)` ，最后调用 `mul()` 。如果 `4.0.into()` 写在 `*` 的左边，由于 `4.0.into()`
得到并不是一个固定的类型，这个类型取决于上下文，那么查找相应 `mul` 函数的第一步就无法完成，编译器自然会报错。如何解决呢？我们可以指定 `.into()`
得到的类型： `<f64 as Into<Dimensionless<f64>>>::into(4.0)` 或者 `Dimensionless::<f64>::from(4.0)` ，但这两种写法都太麻烦了，不如直接把 `4.0.into()`
写在右面，一样可以编译通过。

尽管如此， `4.0.into()` 这种写法依然看起来很糟糕，为什么不能直接实现 `4.0 * c` 这样的写法呢？因为要支持这样的写法意味着我们需要对四则运算分别再实现一遍，
像 `impl<T> Op<T> for Dimensionless<T> where T: Num` 这样；而且由于孤儿规则的存在，编译器也不允许我们
`impl<T> Mul<Dimensionless<T>> for T where T: Num` ，所以只能作罢。出于复用 `PhysicalQuantity` 之间已经实现的运算的目的，不如把无量纲系数转换为
`Dimensionless<T>` ，再利用已有的函数去实现各种运算，何乐而不为呢（）。至于 `4.0.into()` 这种看起来很丑的写法，这是 Ruast 的一大特色，不得不品尝，
连标准库的文档里都充斥着 `1.0_f64.sqrt()` 这种一样“很丑”的写法，习惯就好啦，你多看几眼就不觉得丑啦 ~~（这就是 Ruast 带给我们的自信）~~ 。

对于一般的数，乘法运算是对易的，但除法却不是。当除数是无量纲数时，我们可以使用 `c / 4.0.into()` ；但当被除数是无量纲数时，我们只能
`Dimensionless::from(4.0f64) / c` 这样来处理了。

对于 \\(e^{c})\\) 和 \\(\ln{c}\\) 等限制输入为无量纲数的函数，我们可以通过只为 `Dimensionless` 类型实现相关函数来实现：

```rust
impl<T> Dimensionless<T>
where T: Float,
{
    pub fn exp(self) -> Self {
        Self { value: self.value.exp() }
    }

    pub fn ln(self) -> Self {
        Self { value: self.value.ln() }
    }
}
```

这样，即使用户传入了一个非无量纲数，编译器也会在编译期把这种代码拒之门外。

至此，我们已经为 `PhysicalQuantity` 实现了基础的运算操作，现在已经可以用它去做一些简单的推导了，并且推导的过程完全是编译期完成的，
并且只要能编译成功，就能保证结果的量纲和单位正确。


#### 其它实现 {#其它实现}

其实很早就有编译期量纲分析的实现了，它们没有用到 `const generics` 这个特性，而是直接使用 [typenum](https://docs.rs/typenum/latest/typenum/) 这个库提供的 `Integer` 特质，其定义如下

```rust
pub trait Integer: Sealed + Copy + Default + 'static {
    const I8: i8;
    const I16: i16;
    const I32: i32;
    const I64: i64;
    const ISIZE: isize;

    fn to_i8() -> i8;
    fn to_i16() -> i16;
    fn to_i32() -> i32;
    fn to_i64() -> i64;
    fn to_isize() -> isize;
}
```

这个特质作为泛型约束出现，那么它所约束的泛型参数就相当于本文实现中 `const unit: SiUnit` 内的的成员，然后分别定义了一系列 `P1` 、 `P2` 、 `N1` ……
等等 **类型** ，对这些类型实现 `Integer` 特质，使用时调用 `.to_i8()` 等函数则返回 `1` 、 `2` 、 `-1` 等等整数，从而模拟 `const generics`
内的整数，由于 `P1` 等本质还是类型，所以它不受 `const generics` 里弱鸡表达式的限制，当然作者为了实现类型之间的运算也是花了很大的功夫，
这里就不谈了（其实是没读懂）。比较完善的量纲分析库，我找到的有两个，分别是 [dimensioned](https://docs.rs/dimensioned/latest/dimensioned/) 和 [uom](https://docs.rs/uom/latest/uom/) ，其中 dimensioned 的作者也是 `typenum` 的作者，
~~可以说是为了这碟醋包了一锅饺子~~ 。

除了使用 `typenum` 库的实现，还有用 `const generics` 实现的库 [const_unit_poc](https://docs.rs/const_unit_poc/latest/const_unit_poc/) ，本文就是参考了它的实现。


## 总结 {#总结}

本文分别实现了运行期的量纲分析和借助 const genreics 实现的编译期量纲分析，着重后者了后者的优势，以及实现上的细节。在使用 const generics
时，依次用到了三个不稳定特性： `adt_const_params` （让 const generics 支持自定义的 `SiUnit` 结构体）， `const_trait_impl` （为 `SiUnit`
实现编译期的四则运算）和 `generic_const_exprs` （允许在 const generic params 内写表达式）。这些不稳定特性现在只能临时使用，将来可能会有语法、
行为上的变化，因此本文的实现不保证在未来依然可用。在实现的同时，我们也发现了一些 Rust 不那么优雅的地方，比如冗长的
`<f64 as Into<Dimensionless<f64>>>::into(4.0)` 表达式、对孤儿规则的妥协、 `generic_const_exprs` 对表达式极为有限的支持等等。
不过相比起 C++ 标准的更新速度， Rust 的标准库更新速度还是可以期待的。

本文实现的全部代码在[这里](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=4807be24f1e6493bcc5c7cb86457439c)&nbsp;[^fn:2]。
还有几篇博文对本人帮助很大，有 zqp-cn 大佬的[针对常量泛型参数的分类实现](https://zjp-cn.github.io/rust-note/forum/impl-const-param.html)

说来编译期的量纲分析其实在 1995 年就被 John J. Barton 和
Lee R. Nackman&nbsp;[^fn:3]
使用 C++ 的模板元编程所实现，
C++ 大师 Scott Meyers 也曾专门写了一篇文章阐述如何使用 C++ template 实现量纲分析[^fn:4] 。
本人其实也是受这个实现所启发，进而产生了用 Rust 的泛型系统重新实现一下这个功能的想法，进而稍微读了些前人的实现，之后便有了这篇文章。
不得不感叹，读别人的代码和自己写完全是两种感觉，有些坑只有自己踩了才会知道，也才能明白有些代码写得拐弯抹角是为了解决啥问题，有啥优势等等。

超长假期学到的一点点东西总算记录了下来，希望不会那么快地忘掉。现在已经开学一两周了，接下来的一两年可能才是艰难险阻的开始，祈祷好运吧……

[^fn:1]: <https://en.wikipedia.org/wiki/Dimensional_analysis>
[^fn:2]: <https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=4807be24f1e6493bcc5c7cb86457439c>
[^fn:3]: John J. Barton 与 Lee R. Nackman 的书 <https://www.amazon.com/Scientific-Engineering-Introduction-Advanced-Techniques/dp/0201533936>
[^fn:4]: Scott Meyers 的文章
    <https://se.inf.ethz.ch/~meyer/publications/OTHERS/scott_meyers/dimensions.pdf>