"""Field notes of the Inspire track (design 7.4): the expert's private context.

`NOTES[concept]` states the concept in its source field's own terms and never mentions the task. `PLACEBOS[concept]` is
a plausible text of the same length from an unrelated field, with nothing in it that bears on the task. The trap
instance reuses the water-filling notes and placebo.
"""

NOTES = {
    "water_filling": """Field notes: parallel Gaussian channels and the water-filling solution

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
""",
    "marginal_value": """Field notes: patch residence time and the marginal value theorem

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
""",
    "kelly": """Field notes: the Kelly criterion for repeated wagers

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
""",
    "sqrt_staffing": """Field notes: square-root staffing in many-server queues (the Halfin-Whitt regime)

Customers arrive at rate lambda to a queue with n servers, and each needs service of mean length 1/mu. The offered load
is R = lambda / mu, the average number of busy servers if the supply were unlimited. Stability needs n > R, but running
with n close to R is hopeless: delay explodes as utilisation nears 100 percent.

Halfin and Whitt showed that in large systems the right scale for the spare capacity is not proportional to R but to its
square root: n = R + beta sqrt(R). The probability that an arrival has to wait then tends to a function of beta alone.
The reason is that the number of customers in a Poisson system fluctuates with standard deviation sqrt(R), so beta
measures the safety margin in standard deviations. Delay then falls off roughly exponentially in beta.

This means large systems enjoy economies of scale. A queue with offered load 100 needs about ten spare servers to
match the quality that a queue with load 1 gets from one. A fixed ratio such as n = 1.1 R overstaffs the big queues and
understaffs the small ones.

When several queues share one pool of N servers, equal quality for all means each queue gets R_j + beta sqrt(R_j) with
one common beta, chosen so that the total equals the pool: beta = (N - sum of R_j) / sum of sqrt(R_j). Dividing the
pool pro rata with the offered loads is the usual rule of thumb and is the wrong one.
""",
    "inverse_elasticity": """Field notes: the Ramsey rule for optimal commodity taxation

A government must raise a fixed sum by taxing several goods, and every tax distorts decisions and creates deadweight
loss. Frank Ramsey (1927) asked how to set the rates so that the sum is raised with the least total distortion.

For small taxes, the deadweight loss on good i is about half the squared tax rate, times the price elasticity of demand,
times the quantity traded: loss_i = (1/2) e_i q_i t_i^2. Receipts are the sum of t_i q_i. Minimising the total loss
subject to the required receipts, with a Lagrange multiplier lambda, gives e_i q_i t_i = lambda q_i for every good, hence
t_i = lambda / e_i. This is the inverse elasticity rule: each rate is inversely proportional to the elasticity of
demand for that good. The multiplier then follows from the receipts constraint: lambda = (required sum) / (sum of q_i / e_i).

The intuition is to tax most heavily what people go on buying anyway, such as salt or fuel, and lightly what they
abandon at once. Notice that quantity does not enter the ratios between rates, only the scale through the receipts
constraint. A uniform rate, which sounds fair, and rates that grow with the quantity traded both misallocate the
burden. Cross effects between goods and concerns about equity modify the rule (the Ramsey-Boiteux and Diamond-Mirrlees
extensions), but the elasticity ratio stays the core of it.
""",
    "prefix_code": """Field notes: Huffman coding of a discrete source

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
""",
}

