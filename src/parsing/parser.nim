import ../common/token
import ../common/kind
import ../common/ast

type
    Parser* = ref object
        tokens*: seq[Token]
        pos*: int

proc newParser*(toks: seq[Token]): Parser =
    new(result)
    result.tokens = toks
    result.pos = 0

type
    Frame = object
        node*: Ast
        endKinds*: seq[Kind]
        pendingAttach*: Ast

method atEnd(p: Parser): bool {.base.} =
    p.pos >= p.tokens.len or (p.pos < p.tokens.len and p.tokens[p.pos].kind == tkEof)

method peek(p: Parser): Token {.base.} =
    if p.pos >= p.tokens.len:
        return Token(kind: tkEof, lexeme: "", startPos: p.pos, len: 0, line: 0, col: 0)
    else:
        return p.tokens[p.pos]

method peekKind(p: Parser): Kind {.base.} = peek(p).kind

method advance(p: Parser): Token {.base.} =
    let t = peek(p)
    if p.pos < p.tokens.len: inc p.pos
    return t

# consume expected kind if present; otherwise consume one token (to make progress)
method expect(p: Parser; k: Kind): Token {.base.} =
    let t = peek(p)
    if t.kind == k:
        return advance(p)
    else:
        if not atEnd(p):
            # consume something permissively and return a fake tkUnknown token with same lexeme
            let wrong = advance(p)
            return Token(kind: tkUnknown, lexeme: wrong.lexeme, startPos: wrong.startPos,
                                     len: wrong.len, line: wrong.line, col: wrong.col)
        else:
            return Token(kind: tkEof, lexeme: "", startPos: p.pos, len: 0, line: 0, col: 0)

method skipNewlines(p: Parser) {.base.} =
    while not atEnd(p) and peekKind(p) == tkNewline:
        discard advance(p)

# primary := number | string | identifier ['(' args ')'] | .invoke NAME? (args?) | '(' primary ')'
proc parsePrimary(p: Parser): Ast =
    skipNewlines(p)
    if atEnd(p):
        return newAst(tkUnknown, "")

    case peekKind(p)
    of tkNumber:
        let t = advance(p)
        return newAst(tkNumber, t.lexeme)
    of tkBool:
        let t = advance(p)
        return newAst(tkBool, t.lexeme)
    of tkNil:
        let t = advance(p)
        return newAst(tkNil, t.lexeme)
    of tkString:
        let t = advance(p)
        return newAst(tkString, t.lexeme)
    of tkIdent:
        let id = advance(p)
        var node = newAst(tkIdent, id.lexeme)

        if peekKind(p) == tkLParen:
            discard advance(p) # eat '('
            skipNewlines(p)
            if peekKind(p) == tkRParen:
                discard advance(p) # eat ')'
            else:
                while true:
                    let arg = parsePrimary(p)
                    addChild(node, arg)
                    skipNewlines(p)
                    if peekKind(p) == tkComma:
                        discard advance(p); skipNewlines(p); continue
                    break
                discard expect(p, tkRParen)
        return node
    of tkDotInvoke:
        # .invoke NAME? (args...)
        let dt = advance(p)
        skipNewlines(p)
        if peekKind(p) == tkIdent:
            let id = advance(p)
            var fn = newAst(tkIdent, id.lexeme)
            if peekKind(p) == tkLParen:
                discard advance(p)
                skipNewlines(p)
                if peekKind(p) == tkRParen:
                    discard advance(p)
                else:
                    while true:
                        let arg = parsePrimary(p)
                        addChild(fn, arg)
                        skipNewlines(p)
                        if peekKind(p) == tkComma:
                            discard advance(p); skipNewlines(p); continue
                        break
                    discard expect(p, tkRParen)
            var inv = newAst(tkDotInvoke, dt.lexeme)
            addChild(inv, fn)
            return inv
        else:
            # permissive: parse next primary as callee
            let callee = parsePrimary(p)
            var inv = newAst(tkDotInvoke, dt.lexeme)
            addChild(inv, callee)
            return inv
    of tkLParen:
        discard advance(p)
        let inner = parsePrimary(p)
        discard expect(p, tkRParen)
        return inner
    else:
        # unknown token: consume and return unknown node
        let t = advance(p)
        return newAst(tkUnknown, t.lexeme)

