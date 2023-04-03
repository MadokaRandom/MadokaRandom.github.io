---
title: "如何将文件打包进 C/C++/Fortran 程序内"
date: 2023-04-04T00:10:00+08:00
tags: ["Posts", "Linux", "Windows", "MacOS", "CXX", "C", "Fortran"]
categories: ["Programming"]
draft: false
---

<div class="ox-hugo-toc toc">

<div class="heading">Table of Contents</div>

- [问题描述](#问题描述)
- [解决方法](#解决方法)
    - [直接写 `const char*`](#直接写-const-char)
    - [通过 inline assembly](#通过-inline-assembly)
    - [宏+内联汇编](#宏-plus-内联汇编)
    - [Fortran 的处理](#fortran-的处理)
- [小结](#小结)

</div>
<!--endtoc-->

最近在写 Fortran 程序时有一个需求：把另一个文件打包进二进制里面，以便可以随时 `print` 出来，经过一番网上冲浪，
摸索出来几个 workaround ，在此记录一下。

<!--more-->


## 问题描述 {#问题描述}

现在有一个不可变的文件名为 `foo.txt` ，编写一个 C/C++/Fortran 程序，使得它能在任意地方打印出 `foo.txt` 的内容。

**注意** ： _任意地方_ 也包括其它人的机器。


## 解决方法 {#解决方法}


### 直接写 `const char*` {#直接写-const-char}

```c
const char* file_content = "Hello world\n\
with a new line here.";
puts(file_content);
```

缺点：麻烦，遇到换行时需要额外加 `\n\` ，可以用 python 脚本生成 `.c` 文件来解决；如果文件为二进制，则需要手写十六进制数据。


### 通过 inline assembly {#通过-inline-assembly}

C 语言中每个全局变量对应一个 label ，并且这个 label 可以直接当作变量名来访问，比如

```C
const char str[] = "Hello world.";
```

Linux 上对应的汇编代码就是

```asm
    .globl  str
    .type   str, @object
    .size   str, 13
str:
    .string "Hello world."
```

可见，除了一些内存对齐、类型标注等，主要起作用的还是 `.section .rodata` 和 `number: .long 114514` 了，前者对应了 `const`
，后者对应了 `int number = 114514` 。那么借用这个方法，我们可以手动定义一个 `const char*` 的变量，然后在 C 代码中调用这个变量，
即可达到访问被包含文件的目的。

GCC 支持用 `__asm__()` 来内联汇编代码，那么我们可以这样写

```c
#include <stdio.h>

__asm__(
    ".section .rodata \n"
    ".globl foo_str \n"
    "foo_str:\n"
    ".string \"Hello world\"\n"
    ".byte 0\n"
);

extern const char foo_str[];

int main() {
    puts(foo_str);
    return 0;
}
```

这样这个程序可以正常输出 "Hello world" ，那把 `.string ...` 换成 `.incbin` 就完成了：

```c
__asm__(
    ".section .rodata \n"
    ".globl foo_str \n"
    "foo_str:\n"
    ".incbin \"file\"\n"
    ".byte 0\n"
);
```

此时运行程序会输出

```shell
$ ./a.out
Hello world from "file"
```

此时我们的目的就达到了，应该可以收工了？

如果这个代码只在 Linux 平台编译，那应该是可以收工了，但如果这个代码要在 macOS 或者 Windows 平台编译，
编译器会报错，因为不同系统上的汇编代码并不完全兼容，我们还需要对它进行一点点修改：

-   Windows 平台上 `.rodata` 对应 `.rdata "dr"`
-   macOS 平台上 `.rodata` 对应 `__TEXT,__const`

此外， macOS 上的编译器生成的汇编代码里符号前面会多一个下划线：

```c
const char str[] = "hello world";
```

对应的汇编代码是

```asm
    .section __TEXT,__const
    .globl _str                    ## @str
_str:
    .asciz "hello world"
```

那么对应的 `__asm__()` 内也要把这个下划线加上，否则编译器会报错。


### 宏+内联汇编 {#宏-plus-内联汇编}

如果代码里只有一处需要打包文件，那么直接手写内联汇编没什么问题；但需要打包的东西多了后再这么做就很麻烦了，
于是[有人](https://gist.github.com/mmozeiko/ed9655cf50341553d282)写了一个宏来解决：

```c
#define STR2(x) #x
#define STR(x) STR2(x)

#ifdef _WIN32
#define INCBIN_SECTION ".rdata, \"dr\""
#else
#define INCBIN_SECTION ".rodata"
#endif

// this aligns start address to 16 and terminates byte array with explict 0
// which is not really needed, feel free to change it to whatever you want/need
#define INCBIN(name, file) \
    __asm__(".section " INCBIN_SECTION "\n" \
            ".global incbin_" STR(name) "_start\n" \
            ".balign 16\n" \
            "incbin_" STR(name) "_start:\n" \
            ".incbin \"" file "\"\n" \
            \
            ".global incbin_" STR(name) "_end\n" \
            ".balign 1\n" \
            "incbin_" STR(name) "_end:\n" \
            ".byte 0\n" \
    ); \
    extern __attribute__((aligned(16))) const char incbin_ ## name ## _start[]; \
    extern                              const char incbin_ ## name ## _end[]

INCBIN(foobar, "binary.bin");
```

但这个宏只能在 Linux 和 Windows 上运行，本人对其做了一点修改，使之能在 macOS 上跑，并且多定义一个表示大小的 `_size` 变量：

```c
#define STR2(x) #x
#define STR(x) STR2(x)

#ifdef __APPLE__
#define USTR(x) "_" STR(x)
#else
#define USTR(x) STR(x)
#endif

#ifdef _WIN32
#define INCBIN_SECTION ".rdata, \"dr\""
#elif defined __APPLE__
#define INCBIN_SECTION "__TEXT,__const"
#else
#define INCBIN_SECTION ".rodata"
#endif

// this aligns start address to 16 and terminates byte array with explict 0
// which is not really needed, feel free to change it to whatever you want/need
#define INCBIN(prefix, name, file) \
    __asm__(".section " INCBIN_SECTION "\n" \
            ".global " USTR(prefix) "_" STR(name) "_start\n" \
            ".balign 16\n" \
            USTR(prefix) "_" STR(name) "_start:\n" \
            ".incbin \"" file "\"\n" \
            \
            ".global " STR(prefix) "_" STR(name) "_end\n" \
            ".balign 1\n" \
            USTR(prefix) "_" STR(name) "_end:\n" \
            ".byte 0\n" \
            ".balign 16\n" \
            ".global " STR(prefix) "_" STR(name) "_size\n" \
            USTR(prefix) "_" STR(name) "_size:\n" \
            ".long " USTR(prefix) "_" STR(name) "_end" " - "  USTR(prefix) "_" STR(name) "_start \n"\
    ); \
    extern __attribute__((aligned(16))) const char prefix ## _ ## name ## _start[]; \
    extern                              const char prefix ## _ ## name ## _end[]; \
    extern __attribute__((aligned(16))) const long prefix ## _ ## name ## _size

INCBIN(incbin, foobar, "file");
// printf("%s\n", incbin_foobar_start);
```

对于 C++ 而言，上面的代码几乎可以照抄，唯一需要注意的是 C++ 对符号有 mangling 操作，变量名和 label 不一样，
所以需要把 `extern const ...` 改成 `extern "C" const ...` 让编译器知道这个变量对应的 label 不需要 mangling ，
从而正确找到目标文件里对应的 label 。


### Fortran 的处理 {#fortran-的处理}

Fortran 不能内联汇编，所以上面的代码放到 `.F` 里是不能用的，我们可以通过 FFI 让 Fortran 间接实现这些操作。

需要注意的是， Fortran 的字符串带长度信息，而 C 字符串则是以 `'\0'` 来表示结尾，并没有直接标注长度信息，
这个不同给 Fortran 和 C 的互操作带来的不小的麻烦……

准备一个 `incbin.c` 文件，里面用上一节的方法包含想要的文件，并暴露出 `file_start` 和 `file_size` 两个变量，
准备一个 `main.f90` 文件，用 `iso_c_binding` 提供的 `bind` 来对接刚刚暴露的变量：

```fortran
module foo
    use iso_c_binding
    implicit none

    integer(kind=c_int), bind(C, name="incbin_foobar_size") :: slen
    character(kind=c_char, len=1024*1024), bind(C, name="incbin_foobar_start") :: cstr
    character(len=:), allocatable :: fstr

    public :: slen, fstr
    private :: cstr

    contains

    subroutine initialize
        integer :: i
        if (allocated(fstr)) return
        allocate(character(len=slen) :: fstr)
        forall(i=1:slen) fstr(i:i) = cstr(i:i)
    end subroutine initialize
end module foo

program main
    use foo
    implicit none

    call initialize
    print '(A)', fstr
end program main
```

它通过 `initialize` 函数来把 C 代码中定义的 `incbin_foobar_size` 转换成 Fortran 里带长度信息的字符串，这个操作产生了一次内存复制，
如果你没有内存复制洁癖，这也是可以接受的。

但如果你不想要这多余的内存复制操作，可以把 `cstr` 里的 `len=1024*1024` 直接改成 `len=<length of file>` ，然后可以直接
`print '(A)', cstr` 也能访问。手动输入文件长度也很麻烦，那不如在 `Makefile` 里定义一个宏，把文件长度填进去即可：

```makefile
FILELEN = $(shell \ls -l incbin.c | awk '{print $$5}')
FFLAGS += -DFILELEN=$(FILELEN)
```

```fortran
character(kind=c_char, len=FILELEN), bind(C, name="incbin_foobar_start") :: cstr
```

然后 `print '(A)', cstr` 就能直接得到对应文件的信息了。

顺便多说一句，这各写法已经是我能想到最简洁的方法了，本人曾试过其它更优雅的写法，但都无法成功，只能作罢。


## 小结 {#小结}

以上只是一些把文件打包里程序里的奇技淫巧，本身不值一提，只是被 Fortran 与 C 字符串的互操作恶心到了，不吐不快。其实关于打包文件，
有人已经写了比较成熟的库，就叫 [incbin](https://github.com/graphitemaster/incbin) ，我大概浏览了一下，里面对多个平台、多个编译器做了适配，甚至对 SIMD 的内存对齐也有考虑，
可以说是相当完善，有需要可以直接用。
