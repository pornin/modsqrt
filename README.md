# Example Implementation of Square Roots in Finite Fields

This is an example implementation (in Sage) of the computation of square
roots in finite fields _GF(q)_ such that _q - 1_ is a multiple of a
relatively large power of two. If we write _q = 1 + m*2^n_ for some odd
integer _m_, then this is classically done with the Tonelli-Shanks
algorithm, whose cost is _O(n^2)_ multiplications in the field (not
counting an initial exponentiation) and can become prohibitive for large
values of _n_, as found in some fields (e.g. in the finite field for
NIST curve P-224, _n = 96_). There are some known optimizations with
precomputed tables and other tricks bringing the complexity to
_O(n^1.5)_. This implementation demonstrates use of a simple
divide-and-conquer strategy for the Pohlig-Hellman algorithm used
internally, that leads to a complexity of _O(n*log n)_, and in practice
seems to be as good or even better than previously known solutions.
