---
title: "VASP 偶极校正及功函数的计算"
date: 2021-04-23T16:44:00+08:00
tags: ["Posts", "VASP", "Python", "ASE", "DipoleCorrection", "Workfunction"]
categories: ["PhysicalChemistry"]
draft: false
katex: true
markup: "goldmark"
---

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [概念解释](#概念解释)
    - [功函数](#功函数)
    - [真空能级](#真空能级)
    - [偶极校正](#偶极校正)
- [如何计算](#如何计算)
    - [偶极校正](#偶极校正)
    - [功函数](#功函数)
- [真空能级](#真空能级)

</div>
<!--endtoc-->

水文一篇，介绍了如何用 VASP 添加偶极校正参数、计算 Slab 体系的功函数，以及如何找真空能级。

<!--more-->


## 概念解释 {#概念解释}


### 功函数 {#功函数}

将一个固体内部的电子移动到真空所需的能量。（类似于光电效应方程中的逸出功）。


### 真空能级 {#真空能级}

固体表面外真空中自由电子所具有的能量。换句话说，电子跑出固体表面并达到这个能级后即可认为它自由 ~~免费~~ 了。


### 偶极校正 {#偶极校正}

因 VASP 所适用的体系是周期性体系，使用它来模拟实验中的 Slab 模型时会取一个相当大的真空层来隔绝相信两个周期中 Slab 的相互作用。理想情况下，真空层中的功函数应当是一条水平的直线（函数值为定值）。但如果表面的两侧并非对称，即其中一侧吸附了分子时，
这两侧的功函数存在差异，此时如果不进行偶极校正，真空中的功函数会是一条斜线；而经过偶极校正后，功函数会出现一个阶梯，阶梯两侧附近的曲接近水平。下图[^fn:1]是一个例子。

<a id="orgef6ecd9"></a>

{{< figure src="/ox-hugo/VCL-2.png" caption="Figure 1: DFT 曲线为未经过偶极校正的功函数， DFT-DC 曲线是经过偶极校正后的功函数" >}}


## 如何计算 {#如何计算}


### 偶极校正 {#偶极校正}

VASP 中直接使用 `LDIPOL` 和 `IDPOL` 即可开启它的偶极校正功能。

-   `LDIPOL = .TRUE.` 表示打开偶极校正；
-   `IDIPOL = 3` 表示偶极校正所修正的方向为第 3 个晶格矢量方向对应的方向，一般来说就是 \\(z\\) 轴；
-   `DIPOL = <3 float values>` 表示体系的中心，以分数坐标表示；

上面几个 Flag 中一般来说 DIPOL 不用填，因为 VASP 手册中[^fn:2]有一句

> If the flag is not set, VASP determines, where the charge density averaged over
> one plane drops to a minimum and calculates the center of the charge
> distribution by adding half of the lattice vector perpendicular to the plane
> where the charge density has a minimum (this is a rather reliable approach for
> orthorhombic cells).

不过有时不填它会导致体系 **非常** 难以收敛，如果遇到这各情况，最好还是手动算一下所有原子 \\(z\\) 坐标的平均值，然后 `DIPOL = 0.5 0.5 <averaged z>` ，此时修正效果可能并不好，读者需要：

1.  打开偶极校正和 `DIPOL = 0.5 0.5 <averaged z>` ，并弛豫结构到稳定；
2.  关闭 `DIPOL` ，并弛豫到结构稳定；
3.  关闭 `DIPOL` ，打开 `LVHAR = .TRUE.` ，并做静态计算，得到功函数；

偶极校正的标准是功函数出现台阶，并且台阶两边为水平，如果画出的功函数图不是这样，
就要考虑调整参数了。


### 功函数 {#功函数}

在 VASP 中 `LVHAR`&nbsp;[^fn:3]参数可以使 VASP 输出体系的功函数文件 `LOCPOT` 。LOCPOT
文件本身是 Volumetric data ，它的格式与 CHGCAR 一样[^fn:4]。一般而言，用户关心的功函数是垂直于表面方向上的数据，因此在得到 LOCPOT 后需要对它做一点工作，即对 \\(xy\\)
平面内的数据做平均，然后乘以晶胞的体积，就得到我们需要的功函数信息。这里给出一个脚本[^fn:5]来完成这项工作：

```python
def locpot_mean(fname="LOCPOT", axis='z', savefile='locpot.dat', outcar="OUTCAR"):
    '''
    Reads the LOCPOT file and calculate the average potential along `axis`.
     @in: See function argument.
    @out:
          - xvals: grid data along selected axis;
          - mean: averaged potential corresponding to `xvals`.
    '''
    def get_efermi(outcar="OUTCAR"):
        if not os.path.isfile(outcar):
            logger.warning("OUTCAR file not found. E-fermi set to 0.0eV")
            return None
        txt = open(outcar).read()
        efermi = re.search(r'E-fermi :\s*([-+]?[0-9]+[.]?[0-9]*([eE][-+]?[0-9]+)?)', txt).groups()[0]
        logger.info("Found E-fermi = {}".format(efermi))
        return float(efermi)

    logger.info("Loading LOCPOT file {}".format(fname))
    locd = VaspChargeDensity(fname)
    cell = locd.atoms[0].cell
    latlens = np.linalg.norm(cell, axis=1)
    vol = np.linalg.det(cell)

    iaxis = ['x', 'y', 'z'].index(axis.lower())
    axes = [0, 1, 2]
    axes.remove(iaxis)
    axes = tuple(axes)

    locpot = locd.chg[0]
    # must multiply with cell volume, similar to CHGCAR
    logger.info("Calculating workfunction along {} axis".format(axis))
    mean = np.mean(locpot, axes) * vol

    xvals = np.linspace(0, latlens[iaxis], locpot.shape[iaxis])

    # save to 'locpot.dat'
    efermi = get_efermi(outcar)
    logger.info("Saving raw data to {}".format(savefile))
    if efermi is None:
        np.savetxt(savefile, np.c_[xvals, mean],
                   fmt='%13.5f', header='Distance(A) Potential(eV) # E-fermi not corrected')
    else:
        mean -= efermi
        np.savetxt(savefile, np.c_[xvals, mean],
                   fmt='%13.5f', header='Distance(A) Potential(eV) # E-fermi shifted to 0.0eV')
```

完整的脚本文件已经放 Gist[^fn:5] 上，当然你也可以直接点击[它](vasp-dipol-correction-work-function/plot-workfunc.py)来下载。运行这个脚本后得到的 Workfunction.pdf 和 locpot.dat 就是 \\(z\\) 方向上的功函数信息。

<a id="orgcd756c0"></a>

{{< figure src="/ox-hugo/Workfunction.png" caption="Figure 2: Workfunction.png 示例" >}}


## 真空能级 {#真空能级}

前面已经提到，真空能级可以读取 locpot.dat 真空部分的数据得到，其实当你打开
`LVHAR` 时，它也可以通过读取 OUTCAR 得到，比如

```sh
$ grep vacuum OUTCAR
 vacuum level on the upper side and lower side of the slab         2.807         3.188
```

这里的 upper side vacuum level 是指 Slab 上表面的真空能级（图 [2](#orgcd756c0)
中 30A 处的平台）， lower side vacuum level 自然就是下表面的真空能级了
（图 [2](#orgcd756c0) 中 35A 处的平台）。

需要注意的是，从 OUTCAR 中 grep 出的真空能级没有经过费米能级修正，它需要减去
OUTCAR 中的 E-fermi 才是实验中测得的功函数的值。所幸的是 plot-workfunc.py 已经做了这个工作，用 locpot.dat 画出来的图就对应实验所测结果。

[^fn:1]: 图源： <http://exciting-code.org/nitrogen-dipole-correction>
[^fn:2]: <https://www.vasp.at/wiki/index.php/DIPOL>
[^fn:3]: 在 VASP 5.2.12 之前的版本中 `LVTOT` 输出的文件是静电势的贡献；但在 VASP 5.2.12 及之后的版本中，交换关联势的贡献也会被写入 `LOCPOT` 中， `LVHAR` 输出的部 分才是真正静电势的贡献，也就是我们想要的部分；
[^fn:4]: CHGCAR 的格式请见 VASP 手册 <https://www.vasp.at/wiki/index.php/CHGCAR> ；
[^fn:5]: 完整脚本见 <https://gist.github.com/Ionizing/1ac92f98e8b00a1cf6f16bd57694ff03> 。
