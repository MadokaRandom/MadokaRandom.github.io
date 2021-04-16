---
title: "VASP 收敛性测试的小脚本"
date: 2021-04-16T20:57:00+08:00
tags: ["Posts", "VASP", "Shell", "ASE"]
categories: ["PhysicalChemistry"]
draft: false
---

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [`SIGMA` 的测试](#sigma-的测试)
- [`ENCUT` 的测试](#encut-的测试)
- [晶格参数的测试](#晶格参数的测试)
    - [晶格常数的测试](#晶格常数的测试)
    - [晶格长度的测试](#晶格长度的测试)
- [Slab 衬底层数的测试](#slab-衬底层数的测试)

</div>
<!--endtoc-->

一般而言，在使用 VASP 计算体系之前都需要对一些参数做收敛性测试，侯老师曾写过一本
VASP 入门手册，里面给了一些测试计算参数的小脚本，这里我也给出一些我经常用的收敛性测试脚本，权当抛砖引玉了。

<!--more-->

本文提供的测试脚本可以写进提交任务的脚本中，进而充分利用超算上多核、多节点的计算资源。需要注意的是，这些脚本本身并不产生 VASP 的输入文件，而是在已有的文件基础上进行修改。


## `SIGMA` 的测试 {#sigma-的测试}

和上面的使用前提一样， INCAR 应提前准备好。 SIGMA 收敛的标准通常是 dE 绝对值小于
1.0meV/atom 。

```sh
#!/bin/bash
#SBATCH xx
...

set -e
set -o pipefail

VASP_EXEC="srun /path/to/vasp"  # "mpirun -np xxx" is also ok

date >> sigma.txt
for i in 0.8 0.5 0.3 0.1 0.08 0.05 ; do
    echo
    sed -i "s/^.*\\bSIGMA\\b.*$/        SIGMA = $i" INCAR
    eval ${VASP_EXEC}
    TS=$(grep "EENTRO" OUTCAR | tail -1 | awk '{print $5}')
    echo "$i    $TS" >> sigma.txt
done

echo "NIONS = " $(grep NIONS OUTCAR | awk '{print $12}') >> sigma.txt
```


## `ENCUT` 的测试 {#encut-的测试}

使用前请先写好一个 INCAR ，并确保里面包含 `ENCUT` 字段，且 `ENCUT` 单独占一行
（否则同一行内的其它参数会被舍去）。通常而言，达到收敛的标志是相邻两次迭代的能量小于 1.0meV/atom 。

```sh
#!/bin/bash
#SBATCH xx
...

set -e
set -o pipefail

VASP_EXEC="srun /path/to/vasp"  # "mpirun -np xxx" is also ok

date >> encut.txt
for i in {200..500..50}; do
    sed -i "s/^.*\\bENCUT\\b.*$/        ENCUT = $i" INCAR
    eval ${VASP_EXEC}
    E=$(grep TOTEN OUTCAR | tail -1 | awk '{printf "%12.6f", $5}')  # Extract TOTEN from OUTCAR
    echo "$i    $E" >> encut.txt
done

echo "NIONS = " $(grep NIONS OUTCAR | awk '{print $12}') >> encut.txt
```


## 晶格参数的测试 {#晶格参数的测试}


### 晶格常数的测试 {#晶格常数的测试}

执行这个测试需要准备好 POSCAR ，这个测试不依赖 ASE 等包，因为它实质上是在更改
POSCAR 第二行的 scale factor 。这个测试只是相对粗糙的测试，因此这里就直接在原位覆盖前一次的计算结果了。

```sh
#!/bin/bash
#SBATCH xx
...

set -e
set -o pipefail

VASP_EXEC="srun /path/to/vasp"  # "mpirun -np xxx" is also ok

date >> a.txt
for i in $(seq 0.99 0.001 1.01)
do
  sed -i "2c $i" POSCAR
  echo -e "a = $i angstrom"
  eval ${VASP_EXEC}
  E=`grep "TOTEN" OUTCAR | tail -1 | awk '{printf "%12.6f", $5 }'`
  V=`grep "volume" OUTCAR | tail -1 | awk '{printf "%12.4f", $5}'`
  printf "a = %6.3f Vol = %10.4f Energy = %18.10f\n" $i $V $E >> a.txt
  tail -1 a.txt
done
echo -e "\n\n" >> a.txt#+end_src
```


### 晶格长度的测试 {#晶格长度的测试}

在测试晶格的角度、长度时就不得不使用其它包了，Python 的 ASE 包提供了相对完善的基础设施，这里在使用它来辅助完成晶格测试的工作。另外，在测试 Slab 的真空层厚度时也可以使用这个脚本[^fn:1]。

```python
#!/usr/bin/env python3

import os
from ase.io import read as poscar_reader

poscar = poscar_reader("POSCAR")
cell = poscar.get_cell().copy()

for i in range(1, 7):
    cell[-1, -1] += 5.0             # Increase length along z axis by 5 angstroms each time
    poscar.set_cell(cell)
    dirname = "{:02}".format(i*5)
    if not os.path.exists(dirname):
        os.mkdir(dirname)           # create directories for each test
    poscar.write(dirname + "/POSCAR", vasp5=True, direct=True)
    for infile in ['INCAR', 'POTCAR', 'KPOINTS', 'sub_vasp_tahoma']:
        abspath = os.path.abspath(infile)
        os.symlink(abspath, dirname + "/" + infile)
        pass
    print("POSCAR saved in {}".format(dirname + "/POSCAR"))
    pass
```

用户可以根据自己需要随意更改晶格的参数，具体的需求可以通过阅读 ASE 的文档[^fn:2]来实现，这里就不一一列举了。


## Slab 衬底层数的测试 {#slab-衬底层数的测试}

一般而言，结构建模都是在 Materials Studio 上完成的（我现在也是如此），但如果有对
Slab 衬底做收敛性测试的需求，还是要借助一下 ASE ，它也内置一了些常见的 Slab 。

下面是一个生成不同层数 Ag(111) Slab 的脚本：

```python
#!/usr/bin/env python3

import os
import numpy as np
from ase.build import fcc111
from ase.constraints import FixAtoms

for i in np.arange(1, 9):
    numstr = str(i)

    # generate 1x1 slab along a and b axis, this slab has `i` layers
    # vacuum is 20 angstrom
    slab = fcc111("Ag", size=(1, 1, i), vacuum=20)

    # Relax the first 2 layers and fix the others.
    c = FixAtoms(mask=[atom.tag > 2 for atom in slab])

    # Apply the constraint
    slab.set_constraint(c)
    print(slab)
    if not os.path.exists(numstr):
        os.makedirs(numstr+"/opt")
        os.makedirs(numstr+"/band")
        pass
    slab.write(numstr+"/opt/POSCAR", vasp5=True, direct=True)
    pass
```

对于其它金属， ASE 也有支持，详细说明请看它的文档[^fn:3]。

[^fn:1]: 这个脚本要求晶格的 c 轴垂直于 a 轴和 b 轴
[^fn:2]: <https://wiki.fysik.dtu.dk/ase/ase/atoms.html> 和 <https://wiki.fysik.dtu.dk/ase/ase/geometry.html>
[^fn:3]: <https://wiki.fysik.dtu.dk/ase/ase/build/build.html>
