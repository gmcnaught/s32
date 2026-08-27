#!/usr/bin/env python3
"""The V60 instruction-set table: opcode -> instruction format.

Transcribed from NEC_uPD70616_V60_DataBook_1986.pdf, databook pp.3.296-3.299
(PDF pages 68-71 of the 73-page extract), the "Instruction Format" column of
the instruction-set summary.  Clean-room: this is NEC's own table, read off the
page; nothing here comes from another implementation.

WHY THIS FILE EXISTS RATHER THAN A HAND-WRITTEN CASE STATEMENT

The printed opcode is a PATTERN, not a byte.  Placeholder fields stand in for
small tables on p.3.295:

    siz  2 bits  integer data type: 00 byte, 01 halfword, 10 word, 11 RESERVED
    ext  2 bits  bit field extension: 00 signed, 01 unsigned, 10 right
                 justified, 11 RESERVED
    cccc 4 bits  condition code
    s    1 bit   floating point: 0 short real, 1 long real
    c    1 bit   character data type: 0 byte, 1 halfword
    d    1 bit   string direction: 0 increment, 1 decrement
    b    1 bit   branch displacement: 0 byte, 1 halfword
    -    1 bit   printed as a dash: not part of the opcode

One printed row is therefore a family of up to sixteen byte values, and the
reserved codes of siz and ext are excluded -- which is what lets other
instructions occupy those slots, and they do: TEST1 sits on MUL's siz=11,
SET1 on MULU's, CLR1 on SHL's, NOT1 on SHA's.

Expanding the patterns and checking for collisions is the point.  Two
instructions cannot share an encoding, so a collision is a transcription
error, and at the resolution of this scan there ARE transcription errors: see
UNRESOLVED below.

Run this file to validate the table and print the collisions.
"""

# Bits each placeholder field occupies.
FIELD_BITS = {'siz': 2, 'ext': 2, 'cccc': 4, 's': 1, 'c': 1, 'd': 1, 'b': 1,
              '-': 1}

# Values each placeholder takes.  siz and ext exclude their reserved code
# (p.3.295), which is exactly why other instructions can occupy those slots.
FIELD_VALUES = {
    'siz':  [0, 1, 2],           # 3 is reserved
    'ext':  [0, 1, 2],           # 3 is reserved
    'cccc': list(range(16)),
    's':    [0, 1],
    'c':    [0, 1],
    'd':    [0, 1],
    'b':    [0, 1],
    '-':    [0, 1],              # not part of the opcode: both values decode
}

