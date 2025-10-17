import kind, span

type
    Ast* = object
        kind*: Kind
        lexeme*: string
        children*: seq[Ast]
        span*: Span

proc newAst*(k: Kind; lex: string = ""): Ast =
    result = Ast(kind: k,
        lexeme: lex,
        children: @[],
        span: Span(startPos: 0, len: 0, line: 0, col: 0))

method addChild*(parent: var Ast; child: Ast) {.base.} =
    parent.children.add(child)
