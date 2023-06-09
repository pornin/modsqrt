# This is an example implementation of a square root extraction algorithm
# in a finite field with a "difficult" order, i.e. GF(q) such that q-1 is
# a multiple of a large-ish power of 2. If we write g = m*2^n + 1, then
# the classic Tonelli-Shanks algorithm first performs an exponentiation
# to the power (m-1)/2 (with cost O(log m) multiplications), then an extra
# step with cost O(n^2) multiplications (about n^2/4 on average, but about
# n^2/2 if a constant-time implementation is required). In the following
# text, we do not include the initial exponentation cost, which is the same
# for all considered algorithms.
#
# Bernstein (https://cr.yp.to/papers.html#sqroot) describes an optimization
# of the last step with precomputed tables; storage cost is O((2^w)*n/w),
# but decreases runtime cost to O((n/w)^2).
#
# Sarkar (https://eprint.iacr.org/2020/1407) reduces the runtime cost to
# O((n/w)^1.5), for the same storage cost of precomputed tables.
#
# The algorithm below uses a simple divide-and-conquer approach to get
# a cost in O(n*log n); the algorithm can furthermore benefit from
# lookup tables. While it is asymptotically better than Bernstein's and
# Sarkar's algorithms, it is not necessarily faster for a given field
# and overall storage cost. For a practical case, using q = 2^224 - 2^96 + 1
# (the field used in the NIST curve P-224) and tables with w-bit indices
# we get the following costs, expressed in squarings (S) and general
# multiplications (M):
#
#   n = 96             w = 2               w = 4               w = 6
#   storage (kB)         4                  10                  28
#   Bernstein:      94 S + 1178 M       92 S + 302 M        90 S + 138 M
#   Sarkar:        182 S +  338 M      170 S + 122 M       146 S +  82 M
#   This code:     310 S +  172 M      191 S + 124 M       142 S +  60 M
#
# We thus get costs similar to those of Sarkar for that field. For larger n,
# this code gets better (relatively); e.g. for n = 1024 (assuming a 2048-bit
# field):
#
#   n = 1024           w = 2               w = 4               w = 6
#   storage (kB)        393                 983                2742
#   Bernstein:    1022 S + 131330 M   1020 S + 32898 M    1018 S + 14708 M
#   Sarkar:       2087 S +  11801 M   1996 S +  4098 M    2241 S +  2378 M
#   This code:    4617 S +   2324 M   2852 S +  1668 M    2852 S +  1302 M
#
# In general, squarings are somewhat faster than generic multiplications
# (typically, a squaring cost is about 70 to 80% of a multiplication cost),
# thus converting multiplications into squarings is better. This code
# has the highest squarings-to-multiplications ratios, and also the lowest
# total operation counts, for the figures shown above.
#
# IMPORTANT: all these values are abstract estimates, and counting only
# multiplications. In particular:
#  - Large tables do not fit into L1 cache on large CPUs, making table
#    access more expensive.
#  - If constant-time operations are needed, then each lookup entails
#    reading the entire table, which disfavours use of large tables. For
#    w = 2, 4 or 6, each table contains 3, 15 or 63 entries, and each
#    entry is a field element (each table contains powers of a given
#    element; the first power is for exponent 0 and thus is always 1).
#  - Apart from the runtime usage cost of the tables, the table size may
#    also be important by itself, but how much it matters depends on the
#    overall system and is not easily compared with the CPU cost. It is
#    expected that small embedded systems, in particular, will prefer the
#    smallest tables (say, using w = 1 or 2).
#
#
# ALGORITHM DESCRIPTION
# ---------------------
#
# Field is GF(q) with q = m*2^n + 1, for an odd integer m, and n >= 1.
# The 2^n-th roots of 1 are a cyclic subgroup; g is a conventional fixed
# generator for that subgroup.
# NOTE: it is not required that q is prime; this algorithm also works for
# field extensions. In fact, the discrete logarithm solving step works for
# any group homomorphic to Z/(2^n)Z.
#
# For an input x != 0:
#
#   v <- x^((m-1)/2)
#   w <- x*v
#   h <- w*v   (hence: h = x*v^2 = (w^2)/x = x^m, thus h is a 2^n-th root of 1)
#   e <- solve_dlp(g, h)    (i.e. h = g^e mod p)
#
# A square root exists if and only if e is even; the putative square root
# is w*g^((2^n - e)/2).
#
# Tonelli-Shanks, Bernstein, Sarkar and this code all follow the steps
# above; they differ in the implementation of solve_dlp(g, h). We define
# solve_dlp(b, z) as follows:
#    b = g^(2^i) for some known integer i
#    z is in the subgroup generated by b
#    The function returns e such that z = b^e
# In this code, this is done recursively:
#
#    b = g^(2^i) has order exactly 2^lb, with lb = n - i
#    if lb == 1:
#        return 0 or 1, depending on whether z = 1 or -1, respectively
#    else:
#        lb0 = floor(lb/2)
#        lb1 = lb - lb0
#        e0 = solve_dlp(b^lb1, h^lb1)
#        e1 = solve_dlp(b^lb0, h*b^(2^lb0 - e0))
#        return e0 + ((e1 - 1) mod 2^lb1)*2^lb0
#
# This is, in fact, a DLP solving algorithm that was already described
# by Shoup (in the textbook "A computational introduction to number theory
# and algebra"), as a straightfoward divide-and-conquer variant of the
# Pohlig-Hellman algorithm.
#
# In a nutshell:
#
#  - If we write e = e0 + e1*2^lb0, then by raising both b and h to
#    the power lb1, we "erase" the bits e1, and get a sub-problem of
#    size lb0 bits that yields e0.
#
#  - Once e0 is obtained, we get e1 by replacing h with h/b^e0, which
#    clears the low bits of e and thus reduces to a sub-problem of
#    size lb1 bits.
#
#  - Since we want to avoid divisions, we do not divide h by b^e0;
#    instead, we multiply h by b^(2^lb0 - e0), which clears the
#    low bits of e, but also adds 1 to the high bits; this is why
#    we must correct the result on backtracing (the 'e1 - 1 mod 2^lb1').
#    (In some field extensions, in particular GF(p^2) for p = 3 mod 4,
#    inversion of a 2^n-th root of 1 can be done with a single negation
#    in GF(p), making division no more expensive than a multiplication,
#    and we can avoid this trick in such fields.)
#
# The recursion depth is logarithmic, and each depths involves O(n)
# multiplications, which is why the asymptotic cost is O(n*log n) (cost
# expressed in the number of field element multiplications).
#
# Lookup tables speed up the process in two ways:
#
#  - When lb is small enough, this is a matter of recognizing the value z
#    among the known 2^lb-th roots of 1, with a "reverse lookup". This can
#    be done by using only a small number of bits from the value (see the
#    minhc() function in the code below, to find a minimal-sized bit
#    pattern that is enough to distinguish all roots). We can thus stop
#    the recursion before reaching lb == 1.
#
#  - Computations of b^(2^lb0 - e0) can use precomputed tables of powers
#    of g. Typically, we use a w-bit window, and precompute all values
#    (g^(2^(i*w)))^j, for j = 0 to 2^w-1, and i*w < n.
#
# Some additional savings can be obtained by noticing that the second
# recursive call uses h*b^(2^lb0 - e0), and the callee will then raise
# that value to the power floor(lb1/2). But the caller previously computed
# h^(2^j) for some values of j (up to lb0, thus above floor(lb1/2)) and
# will get h^(2^floor(lb1/2)) "for free". The callee can thus replace
# the floor(lb1/2) squarings with about lb0/w multiplications, which is
# cheaper if w >= 3.
#
# Another optimization is in the top-level call to solve_dlp_pow2():
# when preparing for the second nested call, it computes b^(2^lb0 - e0),
# with b = g for this call, and e0 being even (if e0 is odd, then the
# initial input was not a square). We can thus compute g^((2^lb0 - e0)/2),
# and square it; this implies an extra squaring, but also yields an
# intermediate value that we can reuse for computing the final square root
# of the input.