# (mnemonic, opcode pattern, subop pattern or None, format, databook page)
#
# Patterns are written high bit first, fields in braces.  Every pattern must
# come to exactly eight bits; check_table() enforces it.
TABLE = [
    # ---- p.3.296  Data Transfer -------------------------------------------
    ('MOV.B',    '00001001',      None, 'I,II',  '3.296'),
    ('MOV.H',    '00011011',      None, 'I,II',  '3.296'),
    ('MOV.W',    '00101101',      None, 'I,II',  '3.296'),
    ('MOV.D',    '00111111',      None, 'I,II',  '3.296'),
    ('MOVS.BH',  '00001010',      None, 'I,II',  '3.296'),
    ('MOVS.BW',  '00001100',      None, 'I,II',  '3.296'),
    ('MOVS.HW',  '00011100',      None, 'I,II',  '3.296'),
    ('MOVZ.BH',  '00001011',      None, 'I,II',  '3.296'),
    ('MOVZ.BW',  '00001101',      None, 'I,II',  '3.296'),
    ('MOVZ.HW',  '00011101',      None, 'I,II',  '3.296'),
    ('MOVT.HB',  '00011001',      None, 'I,II',  '3.296'),
    ('MOVT.WB',  '00101001',      None, 'I,II',  '3.296'),
    ('MOVT.WH',  '00101011',      None, 'I,II',  '3.296'),
    ('XCH',      '01000{siz}1',   None, 'I,II',  '3.296'),
    ('MOVEA',    '01000{siz}0',   None, 'I,II',  '3.296'),
    ('RVBYT',    '00101100',      None, 'I,II',  '3.296'),
    ('RVBIT',    '00001000',      None, 'I,II',  '3.296'),

    # ---- p.3.296  Integer Arithmetic --------------------------------------
    ('ADD',      '10000{siz}0',   None, 'I,II',  '3.296'),
    ('ADDC',     '10010{siz}0',   None, 'I,II',  '3.296'),
    ('SUB',      '10101{siz}0',   None, 'I,II',  '3.296'),
    ('SUBC',     '10011{siz}0',   None, 'I,II',  '3.296'),
    ('MUL',      '10000{siz}1',   None, 'I,II',  '3.296'),
    ('MULU',     '10010{siz}1',   None, 'I,II',  '3.296'),
    ('MULX',     '10000110',      None, 'I,II',  '3.296'),
    ('MULUX',    '10010110',      None, 'I,II',  '3.296'),
    ('DIV',      '10100{siz}1',   None, 'I,II',  '3.296'),
    ('DIVU',     '10110{siz}1',   None, 'I,II',  '3.296'),
    ('DIVX',     '10100110',      None, 'I,II',  '3.296'),
    ('DIVUX',    '10110110',      None, 'I,II',  '3.296'),
    ('REM',      '01010{siz}0',   None, 'I,II',  '3.296'),
    ('REMU',     '01010{siz}1',   None, 'I,II',  '3.296'),
    ('INC',      '11011{siz}{-}', None, 'III',   '3.296'),
    ('DEC',      '11010{siz}{-}', None, 'III',   '3.296'),
    ('NEG',      '00111{siz}1',   None, 'I,II',  '3.296'),
    ('CMP',      '10111{siz}0',   None, 'I,II',  '3.296'),
    ('TEST',     '11110{siz}{-}', None, 'III',   '3.296'),

    # ---- p.3.296  Logical --------------------------------------------------
    ('AND',      '10100{siz}0',   None, 'I,II',  '3.296'),
    ('OR',       '10001{siz}0',   None, 'I,II',  '3.296'),
    ('XOR',      '10110{siz}0',   None, 'I,II',  '3.296'),
    ('NOT',      '00111{siz}0',   None, 'I,II',  '3.296'),

    # ---- p.3.297  Shift / Rotate -------------------------------------------
    ('SHA',      '10111{siz}1',   None, 'I,II',  '3.297'),   # CSV: B9 BB BD
    ('SHL',      '10101{siz}1',   None, 'I,II',  '3.297'),   # CSV: A9 AB AD
    ('ROT',      '10001{siz}1',   None, 'I,II',  '3.297'),
    ('ROTC',     '10011{siz}1',   None, 'I,II',  '3.297'),

    # ---- p.3.297  Floating Point -------------------------------------------
    ('MOVF',     '010111{s}0',    '00001000', 'II', '3.297'),
    ('ADDF',     '010111{s}0',    '00011000', 'II', '3.297'),
    ('SUBF',     '010111{s}0',    '00011001', 'II', '3.297'),
    ('MULF',     '010111{s}0',    '00011010', 'II', '3.297'),
    ('DIVF',     '010111{s}0',    '00011011', 'II', '3.297'),
    ('CMPF',     '010111{s}0',    '00000000', 'II', '3.297'),
    ('NEGF',     '010111{s}0',    '00001001', 'II', '3.297'),
    ('ABSF',     '010111{s}0',    '00001010', 'II', '3.297'),
    ('SCLF',     '010111{s}0',    '00010000', 'II', '3.297'),
    ('CVTF',     '01011111',      '00001000', 'II', '3.297'),
    ('CVT.WS',   '01011111',      '00000000', 'II', '3.297'),
    ('CVT.WL',   '01011111',      '00010001', 'II', '3.297'),
    ('CVT.SW',   '01011111',      '00000001', 'II', '3.297'),
    ('CVT.LW',   '01011111',      '00001001', 'II', '3.297'),
    ('TRAPFL',   '11001011',      None, 'V',     '3.297'),

    # ---- p.3.297  Decimal Arithmetic ---------------------------------------
    ('ADDDC',    '01011001',      '00000000', 'VIIc', '3.297'),
    ('SUBDC',    '01011001',      '00000001', 'VIIc', '3.297'),
    ('SUBRDC',   '01011001',      '00000010', 'VIIc', '3.297'),
    ('CVTD.PZ',  '01011001',      '00010000', 'VIIc', '3.297'),
    ('CVTD.ZP',  '01011001',      '00011000', 'VIIc', '3.297'),

    # ---- p.3.297  Bit Manipulation -----------------------------------------
    ('TEST1',    '10000111',      None, 'I,II',  '3.297'),
    ('SET1',     '10010111',      None, 'I,II',  '3.297'),
    ('CLR1',     '10100111',      None, 'I,II',  '3.297'),
    ('NOT1',     '10110111',      None, 'I,II',  '3.297'),

    # ---- p.3.297  Bit Field -------------------------------------------------
    ('EXTBF',    '01011101',      '000010{ext}', 'VIIb', '3.297'),
    ('INSBF',    '01011101',      '000110{ext}', 'VIIc', '3.297'),
    ('CMPBF',    '01011101',      '000000{ext}', 'VIIb', '3.297'),

    # ---- p.3.297-8  Bit String ---------------------------------------------
    ('MOVBS',    '01011011',      '0000100{d}', 'VIIb', '3.297'),
    ('NOTBS',    '01011011',      '0000101{d}', 'VIIb', '3.297'),
    ('ANDBS',    '01011011',      '0001000{d}', 'VIIb', '3.297'),
    ('ANDNBS',   '01011011',      '0001001{d}', 'VIIb', '3.297'),
    ('ORBS',     '01011011',      '0001010{d}', 'VIIb', '3.297'),
    ('ORNBS',    '01011011',      '0001011{d}', 'VIIb', '3.298'),   # UNRESOLVED
    ('XORBS',    '01011011',      '0001100{d}', 'VIIb', '3.298'),
    ('XORNBS',   '01011011',      '0001101{d}', 'VIIb', '3.298'),   # UNRESOLVED
    ('SCH0BS',   '01011011',      '0000000{d}', 'VIIb', '3.298'),
    ('SCH1BS',   '01011011',      '0000001{d}', 'VIIb', '3.298'),   # UNRESOLVED

    # ---- p.3.298  Character Manipulation -----------------------------------
    ('MOVC',     '010110{c}0',    '0000100{d}', 'VIIa', '3.298'),
    ('MOVCF',    '010110{c}0',    '0000101{d}', 'VIIa', '3.298'),
    ('MOVCS',    '010110{c}0',    '00001100',   'VIIa', '3.298'),  # PgmRef: 58-0C AND 5A-0C
    ('CMPC',     '010110{c}0',    '00000000',   'VIIa', '3.298'),
    ('CMPCF',    '010110{c}0',    '00000001',   'VIIa', '3.298'),
    ('CMPCS',    '010110{c}0',    '00000010',   'VIIa', '3.298'),
    ('SCHC',     '010110{c}0',    '0001100{d}', 'VIIb', '3.298'),
    ('SKPC',     '010110{c}0',    '0001101{d}', 'VIIb', '3.298'),

    # ---- p.3.298  Stack Manipulation ---------------------------------------
    ('PUSH',     '1110111{-}',    None, 'II',    '3.298'),
    ('POP',      '1110011{-}',    None, 'II',    '3.298'),
    ('PUSHM',    '1110110{-}',    None, 'II',    '3.298'),
    ('POPM',     '1110010{-}',    None, 'II',    '3.298'),
    ('PREPARE',  '1101111{-}',    None, 'II',    '3.298'),
    ('DISPOSE',  '11001100',      None, 'V',     '3.298'),

    # ---- p.3.298  Control Transfer -----------------------------------------
    ('Bcc',      '011{b}{cccc}',  None, 'IV',    '3.298'),
    ('DBcc',     '1100011{-}',    None, 'VI',    '3.298'),   # low bit is c0
    ('TB',       '11000111',      None, 'VI',    '3.298'),
    ('JMP',      '1101011{-}',    None, 'III',   '3.298'),
    ('BSR',      '01001000',      None, 'IV',    '3.298'),
    ('JSR',      '1110100{-}',    None, 'III',   '3.298'),   # UNRESOLVED
    ('RSR',      '11001010',      None, 'V',     '3.298'),
    ('CALL',     '01001001',      None, 'II',    '3.298'),
    ('RET',      '1110001{-}',    None, 'III',   '3.298'),
    ('BRK',      '11001000',      None, 'V',     '3.298'),
    ('BRKV',     '11001001',      None, 'V',     '3.298'),
    ('TRAP',     '1111100{-}',    None, 'III',   '3.298'),   # PgmRef S7: F8/9
    ('RETIU',    '1110101{-}',    None, 'III',   '3.298'),

    # ---- p.3.298-9  Miscellaneous -------------------------------------------
    ('NOP',      '11001101',      None, 'V',     '3.298'),
    ('GETPSW',   '1111011{-}',    None, 'III',   '3.298'),
    ('UPDPSW.H', '01001010',      None, 'I,II',  '3.298'),
    ('CHLVL',    '01001011',      None, 'I,II',  '3.298'),
    ('CHKAR',    '01001101',      None, 'I,II',  '3.298'),
    ('CHKAW',    '01001110',      None, 'I,II',  '3.299'),
    ('CHKAE',    '01001111',      None, 'I,II',  '3.299'),
    ('TASI',     '1110000{-}',    None, 'III',   '3.299'),
    ('CAXI',     '01001100',      None, 'I',     '3.299'),
    ('SETF',     '01000111',      None, 'I,II',  '3.299'),

    # ---- p.3.299  Privileged -------------------------------------------------
    ('LDPR',     '00010010',      None, 'I,II',  '3.299'),
    ('STPR',     '00000010',      None, 'I,II',  '3.299'),
    ('CLRTLB',   '1111111{-}',    None, 'III',   '3.299'),
    ('CLRTLBA',  '00010000',      None, 'V',     '3.299'),
    ('GETATE',   '00000101',      None, 'I,II',  '3.299'),
    ('UPDATE',   '00010101',      None, 'I,II',  '3.299'),
    ('GETPTE',   '00000100',      None, 'I,II',  '3.299'),
    ('UPDPTE',   '00010100',      None, 'I,II',  '3.299'),
    ('GETRA',    '00000011',      None, 'I,II',  '3.299'),
    ('IN',       '00100{siz}0',   None, 'I,II',  '3.299'),
    ('OUT',      '00100{siz}1',   None, 'I,II',  '3.299'),
    ('LDTASK',   '00000001',      None, 'I,II',  '3.299'),
    ('STTASK',   '1111110{-}',    None, 'III',   '3.299'),
    ('RETIS',    '1111101{-}',    None, 'III',   '3.299'),
    ('UPDPSW.W', '00010011',      None, 'I,II',  '3.299'),
    ('HALT',     '00000000',      None, 'V',     '3.299'),
]

