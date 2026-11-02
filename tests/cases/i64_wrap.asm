# DELIBERATE DEVIATION
# Values are 64-bit two's complement, so this wraps instead of producing
# 9223372036854775808 the way Haskell's arbitrary-precision Integer does.
push 9223372036854775807
push 1
add
outnum
end
