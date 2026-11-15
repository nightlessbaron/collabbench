# Study definitions: the free light chain cohort

This note collects what the cohort's own documentation says about the grouping and coding columns, and the reporting
conventions this analysis uses. It is a reading aid: where a definition is the dataset's own, it is quoted; where it is
a convention of this analysis, it says so.

## 1. What the records are

`data/flchain.csv` has 7,874 rows, one per person: a stratified random half of the 15,759 subjects of a study of serum
free light chains (FLC) and mortality in Olmsted County, Minnesota, residents aged 50 or older who gave a blood sample
between 1995 and 2003 (R package `survival`, data set `flchain`, help page; Dispenzieri et al., Mayo Clin Proc 2012;
87:512-523; Kyle et al., N Engl J Med 2006; 354:1362-1369). Identifiers and dates were removed from the distributed
data.

| column | the dataset's own definition |
| --- | --- |
| `age` | "age in years" (at the blood sample) |
| `sex` | "F=female, M=male" |
| `sample_year` | "the calendar year in which a blood sample was obtained" |
| `kappa`, `lambda` | "serum free light chain", the kappa and the lambda portion |
| `flc_group` | "the FLC group for the subject, as used in the original analysis" |
| `creatinine` | "serum creatinine" (blank where not measured) |
| `mgus` | "1 if the subject had been diagnosed with monoclonal gammapothy (MGUS)" |
| `followup_days` | "days from enrollment until death", or, for a person not known to have died, until the last contact. The help page adds: "there are 3 subjects whose sample was obtained on their death date." |
| `cause_chapter` | "for those who died, a grouping of their primary cause of death by chapter headings" of the International Classification of Diseases, ninth revision (ICD-9). Blank for everyone else. |

There is no column that says whether a person died. In this file a person died if and only if `cause_chapter` is
filled.

## 2. The published FLC groups

`flc_group` is the grouping "used in the original analysis": ten groups, 1 (lowest) to 10 (highest), of the sum of the
two light chains, `kappa + lambda`. The groups were formed in the original study, which was about twice the size of this
file. In this file they are not equal in size (730 to 820 people each). Every person in a group lies between the same
two values of `kappa + lambda` as every other: the groups are consecutive ranges of the sum.

The two published decile outputs, so a reader can tell them apart:

- the **published groups** are the `flc_group` column as distributed;
- **recomputed deciles** would be formed from the 7,874 records in hand.

Which of the two this analysis reports is a decision of the study office, recorded with the other decisions.

## 3. Conventions of this analysis (not part of the dataset's documentation)

- FLC tiers group the groups: low is group 1 to 3, mid is 4 to 7, high is 8 to 10.
- Age bands, where used, are by `age` at the blood sample: 50-59, 60-69, 70-79, 80+.
- Cause of death is reported in four classes: Circulatory, Neoplasms, Respiratory, and Other (every other chapter in
  the file: Mental, Nervous, Digestive, External Causes, Endocrine, Genitourinary, Ill Defined, Infectious, Injury and
  Poisoning, Musculoskeletal, Blood, Skin, Congenital).
- A year is 365.25 days.
