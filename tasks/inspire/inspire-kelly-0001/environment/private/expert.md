Field notes: the Kelly criterion for repeated wagers

A gambler faces a series of independent favourable wagers and wants the bankroll to grow as fast as possible in the
long run. A wager that pays b units per unit risked, won with probability p and otherwise lost entirely, multiplies the
bankroll by (1 + b f) after a win and by (1 - f) after a loss, where f is the fraction of the bankroll wagered. Because
growth compounds, the long-run exponential growth rate is the expected logarithm: G(f) = p log(1 + b f) + (1 - p)
log(1 - f).

Setting the derivative to zero gives Kelly's fraction f* = p - (1 - p) / b, which is the advantage divided by the odds,
(b p - (1 - p)) / b. When the advantage is zero or negative, the best fraction is zero: pass on the wager.

Wagering more than f* lowers growth, and at about twice f* growth drops to zero; beyond that the bankroll shrinks in the
long run even though every single wager is favourable. Wagering less gives up growth but lowers variance, and half of
f* still keeps three quarters of the growth.

With several wagers running side by side and resolved independently, the growth rates add, so each gets its own Kelly
fraction from its own p and b.

A common mistake is a small fixed fraction applied to every favourable wager. The right fraction scales with advantage
over odds, so a long shot with a big advantage and a near-even wager with a thin one call for quite different amounts.
