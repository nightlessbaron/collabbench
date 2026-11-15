Field notes: what a crystallographer reads into a structure file

These notes come from structural crystallography, for people who handle structure files without having solved one.

The file lists less than the crystal. A structure in the IUCr's Crystallographic Information File format (CIF) gives
the asymmetric unit: the smallest set of atoms from which the whole unit cell follows by the symmetry of the space
group. The symmetry operations are listed as coordinate triples, such as "minus x, y plus one half, minus z", under
the current operation tag or under the older equivalent-position tag; the two mean the same thing, and older files
use the older names throughout. When no operations are listed, they are the ones International Tables for
Crystallography, Volume A gives for the space group's number or symbol. To get the contents of the cell, apply every
operation to every atom, then bring each fractional coordinate back into the cell by subtracting its floor. Only a
file whose single operation is the identity can be read as it stands.

Images that coincide are one atom. An atom on a mirror plane, a rotation axis or an inversion centre (a special
position) is mapped onto itself by some of the operations, so several of its images land on the same spot. They are
one atom: merge them, keeping the original atom's label and its occupancy, never a sum. Test coincidence by distance
in angstroms under the periodic minimum image, not by comparing raw fractional numbers, which can differ by a whole
cell. Crystallographers call the number of distinct copies an atom has in the cell its site multiplicity, or Wyckoff
multiplicity: the number of operations for an atom in a general position, and that number divided by the order of
its site-symmetry group for an atom on a special position.

Disorder and partial occupancy. When part of a structure takes two alternative positions, each alternative is its
own disorder group with a fractional occupancy. Atoms from different disorder groups are never merged, even where
they overlap, and an occupancy below one never makes an atom disappear.

Numbers carry their uncertainty. A value followed by digits in parentheses gives the standard uncertainty in its last
digits. The value is the part before the parenthesis; the bracketed digits never enter arithmetic. Cell lengths and
angles carry them too.

Cartesian axes follow one convention. International Tables, Volume A puts a along x, b in the xy-plane and c to
complete a right-handed set: b is (b cos gamma, b sin gamma, zero), and c is (c cos beta, c (cos alpha minus cos beta
cos gamma) / sin gamma, V / (a b sin gamma)), with V the cell volume. The rows of the cell matrix are then the three
cell vectors, and Cartesian coordinates are the fractional coordinates times that matrix. A diagonal matrix of a, b
and c is right only when every angle is a right angle.

Distances need the lattice. In an oblique cell the nearest copy of a neighbour may sit in an adjacent cell, and
fractional differences mislead. Measure in Cartesian space over the neighbouring cell translations, the minimum
image, and keep the shortest.
