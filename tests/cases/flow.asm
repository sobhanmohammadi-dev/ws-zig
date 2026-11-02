# Calls, returns, unconditional and conditional jumps.
call greet
push 3
call countdown
jump done

greet:
push 65
outchar
ret

countdown:
dup
ifzero finish
outnum
push 32
outchar
push 1
sub
jump countdown

finish:
discard
ret

done:
push 46
outchar
end