# Rows whose SUBOP could not be read reliably off the scan and were resolved by
# the collision check plus the group's own numbering, not by reading.  See
# docs/v60/INSTRUCTION-FORMATS.md.  Their FORMAT is not in doubt -- the format
# column is a word, not a bit string -- and the format is all the RTL uses.
UNRESOLVED_SUBOP = {'ORNBS', 'XORNBS', 'SCH1BS'}

# Encodings two instructions legitimately share, with what tells them apart.
# The FORMAT is the same for both members of each pair, so op_format() is
# unambiguous either way -- which is the only thing the RTL asks this table.
SHARED_ENCODINGS = {
    ('DBcc', 'TB'): 'C7: both Format VI, told apart by the subop field in the '
                    'base word -- TB is subop 101 (Programmer\'s Reference: '
                    '"Opcode C7-5"), DBcc carries c3c2c1 there',
}

# Where the two NEC documents disagree.  Neither is "fixed" against the other;
# both readings are first hand.  In each case the FORMAT is the same on both
# readings, so nothing the RTL uses depends on the resolution.
DISAGREEMENTS = {
    'IN':  'databook p.3.299 prints 00100.siz.0 (20 22 24); the Programmer\'s '
           'Reference S7 page for IN prints "Opcode 21 23 25".  OUT takes the '
           'other half of the pair either way, and both are Format I,II.',
    'OUT': 'the other half of the IN disagreement, above.',
    'MOVCS': 'the databook prints only the c=0 form (58); the Programmer\'s '
             'Reference gives 58-0C and 5A-0C, so the c bit is live.  Taken '
             'from the Reference.',
    'TRAP': 'the databook table prints 1110100- for TRAP, which is JSR\'s '
            'encoding on the same page; the Programmer\'s Reference S7 page '
            'prints "Opcode F8/9".  Taken from the Reference.',
}


