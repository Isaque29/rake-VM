type
    Kind* = enum
        # structural / common
        tkEof,
        tkIdent,        # generic identifier (type names, function names, keywords not matched)
        tkAt,           # acess between identifiers, ex: Character@new
        tkNumber,
        tkString,
        tkArrow,        # ->
        tkColon,        # :
        tkComma,        # ,
        tkLParen,       # (
        tkRParen,       # )
        tkLBracket,     # [
        tkRBracket,     # ]
        tkLBrace,       # {
        tkRBrace,       # }
        tkVis,          # * and ~
        tkNewline,      # newline
        tkComment,
        tkUnknown,

        # top-level keywords / declarations
        tkHave,         # have
        tkEnd,          # end
        tkFuncSet,      # funcset

        # dot-commands
        tkDotSet,       # .set
        tkDotLet,       # .let
        tkDotConst,     # .const
        tkDotInvoke,    # .invoke
        tkDotRet,       # .ret
        tkDotIf,        # .if
        tkDotElif,      # .elif
        tkDotElse,      # .else
        tkDotWhile,     # .while
        tkDotFor,       # .for
        tkDotBreak,     # .break
        tkDotContinue   # .continue


        #ast nodes
        astProgram,
        astIf,          # .if (a)          have end 
        astWhile,       # .while (a)       have end
        astForIn,       # .for (a in b)    have end

        astFunc,        # funcset x(a) -> T have end
        astEnum,
        

        