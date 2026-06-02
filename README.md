# 🧠 Basic Compiler Project

## 🎯 Overview
This project consists of the development of a **basic compiler** as part of the *Compilers* undergraduate course. The main goal is to understand, in practice, how programming languages are processed. The project focus on core compiler construction concepts such as lexical, syntactic, and semantic analysis.

<br>

## ⚙️ How does it work?
The compiler will process source code written in a custom language and translate it into **C code**, which can then be compiled using a standard C compiler such as the **gcc (GNU Compiler Collection)**

This approach allows us to focus on the compilation process itself while leveraging a mature backend for execution.

<br>

## 🛠 Technical Stack
* **Programming Language:** ![Lex](https://img.shields.io/badge/Lex-F06632?style=flat&logo=gnu&logoColor=white)![Yacc](https://img.shields.io/badge/Yacc-944058?style=flat&logo=gnu&logoColor=white)
* **Target Language:** ![C](https://img.shields.io/badge/C-A8B9CC?style=flat&logo=c&logoColor=white)
* **Tools/Libraries used:** `flex`, `bison`, `g++`, [`wsl`](https://learn.microsoft.com/windows/wsl/install).

<br>

## 🖥️ Execution

```
make                                                # compiles the compiler
make run FILE=examples/01_sum.foca                  # runs an example
make test                                           # runs all tests
make test-01                                        # tests stage 01
make verify FILE=examples/03_temp_declaration.foca  # compiles and runs the generated C code
make clean                                          # cleans generated files
```

<br>

## 🧩 Compiler Structure
The implementation will follow the traditional compiler pipeline:

* **Lexical Analysis (Scanner):** Tokenization of source code  
* **Syntactic Analysis (Parser):** Grammar validation and AST generation  
* **Semantic Analysis:** Type checking and scope resolution  
* **Intermediate Code Generation:** Translation to C  
* **Error Handling:** Detection and reporting of compilation errors  


<br>

## 👥 Contributors
<a href="https://github.com/d-olivr/basic-compiler/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=d-olivr/basic-compiler" />
</a>
<br>

<br>


## 🚀 Getting Started
*Instructions on how to clone, build, and run the project will be added later on.*

1. `git clone https://github.com/<your-username>/<your-repo>.git`  
2. ...