# ---------------------------------------------------------------------------
# The operand data type, per operand.
# ---------------------------------------------------------------------------
# What an operand's WIDTH is, which fixes an immediate's length (p.3.294 -- one
# mode code, three rows), the scaled index constant and the [Rn+] / [-Rn] step
# (p.3.257, p.3.261), and how many bus cycles the access takes.
#
# Four kinds of answer, and only the first three are on a page:
#
#   'siz'  the opcode carries the integer data type field: 00 byte, 01
#          halfword, 10 word, 11 reserved (p.3.295).
#   's'    the opcode carries the floating point selector: 0 short real
#          (4 bytes), 1 long real (8) (p.3.295).
#   'c'    the opcode carries the character selector: 0 byte, 1 halfword
#          (p.3.295).
#   an int the width is fixed, and the mnemonic says it: MOV.B is a byte,
#          MOVS.BH is a byte source and a halfword destination -- the suffix IS
#          the data type, which is why these need no field in the opcode.
#   None   the operand is not a datum of a width: a branch displacement, a
#          register number, or an instruction with no operands at all.
#   '?'    NOT DETERMINED HERE.  The instruction has a data operand whose width
#          this table does not carry -- it is in the Programmer's Reference's
#          per-instruction syntax and has not been transcribed.  v60_idu falls
#          back to four bytes for these and says so; see
#          docs/v60/INSTRUCTION-DECODE.md.
#
# This is the data type's UNIT SIZE, which is not the same thing as a variable
# length operand's LENGTH.  p.3.261 lists the unit size for all eleven data
# types -- it is the constant [Rn+] steps by and a scaled index is multiplied
# by -- and every value here is one of the four it uses: byte character 1,
# packed decimal 1, halfword character 2, unpacked decimal 2, bit 4, bit field
# 4, bit string 4, word 4, doubleword 8.  The LENGTH of a character string or
# bit field is what the extension field carries (p.3.293), it reaches the
# sequencer as v60_idu's opN_ext, and it is not this.
#
# Keyed by mnemonic, as (operand 1, operand 2).  An address-typed operand is 4
# because a V60 address is 32 bits (Programmer's Reference S3), not because
# anything was assumed about it.
DATA_TYPE = {
    # Data transfer: the suffix is the data type.
    'MOV.B': (1, 1), 'MOV.H': (2, 2), 'MOV.W': (4, 4), 'MOV.D': (8, 8),
    'MOVS.BH': (1, 2), 'MOVS.BW': (1, 4), 'MOVS.HW': (2, 4),
    'MOVZ.BH': (1, 2), 'MOVZ.BW': (1, 4), 'MOVZ.HW': (2, 4),
    'MOVT.HB': (2, 1), 'MOVT.WB': (4, 1), 'MOVT.WH': (4, 2),
    'XCH': ('siz', 'siz'),
    'MOVEA': (4, 4),          # an effective address, and a place to put it
    'RVBYT': (4, 4), 'RVBIT': (4, 4),

    # Integer arithmetic and logic: the siz field.
    'ADD': ('siz', 'siz'), 'ADDC': ('siz', 'siz'),
    'SUB': ('siz', 'siz'), 'SUBC': ('siz', 'siz'),
    'MUL': ('siz', 'siz'), 'MULU': ('siz', 'siz'),
    'MULX': (4, 8), 'MULUX': (4, 8),      # word by word into a doubleword
    'DIV': ('siz', 'siz'), 'DIVU': ('siz', 'siz'),
    'DIVX': (4, 8), 'DIVUX': (4, 8),
    'REM': ('siz', 'siz'), 'REMU': ('siz', 'siz'),
    'INC': ('siz', None), 'DEC': ('siz', None),
    'NEG': ('siz', 'siz'), 'CMP': ('siz', 'siz'), 'TEST': ('siz', None),
    'AND': ('siz', 'siz'), 'OR': ('siz', 'siz'),
    'XOR': ('siz', 'siz'), 'NOT': ('siz', 'siz'),

    # Shift and rotate: the count is a byte, the datum takes the siz field.
    'SHA': ('siz', 1), 'SHL': ('siz', 1), 'ROT': ('siz', 1), 'ROTC': ('siz', 1),

    # Floating point: the s bit.
    'MOVF': ('s', 's'), 'ADDF': ('s', 's'), 'SUBF': ('s', 's'),
    'MULF': ('s', 's'), 'DIVF': ('s', 's'), 'CMPF': ('s', 's'),
    'NEGF': ('s', 's'), 'ABSF': ('s', 's'), 'SCLF': (4, 's'),
    'CVTF': ('?', '?'),       # converts between the two reals; which way is
                              # in the Reference, not in the opcode
    'CVT.WS': (4, 4), 'CVT.WL': (4, 8), 'CVT.SW': (4, 4), 'CVT.LW': (8, 4),
    'TRAPFL': (None, None),

    # Decimal and the variable-length formats: the extension field.
    # Decimal: packed decimal is 1 and unpacked is 2 (p.3.261), and the CVTD
    # pair converts between them in the direction its mnemonic gives.
    'ADDDC': (1, 1), 'SUBDC': (1, 1), 'SUBRDC': (1, 1),
    'CVTD.PZ': (1, 2), 'CVTD.ZP': (2, 1),
    # Bit field and bit string are both 4 (p.3.261); their LENGTH is the
    # extension field's, not this.
    'EXTBF': (4, 4), 'INSBF': (4, 4), 'CMPBF': (4, 4),
    'MOVBS': (4, 4), 'NOTBS': (4, 4),
    'ANDBS': (4, 4), 'ANDNBS': (4, 4),
    'ORBS': (4, 4), 'ORNBS': (4, 4),
    'XORBS': (4, 4), 'XORNBS': (4, 4),
    'SCH0BS': (4, 4), 'SCH1BS': (4, 4),
    'MOVC': ('c', 'c'), 'MOVCF': ('c', 'c'), 'MOVCS': ('c', 'c'),
    'CMPC': ('c', 'c'), 'CMPCF': ('c', 'c'), 'CMPCS': ('c', 'c'),
    'SCHC': ('c', 'c'), 'SKPC': ('c', 'c'),

    # Bit manipulation: a bit is named by a byte base and an offset, both words
    # on this machine (p.3.261 gives the bit data type a scaling constant of 4).
    'TEST1': (4, 4), 'SET1': (4, 4), 'CLR1': (4, 4), 'NOT1': (4, 4),

    # Stack: the V60 stack moves words.
    'PUSH': (4, None), 'POP': (4, None),
    'PUSHM': (4, None), 'POPM': (4, None),
    'PREPARE': (4, None), 'DISPOSE': (None, None),

    # Control transfer: displacements and addresses, not data.
    'Bcc': (None, None), 'DBcc': (None, None), 'TB': (None, None),
    'JMP': (4, None), 'BSR': (None, None), 'JSR': (4, None),
    'RSR': (None, None), 'CALL': (4, None), 'RET': (4, None),
    'BRK': (None, None), 'BRKV': (None, None),
    'TRAP': (1, None), 'RETIU': (4, None), 'RETIS': (4, None),

    # Miscellaneous and privileged.
    'NOP': (None, None), 'GETPSW': (4, None),
    'UPDPSW.H': (2, 2), 'UPDPSW.W': (4, 4),
    'CHLVL': (1, 4), 'CHKAR': (4, 1), 'CHKAW': (4, 1), 'CHKAE': (4, 1),
    'TASI': (1, None), 'CAXI': (4, 4), 'SETF': (1, 1),
    'LDPR': (4, 4), 'STPR': (4, 4),
    'CLRTLB': (4, None), 'CLRTLBA': (None, None),
    'GETATE': (4, 4), 'UPDATE': (4, 4), 'GETPTE': (4, 4), 'UPDPTE': (4, 4),
    'GETRA': (4, 4),
    'IN': ('siz', 'siz'), 'OUT': ('siz', 'siz'),
    'LDTASK': (4, None), 'STTASK': (4, None),
    'HALT': (None, None),
}


