# DELIBERATE DEVIATION
# The reference reads a full Haskell Integer literal, so it accepts 0x10.
# This interpreter reads decimal input only.
push 0
readnum
push 0
retrieve
outnum
end