method parseType(p: Parser): Ast {.base.} =
    skipNewlines(p)
    if atEnd(p): return newAst(tkUnknown, "")
    if peekKind(p) != tkType: return newAst(tkUnknown, "")

    let baseTok = advance(p)
    var typeNode = newAst(tkType, baseTok.lexeme)
    skipNewlines(p)

    if not atEnd(p) and peek(p).lexeme == "<":
        discard advance(p)
        skipNewlines(p)

        if not atEnd(p) and peek(p).lexeme == ">":
            discard advance(p)
            return typeNode

        while true:
            skipNewlines(p)
            if atEnd(p):
                break

            let arg = parseType(p)
            if arg.kind == tkUnknown:
                if not atEnd(p):
                    discard advance(p)
                    skipNewlines(p)
                    continue
                else:
                    break
            addChild(typeNode, arg)
            skipNewlines(p)

            if atEnd(p):
                break

            if peekKind(p) == tkComma or peek(p).lexeme == ",":
                discard advance(p)
                skipNewlines(p)
                continue
            elif peek(p).lexeme == ">":
                discard advance(p)
                break
            else:
                discard advance(p)
                skipNewlines(p)
                continue

    return typeNode

method parseBody(p: Parser; stopKinds: seq[Kind]): Ast {.base.} =
    # helper: create empty pendingAttach sentinel
    proc emptyPending(): Ast =
        newAst(tkUnknown, "")

    let root = newAst(astBlock, "block")
    var st: seq[Frame] = @[]
    st.add(Frame(node: root, endKinds: stopKinds, pendingAttach: emptyPending()))

    skipNewlines(p)
    while st.len > 0 and not atEnd(p):
        skipNewlines(p)
        if atEnd(p): break

        var top = st[^1]
        let k = peekKind(p)

        # handle special case: if k closes the top frame
        if k in top.endKinds:
            # special handling for .elif / .else when top.pendingAttach is an astIf
            if (k == tkDotElif or k == tkDotElse) and top.pendingAttach.kind == astIf:
                # consume the token and create clause frames (do not attach astIf to parent yet)
                if k == tkDotElif:
                    discard advance(p) # consume .elif
                    skipNewlines(p)
                    discard expect(p, tkLParen)
                    let elifCond = parsePrimary(p)
                    discard expect(p, tkRParen)
                    skipNewlines(p)
                    discard expect(p, tkHave)
                    # create clause and its body, attach clause to the astIf (pendingAttach)
                    var clause = newAst(astClause, ".elif")
                    addChild(clause, elifCond)
                    let clauseBody = newAst(astBlock, "clause")
                    addChild(clause, clauseBody)
                    addChild(top.pendingAttach, clause)
                    # push new frame for the clause body (it will close on end/else/elif)
                    st.add(Frame(node: clauseBody, endKinds: @[tkEnd, tkDotElse, tkDotElif], pendingAttach: emptyPending()))
                    continue
                else:
                    # .else
                    discard advance(p) # consume .else
                    skipNewlines(p)
                    discard expect(p, tkHave)
                    var clause = newAst(astClause, "true")
                    var clauseBody = newAst(astBlock, "clause")
                    addChild(clause, clauseBody)
                    addChild(top.pendingAttach, clause)
                    # push a clause body frame that only ends on tkEnd
                    st.add(Frame(node: clauseBody, endKinds: @[tkEnd], pendingAttach: emptyPending()))
                    continue
            else:
                # normal end of the top frame: consume end token and pop frame
                discard advance(p)
                let finished = st[^1]
                st.del(st.len - 1)
                if st.len == 0:
                    break
                if finished.pendingAttach.kind != tkUnknown:
                    # attach pendingAttach node to parent node
                    addChild(st[^1].node, finished.pendingAttach)
                else:
                    addChild(st[^1].node, finished.node)
                continue

        # not an end token => parse a statement in the context of top.node
        case k
        of tkDotSet, tkDotLet, tkDotConst:
            let tok = advance(p)
            skipNewlines(p)
            let target = parsePrimary(p)
            skipNewlines(p)
            var typeNode: Ast = newAst(tkUnknown, "")
            if not atEnd(p) and peek(p).lexeme == ":":
                discard advance(p)
                skipNewlines(p)
                typeNode = parseType(p)
                skipNewlines(p)
            let value = parsePrimary(p)
            var n = newAst(tok.kind, tok.lexeme)
            addChild(n, target)
            if typeNode.kind != tkUnknown:
                addChild(n, typeNode)
            addChild(n, value)
            addChild(top.node, n)

        of tkDotInvoke:
            let tok = advance(p)
            skipNewlines(p)
            if peekKind(p) == tkIdent:
                let id = advance(p)
                var fn = newAst(tkIdent, id.lexeme)
                if peekKind(p) == tkLParen:
                    discard advance(p)
                    skipNewlines(p)
                    if peekKind(p) == tkRParen:
                        discard advance(p)
                    else:
                        while true:
                            let a = parsePrimary(p)
                            addChild(fn, a)
                            skipNewlines(p)
                            if peekKind(p) == tkComma:
                                discard advance(p); skipNewlines(p); continue
                            break
                        discard expect(p, tkRParen)
                var n = newAst(tkDotInvoke, tok.lexeme)
                addChild(n, fn)
                addChild(top.node, n)
            else:
                let callee = parsePrimary(p)
                var n = newAst(tkDotInvoke, tok.lexeme)
                addChild(n, callee)
                addChild(top.node, n)

        of tkDotWhile:
            let tok = advance(p)
            skipNewlines(p)
            discard expect(p, tkLParen)
            let cond = parsePrimary(p)
            discard expect(p, tkRParen)
            skipNewlines(p)
            discard expect(p, tkHave)
            # create astWhile and its body, but DO NOT attach to parent yet; attach when body closes
            var w = newAst(astWhile, tok.lexeme)
            addChild(w, cond)
            let bodyBlock = newAst(astBlock, "block")
            addChild(w, bodyBlock)
            # push a frame for the while body, with pendingAttach = w (so w is attached to parent when body closes)
            st.add(Frame(node: bodyBlock, endKinds: @[tkEnd], pendingAttach: w))

        of tkDotIf:
            let tok = advance(p)
            skipNewlines(p)
            discard expect(p, tkLParen)
            let cond = parsePrimary(p)
            discard expect(p, tkRParen)
            skipNewlines(p)
            discard expect(p, tkHave)
            # create if node; create initial then clause and push frame that will close on end/elif/else
            var ifn = newAst(astIf, tok.lexeme)
            addChild(ifn, cond)
            let thenBody = newAst(astBlock, "then")
            addChild(ifn, thenBody)   # attach then-block as first child of if
            # push frame for the thenBody; pendingAttach holds the astIf so we can add clauses and only attach at final end
            st.add(Frame(node: thenBody, endKinds: @[tkEnd, tkDotElse, tkDotElif], pendingAttach: ifn))

        of tkDotFor:
            let tok = advance(p)
            skipNewlines(p)
            discard expect(p, tkLParen)
            let varNode = parsePrimary(p)
            skipNewlines(p)
            if peekKind(p) == tkIn or (peekKind(p) == tkIdent and peek(p).lexeme == "in"):
                discard advance(p)
            let iterable = parsePrimary(p)
            discard expect(p, tkRParen)
            skipNewlines(p)
            discard expect(p, tkHave)
            var forn = newAst(astForIn, tok.lexeme)
            addChild(forn, varNode)
            addChild(forn, iterable)
            let bodyBlock = newAst(astBlock, "block")
            addChild(forn, bodyBlock)
            st.add(Frame(node: bodyBlock, endKinds: @[tkEnd], pendingAttach: forn))

        of tkFuncSet:
            discard advance(p) # consumes 'funcset'
            skipNewlines(p)
            let nameTok = expect(p, tkIdent)
            var fnNode = newAst(astFunc, nameTok.lexeme)
            var paramsNode = newAst(astParams, "")
            discard expect(p, tkLParen)
            skipNewlines(p)
            if peekKind(p) != tkRParen:
                while true:
                    let paramTok = expect(p, tkIdent)
                    var paramNode = newAst(tkIdent, paramTok.lexeme)
                    if peekKind(p) == tkColon:
                        discard advance(p); skipNewlines(p)
                        let tnode = parseType(p)
                        if tnode.kind != tkUnknown:
                            addChild(paramNode, tnode)
                    addChild(paramsNode, paramNode)
                    skipNewlines(p)
                    if peekKind(p) == tkComma:
                        discard advance(p); skipNewlines(p); continue
                    break
            discard expect(p, tkRParen)
            skipNewlines(p)
            if peekKind(p) == tkArrow:
                discard advance(p); skipNewlines(p)
                if peekKind(p) == tkType:
                    let ret = parseType(p)
                    if ret.kind != tkUnknown:
                        addChild(fnNode, ret)
                elif peekKind(p) == tkIdent:
                    let r = advance(p)
                    addChild(fnNode, newAst(tkIdent, r.lexeme))
            skipNewlines(p)
            discard expect(p, tkHave)
            # attach params and body placeholder, push frame for body with pendingAttach = fnNode
            addChild(fnNode, paramsNode)
            let bodyBlock = newAst(astBlock, "func-body")
            addChild(fnNode, bodyBlock)
            st.add(Frame(node: bodyBlock, endKinds: @[tkEnd], pendingAttach: fnNode))

        else:
            # fallback expression / single-item (use parsePrimary)
            let e = parsePrimary(p)
            addChild(top.node, e)

    # end loop
    return st[^1].node

method parseProgram* (p: Parser): Ast {.base.} =
    var root = newAst(astProgram, "program")
    # use parseBody to build program children until EOF
    let blockk = parseBody(p, @[tkEof])
    for c in blockk.children:
        addChild(root, c)
    return root
