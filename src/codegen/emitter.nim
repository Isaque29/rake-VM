import std/tables, std/strutils
import ../common/ast
import ../common/kind

type
    Emitter* = ref object
        buf*: string
        indentLevel*: int
        builtins*: Table[string, string]
        impls*: Table[string, string]
        imports*: seq[string]

proc emitNode*(e: Emitter, node: Ast)

proc newEmitter*(): Emitter =
    new(result)
    result.buf = ""
    result.indentLevel = 0
    result.builtins = initTable[string, string]()
    result.impls = initTable[string, string]()
    result.imports = @[]

proc addLine*(e: Emitter, s: string = "") =
    for i in 0..<e.indentLevel: e.buf.add("    ")
    e.buf.add(s & "\n")

proc add*(e: Emitter, s: string) =
    e.buf.add(s)

proc indentInc*(e: Emitter) =
    e.indentLevel.inc
proc indentDec*(e: Emitter) =
    if e.indentLevel > 0: e.indentLevel.dec

proc registerBuiltin*(e: Emitter, name: string, templat: string) =
    e.builtins[name] = templat

proc registerImpl*(e: Emitter, name: string, nimCode: string) =
    e.impls[name] = nimCode

proc addImport*(e: Emitter, stmt: string) =
    e.imports.add(stmt)

proc emitType*(e: Emitter, t: Ast): string =
    if t.kind == tkType:
        if t.children.len == 0:
            return t.lexeme
        else:
            var parts: seq[string] = @[]
            for c in t.children:
                parts.add(emitType(e, c))
            return t.lexeme & "[" & parts.join(", ") & "]"
    elif t.kind == tkIdent:
        return t.lexeme
    else:
        return "auto"

proc emitExpr*(e: Emitter, node: Ast): string =
    case node.kind
    of tkNumber, tkString, tkBool, tkNil:
        return node.lexeme
    of tkIdent:
        if node.children.len == 0:
            return node.lexeme
        else:
            var args: seq[string] = @[]
            for c in node.children: args.add(emitExpr(e, c))
            return node.lexeme & "(" & args.join(", ") & ")"
    of tkDotInvoke:
        if node.children.len == 0:
            return node.lexeme
        let callee = node.children[0]
        # if callee is ident and registered in builtins, use template
        if callee.kind == tkIdent and callee.lexeme in e.builtins:
            var args: seq[string] = @[]
            for i in 1 ..< node.children.len:
                args.add(emitExpr(e, node.children[i]))
            var templat = e.builtins[callee.lexeme]
            var outt = templat
            outt = outt.replace("{args}", args.join(", "))
            outt = outt.replace("{callee}", callee.lexeme)
            return outt
        else:
            # normal call: callee(args...)
            var calleeS = emitExpr(e, callee)
            var args2: seq[string] = @[]
            for i in 1 ..< node.children.len:
                args2.add(emitExpr(e, node.children[i]))
            return calleeS & "(" & args2.join(", ") & ")"
    else:
        # fallback: try to print children concatenated
        var parts: seq[string] = @[]
        for c in node.children:
            parts.add(emitExpr(e, c))
        if parts.len > 0: return parts.join(", ")
        return node.lexeme

proc emitSet*(e: Emitter, node: Ast) =
    # node.children: target, [type?], value    (type optional)
    if node.children.len >= 2:
        let target = node.children[0]
        var value: Ast
        if node.children.len == 3:
            value = node.children[2]
        else:
            value = node.children[1]
        let lhs = emitExpr(e, target)
        let rhs = emitExpr(e, value)
        addLine(e, lhs & " = " & rhs)
    else:
        addLine(e, "# malformed set: " & node.lexeme)

proc emitInvokeStmt*(e: Emitter, node: Ast) =
    # node.children[0] = function ident or expression
    let callS = emitExpr(e, node.children[0])
    addLine(e, callS)

proc emitBlock*(e: Emitter, node: Ast) =
    # node.children are statements
    for ch in node.children:
        emitNode(e, ch)

proc emitIf*(e: Emitter, node: Ast) =
    # node.children are clauses (astClause)
    # each clause: child0 = astParams "cond", child1 = astBlock "body"
    var first = true
    for i, cl in node.children:
        if cl.kind != astClause: continue
        let params = if cl.children.len > 0: cl.children[0] else: newAst(tkUnknown, "")
        let body = if cl.children.len > 1: cl.children[1] else: newAst(astBlock, "body")
        var condS = "true"
        if params.kind == astParams:
            var exprParts: seq[string] = @[]
            for c in params.children: exprParts.add(emitExpr(e, c))
            condS = if exprParts.len == 0: "true" else: exprParts.join(" and ")
        if first:
            addLine(e, "if " & condS & ":")
            first = false
        else:
            addLine(e, "elif " & condS & ":")
        indentInc(e)
        emitBlock(e, body)
        indentDec(e)