def _split(pattern):
    """['0','1','{siz}',...] -- one entry per printed position."""
    out, i = [], 0
    while i < len(pattern):
        if pattern[i] == '{':
            j = pattern.index('}', i)
            out.append(pattern[i + 1:j])
            i = j + 1
        else:
            out.append(pattern[i])
            i += 1
    return out


def pattern_bits(pattern):
    return sum(1 if p in '01' else FIELD_BITS[p] for p in _split(pattern))


def expand(pattern):
    """Every byte value a printed pattern stands for."""
    vals = [0]
    for p in _split(pattern):
        if p in '01':
            vals = [(v << 1) | int(p) for v in vals]
        else:
            n = FIELD_BITS[p]
            vals = [(v << n) | f for v in vals for f in FIELD_VALUES[p]]
    return vals


# The four unit sizes p.3.261 uses, plus the three fields that carry one, plus
# the two ways of having none.  Three is not among them, which is the cell that
# table gets wrong for Word -- see docs/v60/DATA-ACCESS-SPLIT.md.
VALID_DTYPE = (1, 2, 4, 8, 'siz', 's', 'c', '?', None)

# Where each placeholder sits in the byte, checked below rather than assumed.
DTYPE_FIELD_BIT = {'siz': 1, 's': 1, 'c': 1}


