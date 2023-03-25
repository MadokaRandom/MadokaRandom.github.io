---
title: "在 CentOS 7 上使用 Clangd 作为 C/C++ 的 LSP"
date: 2023-03-25T16:28:00+08:00
tags: ["Posts", "C", "CXX", "Anaconda", "LSP"]
categories: ["Programming"]
draft: false
---

<div class="ox-hugo-toc toc">

<div class="heading">Table of Contents</div>

- [基本环境要求](#基本环境要求)
- [安装 `clangd`](#安装-clangd)
- [配置 `coc.nvim`](#配置-coc-dot-nvim)

</div>
<!--endtoc-->

最近在 CentOS 7 服务器上写程序时没有 LSP 的帮助，感觉写起来很费劲，于是折腾了一下 `clangd` 使之能为 `coc.nvim` 所用。

<!--more-->


## 基本环境要求 {#基本环境要求}

1.  Anaconda/Miniconda
    可以去各大镜像站下载安装包，然后直接 `sh Anaconda_xxx.sh` 进行安装。这里推荐使用 miniconda ，因为 Anaconda
    内置的包太多，每次 `conda install` 解析依赖冲突都会耗时 114514 年，而 miniconda 因为内置的包更少，依赖解析起来反倒更快。

2.  Vim 及其插件
    使用 `conda` 命令安装 Vim 8.0 或更高的版本
    ```shell
          conda install -c conda-forge vim
    ```
    然后查看 vim 的版本号：
    ```shell
          $ vim --version
          VIM - Vi IMproved 9.0 (2022 Jun 28, compiled Aug 31 2022 01:19:52)
          Included patches: 1-335
          Compiled by conda@065326dfb3d2
          Huge version without GUI.  Features included (+) or not (-):
          +acl               +file_in_path      +mouse_urxvt       -tag_any_white
          ...
          ...
    ```
    是 9.0 ，说明安装成功。

    然后安装 `vim-plug` 和 `coc.nvim` ，直接 Follow 官网上的安装教程即可

    -   [`vim-plug` 的官网](https://github.com/junegunn/vim-plug)
    -   [`coc.nvim` 的官网](https://github.com/junegunn/vim-plug)


## 安装 `clangd` {#安装-clangd}

CentOS 7 的 yum 源里也有 `llvm` 和 `clang` 的包，但它们都没有提供 `clangd` ，那我们只能去自己安装了。

其实如果你使用 `coc-clangd` 的话，它会帮你下载 `clangd` 的可执行文件，但网上预编译的 `clangd` 没有对
CentOS 7 这种老平台适配，运行时会报这个经典错误

```text
/lib64/libc.so.6: version `GLIBC_2.18' not found (required by clangd)
```

这是因为 CentOS 7 默认的 `glibc` 只有 2.17 ，而贸然升级 `glibc` 又是管理 Linux 服务器的大忌（各种程序会炸），
那就只能寻求别的办法了。

所幸 Anaconda 提供了 `clangd` ，我们只需要执行下面的命令即可

```shell
conda install -c conda-forge clang clangxx clang-tools
```

然后检查一下各个程序的版本

```shell
$ clang --version
clang version 14.0.6
Target: x86_64-unknown-linux-gnu
Thread model: posix
InstalledDir: /public/home/xxx/.miniconda/bin

$ clang++ --version
clang version 14.0.6
Target: x86_64-unknown-linux-gnu
Thread model: posix
InstalledDir: /public/home/xxx/.miniconda/bin

$ clangd --version
clangd version 14.0.6
Features: linux
Platform: x86_64-unknown-linux-gnu
```

写一个 C 的 Hello world ：

```C
#include <stdio.h>

int main(int argc, char* argv[]) {
    puts("Hello world.");
    return 0;
}
```

看能不能用 Clang 编译

```shell
$ clang main.c && ./a.out
Hello world.
```

看来是没问题的；那么 C++ 的 Hello world 呢？

```C++
#include <iostream>

int main() {
    std::cout << "Hello world." << std::endl;
    return 0;
}
```

使用 `clang++` 编译：

```shell
$ clang++ main.cpp
main.cpp:1:10: fatal error: 'iostream' file not found
#include <iostream>
         ^~~~~~~~~~
1 error generated.
```

这又是一个很经典的错误，它表示 `clang++` 找不到头文件 `iostream` ，解决它的办不是添加 `-I/usr/include/...` 等参数，而是告诉 `clang++` 借用 `gcc` 工具链内的一些头文件和链接库，具体办法就是使用 `--gcc-toolchain` 这个参数，
官网[^fn:1]
上对这个参数的说明中表示

```text
--gcc-toolchain=<arg>
Specify a directory where Clang can find ‘include’ and ‘lib{,32,64}/gcc{,-cross}/$triple/$version’. Clang will use the GCC installation with the largest version
```

那就很好办了，直接指定 `--gcc-toolchain=/usr` 即可：

```shell
$ clang++ --gcc-toolchain=/usr main.cpp && ./a.out
Hello world.
```

编译运行成功。

此时关于 Clang 的安装就完成了。


## 配置 `coc.nvim` {#配置-coc-dot-nvim}

`coc.nvim` 的官网提供了 `clangd` 的配置模板，直接复制到 `~/.vim/coc-settings.json` 里即可

```js
"languageserver": {
  "clangd": {
    "command": "clangd",
    "rootPatterns": ["compile_flags.txt", "compile_commands.json", ".git/", ".hg/"],
    "filetypes": ["c", "cc", "cpp", "c++", "objc", "objcpp"]
  }
}
```

此时，用 Vim 打开刚才写的 C Hello world `main.c` 应该已经可以提供补全了，如图所示
![](/ox-hugo/vim-clangd-C.png)

接下来配置 C++ 源文件的补全。如果不添加别的参数，那么打开刚刚的 C++ Hello world `main.cpp` ，应该会出现以下错误
![](/ox-hugo/vim-clangd-cxx-1.png)
这和之前直接用 `clang++` 编译时的错误一模一样，之前是通过给 `clang++` 加一个参数 `--gcc-toolchain=/usr` 来解决的，
那么一定有方法可以把编译参数传给 `clang++` 来让 `clangd` 正常工作。 `clangd` 官网上给出的解决方案是在 `main.cpp` 同目录下写一个配置文件让 `clangd` 来正确调用相关的程序，有三种格式可供选择：

1.  `compile_commands.json`

    这个就是用 json 的格式把编译时需要的命令和参数记录下来传给 `clangd` ，它需要把每个文件的编译命令都显式写出来，
    我想没人会喜欢手写 json ，并且是如此啰嗦的 json ，
    下面是一个示例[^fn:2]
    ```js
          [
          {
              "directory": "/public/home/xxx/tests/cxx",
              "arguments": ["/public/home/xxx/.miniconda/bin/clang++", "--gcc-toolchain=/usr", "main.cpp"],
              "file": "file.cc"
          },
          ]
    ```

2.  `compile_flags.txt`

    这个文件的格式非常简单，把参数逐行写到这个文件里即可
    ```text
          --gcc-toolchain=/usr
          --std=c++11
    ```
    然后 `clangd` 就能正常工作了。

<!--listend-->

1.  `.clangd`

    这个文件格式会稍微复杂一些，官网[^fn:3]上有详细的解释，这里给出一个可用的示例
    ```text
          CompileFlags:
            Add: [--gcc-toolchain=/usr]
    ```

将上述三个文件中的任意一个放到 `main.cpp` 的同目录下，用 Vim 打开 `main.cpp` ， LSP 应该能正常补全了
![](/ox-hugo/vim-clangd-cxx-2.png)

看起来效果不错，但总要写这些配置文件总让人不爽，倒不是说参数太长，而是连建个 Hello world 都要写个配置文件难免过于麻烦了，而且编译参数在 `Makefile` 里已经写过一遍，再写一遍岂不很累。有没有办法不用写这些配置，就把参数传给 `clang++` ？经过上网冲浪，在 `vscode` 和 [`coc-clangd`](https://github.com/clangd/coc-clangd) 的配置里有个参数叫 `--fallbackFlags` ，它表示当
`clangd` 找不到上面 `compile.json` 、 `compile_flags.txt` 和 `.clangd` 中任意一个时所使用的参数。从 `coc-clangd`
的源码[^fn:4]里得知，
这个参数应该被放在 `initializationOptions` 下面。打开 `~/.vim/coc-settings.json` ，加上这个参数：

```js
"languageserver": {
    "clangd": {
        "command": "clangd",
        "rootPatterns": ["compile_flags.txt", "compile_commands.json", ".git/", ".hg/"],
        "filetypes": ["c", "cc", "cpp", "c++", "objc", "objcpp"],
        "initializationOptions": {
            "fallbackFlags":["--gcc-toolchain=/usr"]
        }
    }
}
```

删掉 `compile.json` 、 `compile_flags.txt` 和 `.clangd` ，然后打开 `main.cpp` ，补全依然正常工作，大功告成。

[^fn:1]: <https://clang.llvm.org/docs/ClangCommandLineReference.html#cmdoption-clang-gcc-toolchain>
[^fn:2]: <https://clang.llvm.org/docs/JSONCompilationDatabase.html#format>
[^fn:3]: <https://clangd.llvm.org/config>
[^fn:4]: <https://github.com/clangd/coc-clangd/blob/ff784ff7e9bcbcad2bbac556e6849be08c3f048c/src/ctx.ts#L73>