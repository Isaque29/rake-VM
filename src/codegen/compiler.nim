import emitter
import ../common/ast

proc compile* (root: Ast, targetOutput: string = "c"): string =
    var em = newEmitter()
    em.addImport("import math, system")


    em.registerBuiltin("echo", "echo({args})")
    em.registerBuiltin("__sum", "sum({args})")
    em.registerBuiltin("__min", "min({args})")
    em.registerBuiltin("__eqls", "eqls({args})")


    # to generate a implementation of somethig not in asts
    em.registerImpl("__eqls", "proc eqls(a: bool, b: bool): bool {.inline.} = a == b")
    em.registerImpl("__eqls", "proc eqls(a: int, b: int): bool {.inline.} = a == b")
    em.registerImpl("__eqls", "proc eqls(a: string, b: string): bool {.inline.} = a == b")


    let nimSrc = em.emitProgram(root)
    writeFile("out.nim", nimSrc)

    nimSrc
