---
title: How Nim makes multi-platform (especially browser) code easy
description: "Explaining the design choices in the Nim programming language
that make multi-platform code, especially code generated for the browser,
easy to write and manage"
---

###|{title} How Nim makes multi-platform (especially browser) code easy 
####|{subtitle} <time datetime="2024-08-19">2024-08-19</time>

[Nim](https://nim-lang.org) isn't a perfect language, at least not yet. But it is awfully convenient a lot of the time. One convenience I make use of a lot is the fact that it can compile native code (with the C/C++ backends) as well as code for the browser (with the JavaScript backend). 
