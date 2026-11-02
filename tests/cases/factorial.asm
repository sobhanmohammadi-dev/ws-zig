# Recursive factorial of 5.
push 5
call fact
outnum
end

fact:
dup
push 1
sub
ifzero base
push 0
swap
store
push 0
retrieve
push 1
sub
call fact
push 0
retrieve
mul
ret

base:
discard
push 1
ret
