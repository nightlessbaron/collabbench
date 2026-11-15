Field notes: Huffman coding of a discrete source

A source emits symbols with known probabilities. We give each symbol a bit string, its codeword, so that no codeword is
the beginning of another (a prefix-free code), which allows instant decoding. The cost is the expected codeword length,
the sum of p_i l_i. Kraft's inequality says that a prefix-free code with lengths l_i exists exactly when the sum of
2^(-l_i) is at most 1: a codeword of length l uses up a fraction 2^(-l) of the tree of all bit strings. The entropy H of
the source is a lower bound on the cost.

Huffman (1952) built an optimal code greedily. Repeatedly take the two least probable nodes, join them under a new node
whose probability is their sum, and continue until one node remains. A symbol's codeword length is its distance from the
root. Ties do no harm.

Properties. Likelier symbols get shorter words. The two least likely symbols end up with the same, greatest length. The
lengths are not simply -log2 p rounded, but the expected length is within one bit of H. Worked example: probabilities
0.4, 0.3, 0.2, 0.1 give lengths 1, 2, 3, 3.

Pitfalls. Fixed-width words waste bits when the probabilities are skewed. Lengths 1, 2, 3, ... assigned by rank are
good only for extremely geometric probabilities. And a set of lengths that violates Kraft's inequality cannot be built
at all, however sensible it looks.
