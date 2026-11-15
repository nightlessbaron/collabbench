Field notes: square-root staffing in many-server queues (the Halfin-Whitt regime)

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
