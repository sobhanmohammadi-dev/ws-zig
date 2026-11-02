# 2,000,000 iterations of a five-instruction loop.
push 2000000
loop:
dup
ifzero done
push 1
sub
jump loop
done:
discard
push 66
outchar
end