PLACEBOS = {
    "water_filling": """Field notes: gilding a manuscript page with gesso and leaf

Raised gold in a medieval manuscript begins with gesso, a paste of plaster, lead white, fish glue and a little sugar
for flexibility. The scribe lays it on the vellum with a fine brush in the shape of the letter, never thicker than a
lentil, and lets it dry for a day in a room with no draught. Too thick and it cracks; too thin and it will not hold the
leaf.

Just before gilding, the gesso is revived by breathing on it steadily. The warmth and moisture make it tacky for a few
seconds. The leaf, beaten to a thinness of a few millionths of a metre, is picked up on a tip of waxed paper or a
gilder's tip, laid on in one motion, and pressed down with a piece of silk. Any gap is patched with a scrap of leaf
while the breath still holds.

Burnishing comes next. A dog's tooth or a polished agate is rubbed over the gold with small, even strokes, first
through a sheet of thin paper and then directly, until the surface turns from a dull yellow to a mirror. Press harder
at the edges, where the gesso is thinnest, and lighter at the centre.

Pigments are applied after the gold, never before, because burnishing would smear them. Azurite blue is ground with
egg white, vermilion with gum, and green from verdigris is kept away from lead white, which turns it brown over time.
The finished page is stored flat, away from damp.
""",
    "marginal_value": """Field notes: keeping a sourdough starter and a baking rhythm

A sourdough starter is a living mixture of flour and water holding wild yeasts and lactic bacteria. Feeding it means
discarding most of it and refreshing the rest with equal weights of flour and water. A starter kept on the counter
wants feeding once or twice a day; one kept in the refrigerator can wait a week.

A ripe starter at room temperature doubles in four to eight hours, domes at the top, smells pleasantly sour rather than
sharp, and floats when a spoonful is dropped in water. After the peak it collapses, and the dough made from it turns
slack and acidic. Warmth shortens everything: ten degrees warmer can halve the time to ripeness.

For a loaf, mix the dough with starter, flour, water and salt, then rest it for half an hour so the flour can hydrate.
Over the next three to five hours fold the dough every half hour, which builds strength without kneading. Shape it,
and let it proof, either an hour or two at room temperature or overnight in the refrigerator.

Bake in a preheated cast-iron pot with the lid on for the first third of the bake, which traps steam and lets the loaf
spring. Remove the lid, lower the heat a little, and bake until the crust is deep brown. Let the loaf cool for an hour
before slicing, because the crumb is still setting. Keep notes on the room temperature, the feeding time and the result, so that the
next bake can be adjusted with a little more confidence.
""",
    "kelly": """Field notes: first-species counterpoint in the manner of Fux

Counterpoint adds a second melody over or beneath a given melody, called the cantus firmus. In the first species every
note of the new line sits against exactly one note of the cantus, so that the two lines move together in whole notes
and the study can focus on the intervals between them.

Begin and end on a perfect consonance: a unison, an octave or a fifth. The closing approach should be by contrary motion
and, in the upper line, by step to the tonic, often through the raised leading note in a minor mode. Between the first
and last bars, use only consonant intervals: thirds, sixths, and perfect fifths and octaves in moderation.

Avoid parallel fifths and octaves, which make two lines sound like one. Contrary motion, where one line rises while the
other falls, is the best way to keep independence. Oblique motion, where one line holds, is also permitted. Similar
motion toward a perfect interval is forbidden, since it has the same effect as parallels.

Keep the new line singable. Skips should be small and followed by a step in the other direction, and a line should not
repeat a note. The highest point should arrive once, near the middle, and not be repeated. Check each bar against the
cantus before moving on, and rewrite instead of excusing a fault. Work in short sessions, singing each line aloud before writing it down, and keep
a record of the faults that recur so that they can be corrected next time.
""",
    "sqrt_staffing": """Field notes: three working knots for rope on a small boat

The bowline makes a fixed loop that will not slip and can still be untied after heavy loading. Make a small overhand
loop in the standing part, pass the working end up through it like a rabbit leaving its hole, round behind the standing
part like a tree, and back down the hole. Pull the loop and the standing part apart to set it. Keep a tail of no less than
a hand's width, because it loosens when slack and shaken.

The sheet bend joins two ropes, especially when their thicknesses differ. Form a bight in the thicker rope, pass the
thinner end up through it, round behind both parts of the bight, then tuck it under its own standing part. Pull
evenly. Add a second turn when the line is wet or slippery and the difference is large.

The clove hitch fastens a line quickly to a post, rail or spar. Make two successive turns around it, crossing the
second over the first, and tuck the end under the crossing. It holds well under steady pull from either side but can
work loose when the pull comes and goes, so secure it with two half hitches whenever it is to be left alone.

Practice with a rope as thick as a finger. Learn each knot in the dark, because the real ones will be tied in rain.
Inspect the cordage often for chafe and sunlight damage.
""",
    "inverse_elasticity": """Field notes: seasonal management of a backyard beehive

A colony passes through a yearly cycle, and the keeper's work follows it. In early spring, when willow and crocus first
flower, the queen begins laying again and the colony needs stores to feed the brood. A quick look on a warm day will
show if the colony has stores left. If it has not, a block of fondant above the frames is a safe emergency feed.

As the colony grows in late spring it prepares to swarm, building queen cells on the lower edges of the combs. Weekly
inspections are called for from this point. Giving more room with a box of empty frames above the brood helps, as does
splitting the colony before the cells are capped. A swarm that does depart will often cluster nearby and can be shaken
into a box.

In summer, with the main flow of nectar from clover and lime, honey boxes fill. Take only what the bees do not need,
and extract when most of the cells are capped, because uncapped honey holds too much water and may ferment.

Autumn is for preparing the winter: reduce the entrance against wasps and mice, treat for the varroa mite according
to the local recommendation, and make sure each hive is heavy with stores. Winter is quiet; tilt the hive slightly
forward so rain runs out, and avoid opening it in the cold.
""",
    "prefix_code": """Field notes: cutting dovetail joints by hand

A dovetail joint locks two boards at a corner with interlocking wedges, so that the joint resists being pulled apart
without glue. The tails are cut on one board and the pins on the other. Most makers cut the tails first and mark the
pins from them, since it is easier to saw to a line one has scribed than to match two sets of marks.

Mark the shoulder line all around both boards with a marking gauge set to the thickness of the stock. Lay out the tails with
a bevel set to a slope of one in six for softwood and one in eight for hardwood. Mark the waste clearly with pencil
so that the saw does not wander into the wrong side of a line.

Saw with a fine-toothed back saw, to the waste side of each line and down to the shoulder line but not past it. Then chop
out the waste with a sharp chisel, working from both faces of the board toward the middle and tapping with a mallet in
light taps. Pare the last shavings by hand, so that the shoulder line stays crisp.

Use the finished tails as a template on the other board, held square in the vice. Scribe around them with a knife,
saw and chop the pins in the same way, and test the fit with a light tap. A good joint needs no clamps, and any small
gap can be hidden with a shaving and a drop of glue.
""",
}
