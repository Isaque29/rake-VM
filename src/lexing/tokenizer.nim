import ../common/token
import ../common/kind

type
    Tokenizer* = ref object
        src*: string
        len*: int
        i*, line*, col*: int

proc newTokenizer *(s: string): Tokenizer =
    new(result)
    result.src = s
    result.len = s.len
    result.i = 0
    result.line = 1
    result.col = 1

proc isSpace(ch: char): bool {.inline.} =
    ch == ' ' or ch == '\t' or ch == '\r'

proc isNewline(ch: char): bool {.inline.} =
    ch == '\n'

proc isAlpha(ch: char): bool {.inline.} =
    (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or ch == '_'

proc isDigit(ch: char): bool {.inline.} =
    ch >= '0' and ch <= '9'

proc isIdentChar(ch: char): bool {.inline.} =
    isAlpha(ch) or isDigit(ch) or ch == '_'

proc peek(t: Tokenizer): char {.inline.} =
    if t.i >= t.len: '\0' else: t.src[t.i]


proc bump(t: Tokenizer): char =
    if t.i >= t.len:
        '\0'
    else:
        let ch = t.src[t.i]
        t.i += 1
        if ch == '\n':
            t.line += 1
            t.col = 1
        else:
            t.col += 1
        ch

proc subStrRange(s: string, a, b: int): string {.inline.} =
    if a >= b: "" else: s[a ..< b]

proc keywordKind(ident: string): Kind =
    case ident
        of "funcset": return tkFuncset
        else: return tkIdent

proc dotCmdKind(name: string): Kind =
    case name
        of "set": return tkDotSet
        of "let": return tkDotLet
        of "const": return tkDotConst
        of "invoke": return tkDotInvoke
        of "ret": return tkDotRet
        of "if": return tkDotIf
        of "elif": return tkDotElif
        of "else": return tkDotElse
        of "while": return tkDotWhile
        of "for": return tkDotFor
        of "break": return tkDotBreak
        of "continue": return tkDotContinue
        else: return tkUnknown

proc tokenize *(t: Tokenizer): seq[Token] =
    var outt: seq[Token] = @[]
    while true:
        while true:
            let ch = peek(t)
            if ch == '\0': break
            elif isSpace(ch): discard bump(t)
            elif isNewline(ch):
                let spos = t.i
                discard bump(t)
                outt.add(Token(kind: tkNewline, lexeme: "\n", startPos: spos,
                        len: 1, line: t.line-1, col: t.col))
                continue
            else:
                break

        if t.i >= t.len:
            outt.add(Token(kind: tkEof, lexeme: "", startPos: t.i, len: 0,
                    line: t.line, col: t.col))
            break

        let ch = peek(t)

        if ch == '#':
            discard bump(t); discard bump(t)
            while peek(t) != '\0' and not isNewline(peek(t)):
                discard bump(t)
            continue

        # dot commands (.set, .invoke, etc.) or a plain dot between identifiers
        if ch == '.':
            let start = t.i
            discard bump(t)
            if isAlpha(peek(t)):
                # this is a dot-command like .set or .invoke
                let idStart = t.i
                var idx = t.i
                while idx < t.len and isIdentChar(t.src[idx]): idx.inc
                let name = subStrRange(t.src, idStart, idx)

                # advance tokenizer
                while t.i < idx: discard bump(t)
                let dk = dotCmdKind(name)
                if dk != tkUnknown:
                    outt.add(Token(kind: dk, lexeme: "." & name,
                            startPos: start, len: t.i - start, line: t.line, col: t.col))
                else:
                    # treat as generic @IDENT -> emit tkAt + tkIdent
                    outt.add(Token(kind: tkAt, lexeme: "@", startPos: start,
                            len: 1, line: t.line, col: t.col))
                    outt.add(Token(kind: tkIdent, lexeme: name,
                            startPos: idStart, len: name.len, line: t.line, col: t.col))
                continue
            else:
                # plain dot (probably an error or at between tokens)
                outt.add(Token(kind: tkAt, lexeme: "@", startPos: start,
                        len: 1, line: t.line, col: t.col))
                continue

        # visibility token '*' or '~'
        if ch == '*' or ch == '~':
            let spos = t.i
            let c = bump(t)
            outt.add(Token(kind: tkVis, lexeme: $c, startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue

        # strings
        if ch == '"':
            let start = t.i
            discard bump(t) # consume opening "
            while peek(t) != '\0':
                let c = bump(t)
                if c == '\\':
                    if peek(t) != '\0': discard bump(t) # skip escaped char
                    continue
                elif c == '"':
                    break
            let lex = subStrRange(t.src, start, t.i)
            outt.add(Token(kind: tkString, lexeme: lex, startPos: start,
                    len: t.i - start, line: t.line, col: t.col))
            continue

        # numbers (integers)
        if isDigit(ch):
            let start = t.i
            var idx = t.i
            while idx < t.len and isDigit(t.src[idx]): idx.inc
            let lit = subStrRange(t.src, start, idx)
            while t.i < idx: discard bump(t)
            outt.add(Token(kind: tkNumber, lexeme: lit, startPos: start,
                    len: lit.len, line: t.line, col: t.col))
            continue

        # identifiers / keywords
        if isAlpha(ch):
            let start = t.i
            var idx = t.i
            while idx < t.len and isIdentChar(t.src[idx]): idx.inc
            let id = subStrRange(t.src, start, idx)
            while t.i < idx: discard bump(t)
            let kk = keywordKind(id)
            if kk != tkIdent:
                outt.add(Token(kind: kk, lexeme: id, startPos: start,
                        len: id.len, line: t.line, col: t.col))
            else:
                outt.add(Token(kind: tkIdent, lexeme: id, startPos: start,
                        len: id.len, line: t.line, col: t.col))
            continue

        # punctuation and small tokens
        case ch
        of '-':
            if t.i+1 < t.len and t.src[t.i+1] == '>':
                let spos = t.i
                discard bump(t); discard bump(t)
                outt.add(Token(kind: tkArrow, lexeme: "->", startPos: spos,
                        len: 2, line: t.line, col: t.col))
                continue
            else:
                let spos = t.i
                let c = bump(t)
                outt.add(Token(kind: tkUnknown, lexeme: $c, startPos: spos,
                        len: 1, line: t.line, col: t.col))
                continue
        of ':':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkColon, lexeme: ":", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        of ',':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkComma, lexeme: ",", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        of '(':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkLParen, lexeme: "(", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        of ')':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkRParen, lexeme: ")", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        of '[':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkLBracket, lexeme: "[", startPos: spos,
                    len: 1, line: t.line, col: t.col))
            continue
        of ']':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkRBracket, lexeme: "]", startPos: spos,
                    len: 1, line: t.line, col: t.col))
            continue
        of '{':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkLBrace, lexeme: "{", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        of '}':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkRBrace, lexeme: "}", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        of '=':
            let spos = t.i
            discard bump(t)
            outt.add(Token(kind: tkAssign, lexeme: "=", startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue
        else:
            let spos = t.i
            let c = bump(t)
            outt.add(Token(kind: tkUnknown, lexeme: $c, startPos: spos, len: 1,
                    line: t.line, col: t.col))
            continue

    return outt

