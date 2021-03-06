---
title: "新的旅程"
date: 2021-04-14T16:15:00+08:00
tags: ["Posts", "回归", "模板", "配置"]
categories: ["杂项"]
draft: false
katex: true
markup: "goldmark"
---

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [回归](#回归)
- [博客相关](#博客相关)
    - [配置、模板](#配置-模板)
    - [图片等外部文件的引用](#图片等外部文件的引用)
    - [使用 TikZ 配合 Orgmode 进行画图 <span class="timestamp-wrapper"><span class="timestamp">[2021-04-29 Thu] </span></span> 更新](#使用-tikz-配合-orgmode-进行画图-更新)
        - [输出 PNG 格式的图片](#输出-png-格式的图片)
        - [输出 SVG 格式的图片](#输出-svg-格式的图片)

</div>
<!--endtoc-->

这是回归博客写作后的第一篇文章

<!--more-->


## 回归 {#回归}

时光荏冉，已经好久没有更新博客了，上一次写博客还是去年寒假疫情在家时期。

这一年多以来总算把与实验组合作的几个工作结束了（第一次实践使用 VASP ），这几个工作感觉能总结的地方不多，都是细节居多，但坑还是不少的。我自己的工作做了快两年了
（看来平时没少摸鱼），在去年底它的进度有了 180 度转变，这还多亏了导师的嘱托，让我在补充图表时 Review 了一下之后的结果，一看就发现之前的结论完全错误，于是重新跑了一下 NAMD ，这次的结果终于符合「预期」了，但现在似乎又遇到了一些不大不小的问题，
即能带交叉的处理，目测解决它又要费些时间了（而且还中间还有其它实验组的东西要做）。

说了这段时间自己在做什么，下面就该讲博客相关的东西了。


## 博客相关 {#博客相关}

关于博客，我这次决心将它迁移到 Hugo 框架下，配合 Org-mode 和 ox-hugo 使用，至少到现在体验挺好：

-   Hugo 很快，生成静态页面耗时在 ms 量级，比 Hexo 不知道高到哪里去了；
-   Org-mode 很强大，谁用谁知道；
-   私以为 Jane 主题足够简约，也留了足够的空间折腾。

近期做了些工作，我会把心得总结起来放到博客上，供自己和小伙伴们参考～


### 配置、模板 {#配置-模板}

以下是写博客时可能要用到的一些模板/配置，仅供自己参考了。

-   Org-mode 中 CJK 文档的 soft space 问题，已经有人给出了解决方案[^fn:1] ：

<!--listend-->

```elisp
(defun clear-single-linebreak-in-cjk-string (string)
"clear single line-break between cjk characters that is usually soft line-breaks"
(let* ((regexp "\\([\u4E00-\u9FA5]\\)\n\\([\u4E00-\u9FA5]\\)")
        (start (string-match regexp string)))
    (while start
    (setq string (replace-match "\\1\\2" nil nil string)
            start (string-match regexp string start))))
string)

(defun ox-html-clear-single-linebreak-for-cjk (string backend info)
(when (org-export-derived-backend-p backend 'html)
    (clear-single-linebreak-in-cjk-string string)))

(eval-after-load "ox"
  '(add-to-list 'org-export-filter-final-output-functions
                'ox-html-clear-single-linebreak-for-cjk))
```

-   添加链接时使用 `C-c C-l` ， Doom-Emacs 会提示你输入链
    接的 URL 和 description；
-   使用 Inline code 时，参考它[^fn:2]： `src_sh[:exports code]{echo -e "test"}` ；
-   `:PROPERTIES:` 中 `:@cat:` 定义了一个 category `cat` ， `:foo:` 定义了一个 tag `foo` ，
    `:@cat:foo:bar:` 则分别定义了一个 category `cat` ，两个 tags `foo` 、 `bar` ；
-   每篇文章标题前使用 `S-left` 或 `S-right` 可以切换 `TODO` 和 `DONE` 的状态；输
    入数学公式时，需要在 subtree 的 `:PROPERTIES:` 里加上
    `:EXPORT_HUGO_CUSTOM_FRONT_MATTER+: :katex true :markup goldmark` 。

     此时 `\(F=ma\)` 表示 inline equation ，输出 \\(F=ma\\) ； `\[F=ma\]` 表示
    displaystyle equation 。（冷知识[^fn:3]： Orgmode 支持
    即时渲染公式： `C-c C-x C-l` 会把当前公式渲染好并以 png 的形式插入当前窗口，重
    复这个操作可以关闭预览）

    现在试试一个稍稍复杂点的公式：

\\[ \begin{aligned} \nabla \times \vec{\mathbf{B}} - \frac1c
\frac{\partial\vec{\mathbf{E}}}{\partial t} & = \frac{4\pi}{c}\vec{\mathbf{j}}
\newline \nabla \cdot \vec{\mathbf{E}} & = 4 \pi \rho \newline \nabla \times
\vec{\mathbf{E}} + \frac1c \frac{\partial\vec{\mathbf{B}}}{\partial t} & =
\vec{\mathbf{0}} \newline \nabla \cdot \vec{\mathbf{B}} & = 0 \end{aligned} \\]

-   使用脚注来代替文献的上标[^fn:4]
    ，有三种方式：
    1.  声明和定义分离的脚注：在要添加脚注的地方声明 `[fn:NAME]` ，然后在其它地方定
        义这个脚注 `[fn:NAME] some description here ...` ；
    2.  行内定义的脚注：直接使用 `[fn:: some description here ... ]` ，这种方法不需要命名，可谓对程序员十分友好了 23333 ；
    3.  带名字的行内脚注： `[fn:NAME: some description here ...]` 。


### 图片等外部文件的引用 {#图片等外部文件的引用}

这一节单独列出来是因为它比数学公式还要难处理，根据 `ox-hugo`[^fn:5] 的说明，现在有三种引用图片的方法：

1.  使用相对路径：直接把图片放到 `<HUGO_BASE_DIR>/static/` 里，然后引用时可以省略
    `<HUGO_BASE_DIR>/static/` 前缀，例如有一个文件路径是
    `<HUGO_BASE_DIR>/static/image/foo.png` ，引用它时可以这样写：
    `[[image/foo.png]]` ；
2.  使用绝对路径：例如有一个路径是 `~/some/path/foo.png` ，引用它时可以使用
    `[[~/some/path/foo.png]]` ，此时不光在 orgmode 里可以直接预览图片， `ox-hugo`
    在导出时还会把它复制到 `<HUGO_BASE_DIR>/static/ox-hugo/` 里并生成链接；
3.  使用图床：现在 GitHub ， GitLab 等也可以用作图床，并且有成熟的软件来做这件事
    比如 PicGo[^fn:6] 。把图片传给图床后，图
    床会返回一个链接，直接把它贴在 orgmode 里就能实现引用图片的效果。但之前我用七
    牛云的图床一段时间后七牛云直接拒绝被薅，改了域名，我也就对图床产生一些顾虑
    ~~，而且使用图床后一个缺点是，它降低了每篇文章的内聚度，增加了对外部的耦合（掉个
    书袋233）~~ 。

因此我还是决定把图片等外部文件放在 `<HUGO_BASE_DIR>/content-org/` 里，每篇文章单独建一个文件夹，然后使用相对路径引用。下面是效果展示（它使用了
`[[./a-new-journey/himehina.jpeg]]` ）：![](/ox-hugo/himehina.jpeg)


### 使用 TikZ 配合 Orgmode 进行画图 <span class="timestamp-wrapper"><span class="timestamp">[2021-04-29 Thu] </span></span> 更新 {#使用-tikz-配合-orgmode-进行画图-更新}

Orgmode 原生支持内嵌 \\(\LaTeX\\) 代码，自然也支持用 TikZ 画图。不过如果想要在利用
TikZ 的输出嵌入到博客中，还需要一点工作要做。


#### 输出 PNG 格式的图片 {#输出-png-格式的图片}

-   确保机器上已经安装了 ImageMagick 和 \\(\LaTeX\\) ；
-   在 config 中加入 `(setq org-latex-create-formula-image-program 'imagemagick)` ；

接下来就可以愉快玩耍了：

```org
#+header: :headers '("\\usepackage{tikz}")
#+header: :results file graphics :file ./a-new-journey/test.png
#+header: :exports results
#+header: :fit yes :imoutoptions -geometry 400 :iminoptions -density 600
#+begin_src latex
\begin{tikzpicture}
\draw[->] (-3,0) -- (-2,0) arc[radius=0.5cm,start angle=-180,end angle=0]
    (-1,0) -- (1,0) arc[radius=0.5cm,start angle=180,end angle=0] (2,0) -- (3,0);
\filldraw (-1.5,0) circle[radius=1mm];
\filldraw (1.5,0) circle[radius=1mm];
\end{tikzpicture}
#+end_src

#+RESULTS:
[[file:./a-new-journey/test.png]]
```

Eval 这个 source block 后即可得到：

{{< figure src="/ox-hugo/test.png" >}}


#### 输出 SVG 格式的图片 {#输出-svg-格式的图片}

-   确保机器上已经安装了 \\(\LaTeX\\)

接下来的工作不那么优雅，我们需要修改一下 `ob-latex.el` 。

因为在 Orgmode 中 Eval 代码块时 Orgmode 会自动把代码块的内容加入预告写好的
Preamble 里生成一个临时文件，但当使用 `.svg` 结尾的输出文件名时它的 Preamble 是这样的：

```latex
\documentclass[preview]{standalone}
\def\pgfsysdriver{pgfsys-tex4ht.def}
%% Your \usepackage here
\begin{document}
%% Your code here
\end{document}
```

第二行的 `\def\pgfsysdriver` 需要放在 `\usepackage{tikz}` 后，或者使用 `htlatex`
才能编译，但 ob-latex 使用的是 `latex` ，而且这个过程只会提示 `PDF produced with
errors` ，导致输出的 SVG 是乱码。

查询 `ob-latex.el` 发现，这个 Preamble 是硬编码在 `org-babel-execute:latex` 里的：

```elisp
 (defcustom org-babel-latex-preamble
   (lambda (_)
     "\\documentclass[preview]{standalone}
\\def\\pgfsysdriver{pgfsys-tex4ht.def}
 ")
   "Closure which evaluates at runtime to the LaTeX preamble."

...

          (with-temp-file tex-file
            (insert (concat
                     "\\documentclass[preview]{standalone}
\\def\\pgfsysdriver{pgfsys-tex4ht.def}
 "
                     (mapconcat (lambda (pkg)
                                  (concat "\\usepackage" pkg))
```

那问题就好办了，直接删掉两处 `\\def\\pgfsysdriver{pgfsys-tex4ht.def}` ，并重新
build （我使用的是 DoomEmacs ，运行 `~/.emacs.d/bin/doom build` ），然后就可以正常导出了。

```org
#+header: :headers '("\\usepackage{tikz}")
#+header: :results file graphics :file ./a-new-journey/test.svg
#+header: :exports results
#+header: :fit yes :imoutoptions -geometry 400 :iminoptions -density 600
#+begin_src latex
\begin{tikzpicture}
\draw[->] (-3,0) -- (-2,0) arc[radius=0.5cm,start angle=-180,end angle=0]
    (-1,0) -- (1,0) arc[radius=0.5cm,start angle=180,end angle=0] (2,0) -- (3,0);
\filldraw (-1.5,0) circle[radius=1mm];
\filldraw (1.5,0) circle[radius=1mm];
\end{tikzpicture}
#+end_src

#+RESULTS:
[[file:./a-new-journey/test.svg]]
```

输出以下图形：

{{< figure src="/ox-hugo/test.svg" >}}

其实看 `ob-latex.el` 似乎可以通过用户定义 `org-babel-latex-preamble` 来绕过硬编码的 Preamble ，但经过测试发现并没有起作用，如果读者有更好方案，请务必联系我。

上面测试用的 TikZ 代码圴来自 Jonny Evans[^fn:7]，同时感谢群组内[^fn:8]大佬们的帮助。

[^fn:1]: <http://zwz.github.io>
[^fn:2]: <https://stackoverflow.com/questions/16186843/inline-code-in-org-mode/16193498#16193498>
[^fn:3]: <https://orgmode.org/worg/org-tutorials/org-latex-preview.html>
[^fn:4]: <https://orgmode.org/manual/Creating-Footnotes.html>
[^fn:5]: <https://ox-hugo.scripter.co>
[^fn:6]: <https://github.com/Molunerfinn/PicGo>
[^fn:7]: <https://www.homepages.ucl.ac.uk/~ucahjde/blog/tikz.html>
[^fn:8]: <https://t.me/emacs%5Fzh>
