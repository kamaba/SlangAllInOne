# CommentSpaceNegTest - negative case: compile.isForceSpaceAfterSharp = true
# forces at least one space between '#' and the line-comment text.
#
# Header comments here all use a space, so they are compliant. The three
# violation comments below are ordinary line comments whose text starts
# immediately after '#' with NO leading space: standalone at file level,
# standalone inside _main_, and trailing after a statement.
#
# Exempt forms (must NOT be flagged): block comments #! ... !#, #!md doc
# blocks, ##! nested block comments, and empty comments ('#' directly
# followed by a newline / end of file).
#
# Expected: compile FAILS.
#   Exactly 3 errors: LID 20120 (TokenLexerCommentSpaceRequired).
#   Compliant line comments and the #!...!# block below trigger nothing.
#   No CommentSpaceNegTest.module.json is produced.
#neg-violation-1: standalone comment without space (file top level)
Project
{
    _main_()
    {
        #! block comments are exempt: '#' belongs to the '#!' marker !#
        # compliant line comment (space after '#')
#neg-violation-2: standalone comment without space (inside _main_)
        SystemPrintln("comment space neg test")   #neg-violation-3: trailing comment without space
    }
    _before_()
    {
    }
}
