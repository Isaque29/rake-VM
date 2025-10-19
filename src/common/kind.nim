type
    Kind* = enum
        # structural / common
        tkEof,
        tkIdent,        # generic identifier (type names, function names, keywords not matched)
        tkAt,           # acess between identifiers, ex: Character@new
        tkNumber,
        tkNil,          # nil
        tkBool,         # true | false
        tkString,
        tkType,         # int, int8/16/32/64, string, bool, seq<T>, float, char,
                        # enum, object, number, seq<>, auto, void, nil...
        
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
        tkIn,           # in
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
        astParams,
        astBlock,
        
        astProgram,
        astIf,          # .if (a)          have end
        astClause,      # clause of an if/elif/else ast
        astWhile,       # .while (a)       have end
        astForIn,       # .for (a in b)    have end

        astFunc,        # funcset x(a) -> T have end
        astEnum,
        

        