Field notes: parallel Gaussian channels and the water-filling solution

A transmitter drives several independent Gaussian channels in parallel. Channel i adds noise of variance N_i. The
transmitter has total power P to spend, divided as P_i >= 0 with the P_i adding up to P. Over channel i the achievable
rate is (1/2) log(1 + P_i / N_i), and the total capacity is the sum over channels.

Every logarithm is concave, so one more unit of power on channel i gains 1 / (2 (N_i + P_i)). Capacity is greatest when
all channels that receive power have the same marginal gain, that is, the same value of N_i + P_i. Call that common
value the water level L. The rule is then P_i = max(0, L - N_i).

Picture the noise variances as the uneven bottom of a vessel. Pour the power in like water: it settles in the lowest
hollows first, the surface rises evenly, and any part of the bottom that stands above the eventual surface remains dry. A
channel that is too noisy gets nothing at all. This is the normal outcome when power is scarce.

To find L, sort the variances in ascending order. Try the k quietest channels, L_k = (P + sum of their N_i) / k, and
keep the largest k for which L_k still exceeds the k-th variance. Bisection on L, summing max(0, L - N_i) until it
reaches P, gives the same answer.

Two common shortcuts are wrong. Equal power on every channel wastes power on the noisiest ones. Power in proportion to
1 / N_i overshoots the quiet channels and still feeds the very noisy ones.