# -------------------------------------------------------------------------

# An instance of SQRT encapsulates the precomputed tables for a given
# field. Parameters:
#    K        the finite field
#    w        the window size (in bits)
#    leaf_w   the reverse lookup window size (equal to w if unspecified)
#
# When constructed, each invocation of the instance (as a function) computes
# a square root.
class SQRT:

    # The initialization method computes all relevant tables. In a
    # practical implementation, this would be done once before compilation,
    # and the resulting table values would be hardcoded as read-only data.
    def __init__(self, K, w, leaf_w=None):
        # Get the field order q, and split it into q = m*2^n + 1, with m odd.
        self.K = K
        q = K.cardinality()
        assert (q & 1) == 1
        assert q >= 3
        m = q - 1
        n = 0
        while (m & 1) == 0:
            m >>= 1
            n += 1
        self.m = m
        self.n = n

        # Find g, a primitive 2^n-th root of 1; we find a non-square and
        # raise if to the power m.
        while True:
            g = K.random_element()
            if not(g.is_square()):
                break
        g = g**m

        # Compute gpp[i] = g^i for i = 0 to n-1. We check that gpp[n-1] = -1
        # (this confirms that g is indeed a primitive 2^n-th root).
        gpp = []
        gpp.append(g)
        t = g
        for j in range(1, n):
            t *= t
            gpp.append(t)
        assert gpp[n - 1] == K(-1)
        self.gpp = gpp

        # Precompute powers of g for our window size:
        #   gw[i][j] = g^(j*2^(i*w))  for 0 <= j < 2^w, and 0 <= i*w < n
        # We ensure that the window is not larger than n.
        if w > n:
            w = n
        assert w >= 1
        gw = []
        i = 0
        while i < n:
            gwt = []
            t = K(1)
            gwt.append(t)
            for j in range(1, 1 << w):
                t *= gpp[i]
                gwt.append(t)
            gw.append(gwt)
            i += w
        self.w = w
        self.gw = gw

        # Make the reverse-lookup table for the leaves.
        # We also add zero as a key so that solve_dlp_pow2() gracefully
        # handles the case of a zero input.
        #
        # NOTE: in an optimized implementation of this algorithm, we
        # would extract only a small bit pattern, as long as it is
        # enough to disambiguate the roots (see the minhc() function).
        # Similarly, the case of a zero could be handled within the
        # semantics of the reverse lookup rather than an extra value.
        #
        # We also keep a forward table for the square roots of the
        # leaves: if b = g^(2^(n - leaf_w)), then fhl[i] = sqrt(b^(-i))
        # (if n == leaf_w, then fhl[i] = b^(-ceil(i/2)))
        if leaf_w is None:
            leaf_w = w
        rll = {}
        rll[K(0)] = 0
        s = g**(1 << (n - leaf_w))
        t = K(1)
        rll[t] = 0
        if leaf_w < n:
            u = g**((1 << n) - (1 << (n - leaf_w - 1)))
        else:
            u = g**((1 << n) - (1 << (n - leaf_w)))
        v = K(1)
        fhl = []
        fhl.append(v)
        for i in range(1, 1 << leaf_w):
            t *= s
            if leaf_w < n or (i & 1) == 1:
                v *= u
            rll[t] = i
            fhl.append(v)
        self.rll = rll
        self.fhl = fhl
        self.leaf_w = leaf_w

        # We keep track of the cost of the last operation (in multiplications
        # and squarings, not counting the initial exponentiation).
        self.costM = 0
        self.costS = 0

    # Get the square root of x. If x is indeed a square in the field, then
    # one of its two square roots is returned. Which of the two roots is
    # returned is not specified. If x is not a square, then this call
    # returns None.
    def __call__(self, x):
        # Make sure the value is a field element.
        x = self.K(x)

        # v = x^((m-1)/2)
        # w = x*v
        # h = w*v = x^m
        v = x**((self.m - 1) >> 1)
        w = x*v
        h = w*v

        # We initialize the cost accounting. We do not include the cost
        # of computing the initial exponentation (v).
        self.costM = 2
        self.costS = 0

        # Get e such that 0 <= e < 2^n, and h = g^e.
        # If x == 0, then there is no solution; obtained value e is
        # in the 0 to 2^n-1 range, but not otherwise specified.
        # For x != 0, if x is a square, then value e is even, and d
        # is a square root of 1/h. If x is not a square, then e is an
        # unspecified odd integer in the 0 to 2^n-1 range, and d is
        # an unspecified field element.
        e, d = self.solve_dlp_pow2(0, h, True)

        # Candidate square root is w/sqrt(g^e).
        # If x == 0, we have w == 0, so we obtain the correct value 0.
        # If x != 0 and is a square, then e is even, and d = 1/sqrt(g^e).
        y = w*d
        self.costM += 1

        # If x is not a square then we replace the value with None.
        y = self.SELECT(y, None, x != 0 and (e & 1) != 0)
        return y

    # Return a1 if ctl == True, or a0 if ctl == False.
    def SELECT(self, a0, a1, ctl):
        # CT: in a constant-time implementation, ctl is secret and this
        # should use a constant-time selection.
        if ctl:
            return a1
        else:
            return a0

    # Return (g^(2^i))^(e mod 2^elen).
    # Requirement: i + elen <= n
    def GPOW(self, i, e, elen):
        # CT: in a constant-time implementation, the lookups gw[i][j]
        # must take into account that indices j are secret (but indices i
        # are not secret).
        e &= (1 << elen) - 1
        w = self.w
        wm = (1 << w) - 1
        ri = i % w
        i = i // w
        if ri != 0:
            e <<= ri
            elen += ri
        t = self.gw[i][e & wm]
        while True:
            elen -= w
            if elen <= 0:
                break
            e >>= w
            i += 1
            t *= self.gw[i][e & wm]
            self.costM += 1
        return t

    # Get the cost (in multiplications) of a GPOW call with these
    # parameters. This is used to determine if a specific optimization
    # is worth it.
    def GPOW_cost(self, i, elen):
        if elen == 0:
            return 0
        w = self.w
        ri = i % w
        if ri != 0:
            elen += ri
        return ((elen + w - 1) // w) - 1

    # Solve DLP of h in base b = g^(2^i).
    # Returned values are (e, d) such that h = b^e and d = b^(-e/2).
    # If i == 0 and h is not a square, then d does not exist; in that case,
    # returned value for e is an unspecified odd integer, and value for d is
    # unspecified.
    # If ret_d is False, then d is not computed, and None is returned instead.
    def solve_dlp_pow2(self, i, h, ret_d, helper=None):
        # Base is gpp[i] and has order exactly 2^lb.
        n = self.n
        w = self.w
        leaf_w = self.leaf_w
        lb = n - i

        # If the order of the base is at most 2^leaf_w, then this is a leaf
        # and we use the reverse-lookup table.
        #
        # NOTE: there is no strict need that the input size for the
        # reverse-lookup table matches w; since an optimized implementation
        # will use only a few bits per value, a larger reverse-lookup table
        # may be used.
        #
        # Conversely, for a given field and window size w, possible values
        # of lb at this point do not necessarily range all integers. For
        # instance, if n = 96 and w = 6, when lb is always a multiple of 6;
        # thus, an 11-bit leaf table (leaf_w = 11) would provide absolutely
        # no benefit over a smaller 6-bit leaf table in that case.
        if lb <= leaf_w:
            # If the original input was not a square then we can get
            # an invalid value h here. Similarly, if the input was 0, then
            # we get h = 0 here, which is not a 2^n-th root of 1. This
            # case must be handled specifically.
            # CT: in a constant-time implementation, all lookups must
            # be done in constant-time, even for invalid inputs.
            e = self.rll.get(h)
            if e is None:
                e = 1
            else:
                e >>= (leaf_w - lb)
            if ret_d:
                d = self.fhl[e << (leaf_w - lb)]
            else:
                d = None
            return (e, d)

        # Split the order.
        lb0 = lb >> 1
        lb1 = lb - lb0

        # First sub-call. If the current base is b, then:
        #   b0 = b^(2^lb1)
        #   h0 = h^(2^lb1)
        # If helper != None, then it should contain h0 (the caller might
        # have access to extra values that allow computing h0 more
        # efficiently).
        hlp = None
        nlb1 = lb1 - (lb1 >> 1)
        if helper is None:
            # Second nested call will need:
            #    (h*b^z)^(2^nlb1) = (h^(2^nlb1))*((b^(2^nlb1))^z)
            # with a value z computed below, of size lb0 bits.
            # If we do not provide a helper, this will use nlb1 squarings.
            # However, we get h^(2^nlb1) for free here, and the computation
            # of (b^(2^nlb1))^z is boosted with the precomputed tables, so
            # it might be cheaper to do it that way. The following apply:
            #
            #   - If lb1 <= leaf_w, then the nested call uses the reverse
            #     lookup table, and thus does not compute its h0 at all.
            #
            #   - (b^(2^nlb1))^z has a cost expressed in multiplications
            #     (not squarings), that furthermore depends on where i + nlb1
            #     falls among the precomputed window boundaries.
            cost_hlp = 1 + self.GPOW_cost(i + nlb1, lb0)
            do_hlp = True
            if lb1 <= leaf_w or cost_hlp >= nlb1:
                do_hlp = False

            h0 = h
            for j in range(0, lb1):
                if do_hlp and j == nlb1:
                    hlp = h0
                h0 *= h0
            self.costS += lb1
        else:
            h0 = helper
        e0, _ = self.solve_dlp_pow2(i + lb1, h0, False)

        # Second sub-call.
        #   b1 = b^(2^lb0)
        #   h1 = h*b^(2^lb0 - e0)
        # If hlp is not None, then it contains h^(2^nlb1), where nlb1
        # is the second split value that the recursive call will use
        # (i.e. ceil(lb1/2)); we can then compute its h0 value as:
        #   h^(2^nlb1) * (b^(2^nlb1))^(2^lb0 - e0)
        # This will be faster than letting it do nlb1 squarings, at
        # least if w >= 3.
        if ret_d:
            if i == 0:
                f = self.GPOW(0, ((1 << lb0) - e0 + 1) >> 1, lb0 - 1)
                f = self.SELECT(f, self.gpp[lb0 - 1], e0 == 0)
            else:
                f = self.GPOW(i - 1, (1 << lb0) - e0, lb0)
                f = self.SELECT(f, self.gpp[i - 1 + lb0], e0 == 0)
            h1 = f**2
            self.costS += 1
            # For i == 0, the basis is g, which is not a square. If input
            # h is not a square either, then the value h1 we compute later
            # (by multiplying the current h1 with h) will be incorrect and
            # will lead to failed reverse lookups in recursion tree leaves.
            # The three lines below would correct that, and ensure that even
            # in that case we at least get the correct (odd) discrete
            # logarithm value. However, that costs an extra field
            # multiplication, and this is not needed if the goal is to compute
            # square roots.
            #if i == 0:
            #    h1 = self.SELECT(h1, h1*self.gpp[0], (e0 & 1) != 0)
            #    self.costM += 1
        else:
            h1 = self.GPOW(i, (1 << lb0) - e0, lb0)
            h1 = self.SELECT(h1, self.gpp[i + lb0], e0 == 0)

        h1 *= h
        self.costM += 1
        if not(hlp is None):
            hlp1 = self.GPOW(i + nlb1, (1 << lb0) - e0, lb0)
            hlp1 = self.SELECT(hlp1, self.gpp[i + nlb1 + lb0], e0 == 0)
            hlp *= hlp1
            self.costM += 1
        e1, d1 = self.solve_dlp_pow2(i + lb0, h1, ret_d, helper=hlp)

        if ret_d:
            # We here have 1/d1^2 = (b^(2^lb0))^e1 = h1 = h*f^2.
            # Thus: 1/(d1*f)^2 = h
            #
            # If i == 0 and e0 is odd, then we used h1 = h*g*f^2, and we thus
            # have: 1/(d1*f)^2 = h*g = g^(e+1)
            # In that case, d1*f = g^(-(e+1)/2)
            d = d1*f
            self.costM += 1
        else:
            d = None

        # Since we used h1 = h*b^(2^lb0 - e0) instead of h1 = h/b^e0, the
        # obtained e1 must be decremented as a corrective action.
        e1 = (e1 - 1) & ((1 << lb1) - 1)

        return e0 + (e1 << lb0), d

    # Get the cost of the last computed square root. Cost is (S,M) with
    # S being the number of squarings, and M the number of other
    # multiplications which are not (necessarily) squarings. The cost DOES
    # NOT include the initial exponentiation (to the power (m-1)/2), which
    # would typically use an hand-optimized addition chain.
    def last_cost(self):
        return self.costS, self.costM

    # Run a self-test and report the cost (S,M) of each square root.
    def self_test(self):
        assert self(0) == self.K(0)
        for i in range(0, 100):
            x = self.K.random_element()**2
            assert self(x)**2 == x
            x *= self.gpp[0]
            assert self(x) is None
        return self.last_cost()

# Run tests and get costs for various degrees and window sizes.
def mkstats():
    nn = [32, 64, 96, 128, 256, 512, 1024]
    for n in nn:
        print('n = %d' % n)
        q = (1 << n) + 1
        while not q.is_prime():
            q += 1 << (n + 1)
        K = Zmod(q)
        for w in range(1, 11):
            S = SQRT(K, w)
            S.self_test()
            costS, costM = S.last_cost()
            print('   w = %2d:  %4d S + %4d M   total: %4d' % (w, costS, costM, costS + costM))

# For field K = Zmod(q) (q prime, q = m*2^n + 1 with m odd and n >= 1),
# and window size w (1 <= w <= n), get the position and size of a minimal-width
# pattern that distinguishes all 2^w-th roots of 1 in K. In other words, if
# the function returns (i,j), then the j-bit pattern in each value, starting
# at bit i (i=0 for least significant bit), has distinct values for all
# considered 2^w roots.
#
# If R is specified, it should be a field element (or an integer) such that
# the pattern is looked over all values x*R mod q, with x being a 2^w-th
# root of 1 (this can be used to get a pattern for values in Montgomery
# representation).
#
# For instance, with q = 2^224 - 2^96 + 1 (the field for elliptic curve P-224),
# and a 6-bit window size, this function returns (88,9), meaning that in order
# to distinguish all 64-th roots of 1 in that field, we can use the 9-bit
# pattern that starts at bit 88 in their respective canonical representations
# as integers in the 0 to q-1 range. If we specify R = 2, we get a shorter
# pattern (24,8), i.e. only 8 bits are necessary if we first multiply the
# value to lookup by 2 (which should be a fast operation). The reverse lookup
# table can thus be implemented as a single 256-byte table, using the 8-bit
# pattern as index. Alternatively, a constant-time implementation could
# instead use a 64-byte table that contains the 64 possible 8-bit patterns,
# and find which one matches the 2*z value for an input z which is a 64-th
# root of 1.
def minhc(K, w, R=None):
    # We need q prime here because we inspect the bit representation of
    # field elements when converted to integers. In all generality, elements
    # of finite field extensions cannot be converted to integers with Sage.
    # In fact, we would want to work on the in-memory representation of
    # field elements, but that depends on the target implementation.
    q = K.cardinality()
    assert (q & 1) == 1
    assert q >= 3
    assert q.is_prime()
    m = q - 1
    n = 0
    while (m & 1) == 0:
        m >>= 1
        n += 1
    assert w <= n
    while True:
        g = K.random_element()
        if not(g.is_square()):
            break
    g = g**m
    g = g**(1 << (n - w))
    rr = []
    t_init = K(1)
    if not(R is None):
        t_init *= R
    t = t_init
    rr.append(int(t))
    for i in range(1, 1 << w):
        t *= g
        rr.append(int(t))
    assert rr[1 << (w - 1)] == int(-t_init)
    t *= g
    assert t == t_init

    qlen = len(q.bits())
    min_i = 0
    min_j = len(q.bits())
    for i in range(0, max(qlen - w, 0)):
        for j in range(w, min_j):
            tt = []
            jm = (1 << j) - 1
            for k in range(0, 1 << w):
                tt.append((rr[k] >> i) & jm)
            tt.sort()
            uu = True
            for k in range(1, 1 << w):
                if tt[k - 1] == tt[k]:
                    uu = False
                    break
            if uu:
                min_i = i
                min_j = j
                break
    return min_i, min_j
