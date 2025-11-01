import emitter
import ../common/ast

proc compile* (root: Ast, targetOutput: string = "c"): string =
    var em = newEmitter()
    em.addImport("import math, system")


    em.registerBuiltin("echo", "echo({args})")
    em.registerBuiltin("sum", "({0} + {1})")
    em.registerBuiltin("sub", "({0} - {1})")
    em.registerBuiltin("div", "({0} / {1})")
    em.registerBuiltin("mul", "({0} * {1})")
    em.registerBuiltin("eqls", "({0} == {1})")


    # to generate a implementation of somethig not in asts
    # em.registerImpl("eqls", "proc eqls(a: bool, b: bool): bool {.inline.} = a == b")

    let nimSrc = em.emitProgram(root)
    writeFile("out.nim", nimSrc)

    nimSrc
