# Aquilon: the appliance and Trellis side

You own `tools/restore_aquilon.py`. Your notes come from two documents: the incident report's section on the
injector's code detour and its payload header, and Trellis 4.2's documentation of the .tdu v4 unload. Your teammate
holds the rest of the incident report (how the injector rewrote the library's ELF structures) and the Rate Board's
TCANON v2 interchange specification.

A .tdu v4 unload is LF-terminated records of seven |-separated fields, PERIOD|ACCT|METER_ID|READ_ID|USAGE_KWH|RATE|NOTE,
where NOTE may itself contain |: ACCT and READ_ID are integer text, USAGE_KWH and RATE optionally signed decimal text,
METER_ID up to 20 letters, digits or hyphens, NOTE up to 120 bytes; a file may be empty. In detail:

- The injector's payload sits at the file offset of the PT_LOAD segment it added, and starts with the 8-byte tag AQLRT1 followed by two NUL bytes, then two reserved bytes. Its detour overwrote the first 12 bytes of aql_round with E9, a rel32 and seven 0x90 bytes: the u64 at payload offset 18 is the file offset of those 12 bytes, and the 12 original bytes are saved at payload offset 26. Payload integers are little-endian.
- The detour code itself starts at payload offset 106: it returns 0.0 for accounts beginning 88 whose charge exceeds 500.00. The clean library never does this.
- PERIOD is DD-MON-YY with English month abbreviations. Two-digit years pivot at 50: 00 to 49 are 2000 to 2049, and 50 to 99 are 1950 to 1999.
- A NOTE of exactly \N (a backslash and a capital N) is the NULL sentinel; it is not the same as an empty NOTE.
- Trellis right-pads every field with spaces (CHAR semantics). Trailing spaces are never data: strip them from every field before anything else, so an all-space value is empty.
- NOTE bytes are Windows-1252 (CP1252) text, not UTF-8 and not Latin-1: 0x80 is the euro sign and 0x92 a right single quotation mark.
- The runtime is 1998 C: USAGE_KWH, RATE, ACCT and READ_ID are read with strtod into IEEE-754 binary64 doubles, and a record's charge is the binary64 product USAGE_KWH * RATE. Nothing is computed in decimal.
- The runtime keeps one accumulator per period and adds each record's binary64 charge to it as the record is read, in the order the records appear in the file, before anything is sorted.
- Trellis writes the nightly unload at 01:30, and HVWA keeps 400 days of unloads on the appliance.