def check_table():
    """Returns (errors, collisions).  Both empty means the table is consistent."""
    errors, seen, collisions = [], {}, []

    # The data type has to agree with the encoding: a row typed 'siz' must
    # carry a siz field, an 'ext' row must be a format that HAS an extension
    # field, and each placeholder must sit where the generator expects it.
    for mnemonic, op, subop, fmt, page in TABLE:
        w1, w2 = DATA_TYPE[mnemonic]
        for w in (w1, w2):
            if w not in VALID_DTYPE:
                errors.append('%s: %r is not a data type' % (mnemonic, w))
                continue
            if w in DTYPE_FIELD_BIT:
                fields = _split(op)
                if w not in fields:
                    errors.append('%s: typed %r but its opcode has no %s field'
                                  % (mnemonic, w, w))
                else:
                    # position, counting from bit 7 downwards
                    bit = 8
                    for f in fields:
                        bit -= 1 if f in '01' else FIELD_BITS[f]
                        if f == w:
                            break
                    if bit != DTYPE_FIELD_BIT[w]:
                        errors.append('%s: its %s field is at bit %d, not %d'
                                      % (mnemonic, w, bit, DTYPE_FIELD_BIT[w]))


    for mnemonic, op, subop, fmt, page in TABLE:
        if pattern_bits(op) != 8:
            errors.append('%s: opcode pattern is %d bits, not 8'
                          % (mnemonic, pattern_bits(op)))
        if subop is not None and pattern_bits(subop) != 8:
            errors.append('%s: subop pattern is %d bits, not 8'
                          % (mnemonic, pattern_bits(subop)))
        if fmt not in ('I', 'II', 'I,II', 'III', 'IV', 'V', 'VI',
                       'VIIa', 'VIIb', 'VIIc'):
            errors.append('%s: %r is not a format' % (mnemonic, fmt))

        for b in expand(op):
            subs = expand(subop) if subop is not None else [None]
            for s in subs:
                key = (b, s)
                if key in seen and seen[key] != mnemonic:
                    pair = tuple(sorted((seen[key], mnemonic)))
                    known = any(tuple(sorted(k)) == pair
                                for k in SHARED_ENCODINGS)
                    if not known:
                        collisions.append((key, seen[key], mnemonic))
                seen[key] = mnemonic

    return errors, collisions