proc emitWhile*(e: Emitter, node: Ast) =
    # children: first = astParams, second = astBlock
    var condS = "true"
    if node.children.len > 0 and node.children[0].kind == astParams:
        var parts: seq[string] = @[]
        for c in node.children[0].children: parts.add(emitExpr(e, c))
        condS = if parts.len == 0: "true" else: parts.join(" and ")
    addLine(e, "while " & condS & ":")
    indentInc(e)
    if node.children.len > 1:
        emitBlock(e, node.children[1])
    indentDec(e)

proc emitFor*(e: Emitter, node: Ast) =
    # children: first = astParams, second = astBlock
    if node.children.len > 0 and node.children[0].kind == astParams:
        let params = node.children[0]
        if params.children.len >= 2:
            let varN = emitExpr(e, params.children[0])
            let iter = emitExpr(e, params.children[1])
            addLine(e, "for " & varN & " in " & iter & ":")
            indentInc(e)
            if node.children.len > 1:
                emitBlock(e, node.children[1])
            indentDec(e)
            return
    addLine(e, "# malformed for")

proc emitFunc*(e: Emitter, node: Ast) =
    # node.lexeme = name
    var name = node.lexeme
    var paramsNode: Ast = nil
    var retTypeNode: Ast = nil
    var bodyNode: Ast = nil

    # find children: could be [ret?, astParams, astBlock] or [astParams, astBlock]
    for ch in node.children:
        case ch.kind
        of astParams:
            paramsNode = ch
        of astBlock:
            bodyNode = ch
        of tkType, tkIdent:
            if retTypeNode == nil:
                retTypeNode = ch
        else:
            discard

    var paramsSigParts: seq[string] = @[]
    if paramsNode != nil:
        for p in paramsNode.children:
            # p: tkIdent with optional child type
            var paramName = p.lexeme
            var paramType = "auto"
            if p.children.len > 0 and p.children[0].kind in {tkType, tkIdent}:
                paramType = emitType(e, p.children[0])
            paramsSigParts.add(paramName & ": " & paramType)

    let paramsSig = "(" & paramsSigParts.join(", ") & ")"
    var retSig = ""
    if retTypeNode != nil:
        retSig = ": " & emitType(e, retTypeNode)

    addLine(e, "proc " & name & paramsSig & retSig & " =")
    indentInc(e)
    if bodyNode != nil:
        emitBlock(e, bodyNode)
    else:
        addLine(e, "discard")
    indentDec(e)
    addLine(e, "")

proc emitNode*(e: Emitter, node: Ast) =
    case node.kind
    of astProgram:
        for _, code in e.impls:
            addLine(e, code)
        if e.imports.len > 0:
            for im in e.imports: addLine(e, im)
            addLine(e, "")

        for ch in node.children:
            emitNode(e, ch)
    of astFunc:
        emitFunc(e, node)
    of astBlock:
        emitBlock(e, node)
    of tkDotVarSet:
        if node.children.len >= 2 and node.children[0].kind == tkIdent:
            let nm = node.children[0].lexeme
            let rhs = emitExpr(e, node.children[^1])
            addLine(e, "var " & nm & " = " & rhs)
        else:
            emitSet(e, node)
    of tkDotSet:
        emitSet(e, node)
    of tkDotLet:
        if node.children.len >= 2 and node.children[0].kind == tkIdent:
            let nm = node.children[0].lexeme
            let rhs = emitExpr(e, node.children[^1])
            addLine(e, "let " & nm & " = " & rhs)
        else:
            emitSet(e, node)
    of tkDotConst:
        if node.children.len >= 2 and node.children[0].kind == tkIdent:
            let nm = node.children[0].lexeme
            let rhs = emitExpr(e, node.children[^1])
            addLine(e, "const " & nm & " = " & rhs)
        else:
            emitSet(e, node)
    of tkDotInvoke:
        emitInvokeStmt(e, node)
    of astIf:
        emitIf(e, node)
    of astWhile:
        emitWhile(e, node)
    of astForIn:
        emitFor(e, node)
    else:
        if node.children.len > 0:
            let expr = emitExpr(e, node)
            addLine(e, expr)
        else:
            addLine(e, "# unhandled node: " & $node.kind & " " & node.lexeme)

proc emitProgram*(e: Emitter, root: Ast): string =
    e.buf = ""
    emitNode(e, root)
    return e.buf

proc writeToFile*(e: Emitter, path: string, root: Ast) =
    let outt = emitProgram(e, root)
    writeFile(path, outt)
