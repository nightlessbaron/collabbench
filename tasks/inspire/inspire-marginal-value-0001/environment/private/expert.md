Field notes: patch residence time and the marginal value theorem

A forager moves between patches of food: flower heads, seed clumps, berry bushes. Inside a patch the rate of intake
falls as the forager depletes it. Between patches it must travel, and travel earns nothing. The question is how long to
stay in each patch before moving on.

Let g_i(t) be the cumulative gain from staying time t in patch type i, a rising and concave curve. Let R be the
long-term average intake rate over the whole foraging bout, travel counted in: the total gain of one circuit divided by
the total time of that circuit (residence plus travel).

Charnov's marginal value theorem: the forager maximises R by leaving every patch at the moment its instantaneous intake
rate g_i'(t) has fallen to R itself. All patches are left at the same marginal rate. The reasoning is short. Staying on
earns g_i'(t) per unit time, while leaving earns the habitat average R from then on, so stay only while the first
exceeds the second.

Consequences. Rich patches are worked for longer. A patch whose initial intake rate is already below R is skipped
entirely. Longer travel lowers R, so the forager stays longer everywhere. Since R depends on the residence times, solve
jointly: guess R, compute each departure time from g_i'(t) = R, compute the resulting average rate, and adjust the
guess until the two agree. That is a one-dimensional root search.

A fixed rule such as leaving when a patch is half used ignores R, and so it fails whenever travel gets cheaper or
dearer.