def cross_check(csv_path):
    """Check the table against docs/v60/v60_operand_access.csv.

    That file's `opcodes` column comes from the Programmer's Reference and was
    compiled in a separate pass, so it is a genuine second source for the rows
    it covers -- it is blank for many mnemonics and carries no format, so it
    can confirm a transcription but not supply one.
    """
    import csv as _csv
    import os
    if not os.path.exists(csv_path):
        return ['(no CSV at %s -- cross-check skipped)' % csv_path], 0

    want = {}
    for row in _csv.DictReader(open(csv_path)):
        ops = row['opcodes'].strip()
        if not ops:
            continue
        want.setdefault(row['mnemonic'].upper(), set()).update(ops.split())

    problems, checked = [], 0
    for mnemonic, op, subop, fmt, page in TABLE:
        key = mnemonic.upper()
        if key not in want:
            continue
        checked += 1
        mine = set()
        for b in expand(op):
            if subop is None:
                mine.add('%02X' % b)
            else:
                for s in expand(subop):
                    mine.add('%02X-%02X' % (b, s))
        theirs = {o.upper() for o in want[key]}
        if not (theirs & mine):
            if mnemonic in DISAGREEMENTS:
                problems.append('KNOWN  %s: %s' % (mnemonic, DISAGREEMENTS[mnemonic]))
            else:
                problems.append('%s: reference has %s, table gives %s'
                                % (mnemonic, sorted(theirs), sorted(mine)))
    return problems, checked


def main():
    errors, collisions = check_table()
    for e in errors:
        print('ERROR   ', e)
    for (b, s), a, c in collisions:
        print('COLLIDE  %02X%s  %s vs %s'
              % (b, '' if s is None else '-%02X' % s, a, c))
    problems, checked = cross_check('docs/v60/v60_operand_access.csv')
    for pr in problems:
        print('CROSSCHK', pr)
    print('%d rows, %d encodings, %d errors, %d collisions, %d cross-checked'
          % (len(TABLE), len(set((b, s) for m, o, so, f, p in TABLE
                                 for b in expand(o)
                                 for s in (expand(so) if so else [None]))),
             len(errors), len(collisions), checked))
    hard = [x for x in problems
            if not x.startswith('(') and not x.startswith('KNOWN')]
    return 1 if (errors or collisions or hard) else 0


if __name__ == '__main__':
    raise SystemExit(main())
