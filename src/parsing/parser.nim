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

proc pushFrame(st: var seq[Frame]; node: Ast; endKs: seq[Kind]) =
    st.add(Frame(node: node, endKinds: endKs))

proc popFrame(st: var seq[Frame]): Frame =
    let f = st[^1]
    st.del(st.len - 1)
    return f

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
method expectSilent(p: Parser; k: Kind): Token {.base.} =
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
    of tkString:
        let t = advance(p)
        return newAst(tkString, t.lexeme)
    of tkIdent:
        let id = advance(p)
        var node = newAst(tkIdent, id.lexeme)

        # optional call
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
                discard expectSilent(p, tkRParen)
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
                    discard expectSilent(p, tkRParen)
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
        discard expectSilent(p, tkRParen)
        return inner
    else:
        # unknown token: consume and return unknown node
        let t = advance(p)
        return newAst(tkUnknown, t.lexeme)

method parseProgram* (p: Parser): Ast {.base.} =
    let root = newAst(astProgram, "program")
    var stack: seq[Frame] = @[]
    pushFrame(stack, root, @[tkEof])

    while stack.len > 0 and not atEnd(p):
        skipNewlines(p)
        if atEnd(p): break
        let cur = stack[^1]
        let k = peekKind(p)

        # close frame if token matches any endKinds
        if k in cur.endKinds:
            discard advance(p) # consume the end token (tkEnd, tkDotElse, etc.)
            if stack.len > 1:
                let finished = popFrame(stack)
                addChild(stack[^1].node, finished.node)
                continue
            else:
                break

        case k
        of tkDotSet, tkDotLet, tkDotConst:
            let tok = advance(p)
            skipNewlines(p)
            let target = parsePrimary(p)
            skipNewlines(p)
            let value = parsePrimary(p)
            var n = newAst(tok.kind, tok.lexeme)
            addChild(n, target); addChild(n, value)
            addChild(stack[^1].node, n)
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
                        discard expectSilent(p, tkRParen)
                var n = newAst(tkDotInvoke, tok.lexeme)
                addChild(n, fn)
                addChild(stack[^1].node, n)
            else:
                let callee = parsePrimary(p)
                var n = newAst(tkDotInvoke, tok.lexeme)
                addChild(n, callee)
                addChild(stack[^1].node, n)
        of tkDotWhile:
            let tok = advance(p)
            skipNewlines(p)
            discard expectSilent(p, tkLParen)
            let cond = parsePrimary(p)
            discard expectSilent(p, tkRParen)
            skipNewlines(p)
            discard expectSilent(p, tkHave)
            var w = newAst(astWhile, tok.lexeme)
            addChild(w, cond)

            # frame ends on tkEnd
            pushFrame(stack, w, @[tkEnd])
        of tkDotIf:
            let tok = advance(p)
            skipNewlines(p)
            discard expectSilent(p, tkLParen)
            let cond = parsePrimary(p)
            discard expectSilent(p, tkRParen)
            skipNewlines(p)
            discard expectSilent(p, tkHave)
            var ifn = newAst(astIf, tok.lexeme)
            addChild(ifn, cond)

            # then-block ends on tkEnd or tkDotElse or tkDotElif
            pushFrame(stack, ifn, @[tkEnd, tkDotElse, tkDotElif])
        of tkDotFor:
            let tok = advance(p)
            skipNewlines(p)
            discard expectSilent(p, tkLParen)
            var varNode = parsePrimary(p)
            skipNewlines(p)

            # accept either 'in' as ident or some token
            if peekKind(p) == tkIdent and peek(p).lexeme == "in":
                discard advance(p)
            let iterable = parsePrimary(p)
            discard expectSilent(p, tkRParen)
            skipNewlines(p)
            discard expectSilent(p, tkHave)
            var fn = newAst(astForIn, tok.lexeme)
            addChild(fn, varNode); addChild(fn, iterable)
            pushFrame(stack, fn, @[tkEnd])
        of tkFuncSet:
            discard advance(p) # discard here because the keyword is already known

            skipNewlines(p)
            let nameTok = expectSilent(p, tkIdent)
            var fnNode = newAst(astFunc, nameTok.lexeme)
            discard expectSilent(p, tkLParen)
            skipNewlines(p)
            if peekKind(p) != tkRParen:
                while true:
                    let param = expectSilent(p, tkIdent)
                    var paramNode = newAst(tkIdent, param.lexeme)
                    if peekKind(p) == tkColon:
                        discard advance(p)
                        if peekKind(p) == tkIdent:
                            let typ = advance(p)
                            paramNode.lexeme &= ":" & typ.lexeme
                    addChild(fnNode, paramNode)
                    if peekKind(p) == tkComma:
                        discard advance(p); skipNewlines(p); continue
                    break
            discard expectSilent(p, tkRParen)
            skipNewlines(p)
            if peekKind(p) == tkArrow:
                discard advance(p)
                if peekKind(p) == tkIdent:
                    let rt = advance(p)
                    let rn = newAst(tkIdent, rt.lexeme)
                    addChild(fnNode, rn)
            skipNewlines(p)
            discard expectSilent(p, tkHave)
            pushFrame(stack, fnNode, @[tkEnd])
        else:
            # expression / statement fallback
            let e = parsePrimary(p)
            addChild(stack[^1].node, e)

    # close remaining frames
    while stack.len > 1:
        let finished = popFrame(stack)
        addChild(stack[^1].node, finished.node)

    return stack[0].node
