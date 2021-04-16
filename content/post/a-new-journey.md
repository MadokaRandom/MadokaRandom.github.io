---
title: "新的旅程"
date: 2021-04-14T16:15:00+08:00
lastmod: 2021-04-16T13:29:43+08:00
tags: ["Posts", "回归", "模板", "配置"]
categories: ["杂项"]
draft: false
weight: 1
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

[^fn:1]: <http://zwz.github.io>
[^fn:2]: <https://stackoverflow.com/questions/16186843/inline-code-in-org-mode/16193498#16193498>
[^fn:3]: <https://orgmode.org/worg/org-tutorials/org-latex-preview.html>
[^fn:4]: <https://orgmode.org/manual/Creating-Footnotes.html>
[^fn:5]: <https://ox-hugo.scripter.co>
[^fn:6]: <https://github.com/Molunerfinn/PicGo>
