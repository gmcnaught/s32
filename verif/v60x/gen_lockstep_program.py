#!/usr/bin/env python3
"""
Random V60 programs for the lockstep bench (tb_v60_lockstep.sv), which runs the
shipping core and the clean-room core on one image and compares architectural
state after every instruction.

No reference model is involved: the pages adjudicate.  So unlike
verif/cosim/gen_diff_program.py this generator writes only the image.

Programs are ISLANDS.  Each island loads its operands from immediates, runs one
instruction under test, and stores what it produced, so a divergence inside one
island cannot leak into the next -- the bench keeps comparing after a
divergence and every island's verdict stands on its own.  The exceptions are
the flag readers (ADDC, SUBC, ROTC), which are given a CMP first so CY is
defined on both sides.

Encodings, from databook p.3.293 (formats) and p.3.294 (mod field):

  Format I    [op] [0 m d reg] [mod...]     d=1: mod is source, reg is dest
  Format III  [op|m] [mod...]               one operand
  mod byte    011 rrrrr  m=1 -> Rn          m=0 -> [Rn]
              000 rrrrr  m=0 -> disp.8[Rn]  followed by one signed byte
              1110 vvvv  -> immed.4
              1111 0100  -> immed.N, N the operand's width, little endian
              1111 0011  -> /addr, four bytes

The 111 group -- immediates and absolute -- is emitted with m=0, because the
figure prints those rows with m=0 only.  What an m=1 operand whose mod byte is
in that group means is not on the page, and the two cores read it differently
(the clean-room decodes it as if m were 0; the shipping core does not), so a
generated program does not go there.

Opcodes are the table's (tools/v60x/insn_table.py), siz = 0 byte, 1 halfword,
2 word.
"""
import sys, random, struct

M32 = 0xFFFFFFFF
SCRATCH = 0x8000          # results, 4 bytes per island
DATA    = 0x8800          # memory operands live here, R8 points at it

# opcode = pattern with siz filled in.  (prefix bits, low bit) -> op = prefix<<3 | siz<<1 | low
ALU2 = {  # two-operand, Format I: name -> (prefix5, lowbit), writes dest?, reads CY?
    'ADD':  (0b10000, 0, True,  False),
    'ADDC': (0b10010, 0, True,  True),
    'SUB':  (0b10101, 0, True,  False),
    'SUBC': (0b10111, 0, True,  True),
    'CMP':  (0b10111, 0, False, False),   # 10111{siz}0 -- same prefix as SUBC? no: see below
    'AND':  (0b10100, 0, True,  False),
    'OR':   (0b10001, 0, True,  False),
    'XOR':  (0b10110, 0, True,  False),
    'NEG':  (0b00111, 1, True,  False),
    'NOT':  (0b00111, 0, True,  False),
    'MUL':  (0b10000, 1, True,  False),
    'MULU': (0b10010, 1, True,  False),
    'DIV':  (0b10100, 1, True,  False),
    'DIVU': (0b10110, 1, True,  False),
    'SHL':  (0b10101, 1, True,  False),
    'SHA':  (0b10111, 1, True,  False),
    'ROT':  (0b10001, 1, True,  False),
    'ROTC': (0b10011, 1, True,  True),
}
# CMP is 10111{siz}0 and SUBC is 10011{siz}0 (p.3.296); fix the table above.
ALU2['SUBC'] = (0b10011, 0, True, True)
ALU2['CMP']  = (0b10111, 0, False, False)

SHIFTS = ('SHL', 'SHA', 'ROT', 'ROTC')
DIVS   = ('DIV', 'DIVU')

# fixed-width moves: opcode, src width, dst width
MOVX = {
    'MOVS.BH': (0x0A, 1, 2), 'MOVS.BW': (0x0C, 1, 4), 'MOVS.HW': (0x1C, 2, 4),
    'MOVZ.BH': (0x0B, 1, 2), 'MOVZ.BW': (0x0D, 1, 4), 'MOVZ.HW': (0x1D, 2, 4),
    'MOVT.HB': (0x19, 2, 1), 'MOVT.WB': (0x29, 4, 1), 'MOVT.WH': (0x2B, 4, 2),
}
MOV = {1: 0x09, 2: 0x1B, 4: 0x2D}          # MOV.B / .H / .W
INC, DEC, TEST = 0b11011, 0b11010, 0b11110  # Format III prefixes: 5 bits, then siz, then m


class Asm:
    def __init__(self):
        self.b = bytearray()
        self.notes = []        # (offset, text) for the listing

    def emit(self, *bs):
        self.b += bytes(bs)

    def note(self, text):
        self.notes.append((len(self.b), text))

    # -- Format I helpers -------------------------------------------------------
    def fi(self, op, reg, m, d, mod, extra=b''):
        """[op][0 m d reg][mod][extra]"""
        self.emit(op, (m << 6) | (d << 5) | reg, mod)
        self.b += extra

    def imm_to_reg(self, width, value, rn):
        """MOV.<w> #value, Rn  -- Format I, d=1, mod = immed.N"""
        packed = struct.pack('<I', value & M32)[:width]
        self.fi(MOV[width], rn, 0, 1, 0xF4, packed)

    def rr(self, op, src, dst):
        """op Rsrc, Rdst -- mod = Rsrc (011 rrrrr, m=1), reg = Rdst, d=1"""
        self.fi(op, dst, 1, 1, 0x60 | src)

    def mr(self, op, base, dst, disp=None):
        """op [Rbase] or disp.8[Rbase], Rdst  -- the mod operand is memory"""
        if disp is None:
            self.fi(op, dst, 0, 1, 0x60 | base)
        else:
            self.fi(op, dst, 0, 1, 0x00 | base, struct.pack('<b', disp))

    def rm(self, op, src, base, disp=None):
        """op Rsrc, [Rbase] or disp.8[Rbase]  -- d=0: reg is the source"""
        if disp is None:
            self.fi(op, src, 0, 0, 0x60 | base)
        else:
            self.fi(op, src, 0, 0, 0x00 | base, struct.pack('<b', disp))

    def qr(self, op, q, dst):
        """op #q, Rdst -- immediate quick (1110 vvvv), q in 0..15"""
        self.fi(op, dst, 0, 1, 0xE0 | (q & 0xF))

    def ir(self, op, width, value, dst):
        """op #value, Rdst -- immed.N of the SOURCE operand's width"""
        packed = struct.pack('<I', value & M32)[:width]
        self.fi(op, dst, 0, 1, 0xF4, packed)

    def st_abs(self, rn, addr):
        """MOV.W Rn, /addr -- Format I d=0, mod = /addr (1111 0011)"""
        self.fi(0x2D, rn, 0, 0, 0xF3, struct.pack('<I', addr))

    def f3(self, prefix, siz, m, mod, extra=b''):
        """Format III: [prefix siz m][mod]"""
        self.emit((prefix << 3) | (siz << 1) | m, mod)
        self.b += extra

    def halt(self):
        self.emit(0x00)


def op_of(name, siz):
    prefix, low, _, _ = ALU2[name]
    return (prefix << 3) | (siz << 1) | low


def gen(seed, islands=48):
    rng = random.Random(seed)
    a = Asm()
    a.note('R8 = DATA base')
    a.imm_to_reg(4, DATA, 8)
    slot = 0

    def store_result(reg):
        nonlocal slot
        a.st_abs(reg, SCRATCH + 4 * slot)
        slot += 1

    kinds = ['alu_rr'] * 6 + ['alu_imm'] * 3 + ['alu_mem'] * 3 + ['shift'] * 3 + \
            ['movx'] * 2 + ['inc_dec'] * 2 + ['test'] + ['mov_mem'] * 2 + ['neg_not']
    for n in range(islands):
        kind = rng.choice(kinds)
        siz = rng.choice([0, 1, 2])
        width = 1 << siz
        r1, r2 = rng.sample(range(0, 8), 2)
        v1, v2 = rng.randint(0, M32), rng.randint(0, M32)
        a.note('island %d: %s siz=%d' % (n, kind, siz))
        a.imm_to_reg(4, v1, r1)
        a.imm_to_reg(4, v2, r2)

        if kind in ('alu_rr', 'alu_imm', 'alu_mem'):
            name = rng.choice([k for k in ALU2 if k not in SHIFTS])
            op = op_of(name, siz)
            if name in DIVS:
                # a divisor of zero at the operand's width is the zero-divide
                # exception, which needs an SBT neither side has.  Keep the
                # low `width` bytes non-zero.
                v1 = (v1 & ~((1 << (8 * width)) - 1)) | rng.randint(1, (1 << (8 * width)) - 1)
                a.imm_to_reg(4, v1, r1)
            if ALU2[name][3]:
                a.note('  CMP first so CY is defined')
                a.rr(op_of('CMP', 2), r1, r2)
            a.note('  %s' % name)
            if kind == 'alu_rr':
                a.rr(op, r1, r2)
            elif kind == 'alu_imm':
                # the same zero-divisor rule for an immediate: quick from 1,
                # and the immediate's low byte non-zero
                if rng.random() < 0.5:
                    a.qr(op, rng.randint(1 if name in DIVS else 0, 15), r2)
                else:
                    a.ir(op, width, v1, r2)
            else:
                disp = rng.choice([None, 0, 4, 8, 0x7C])
                a.rm(MOV[4], r1, 8, disp)          # plant the source in memory
                a.mr(op, 8, r2, disp)              # then read it back through the mode
            store_result(r2)

        elif kind == 'shift':
            name = rng.choice(SHIFTS)
            op = op_of(name, siz)
            if ALU2[name][3]:
                a.rr(op_of('CMP', 2), r1, r2)
            count = rng.choice([rng.randint(0, 15), rng.randint(0, 40), -rng.randint(1, 40)])
            a.note('  %s #%d' % (name, count))
            if 0 <= count <= 15 and rng.random() < 0.7:
                a.qr(op, count, r2)
            else:
                a.ir(op, 1, count & 0xFF, r2)      # the count is a BYTE operand
            store_result(r2)

        elif kind == 'movx':
            name = rng.choice(list(MOVX))
            op, sw, dw = MOVX[name]
            a.note('  %s' % name)
            a.rr(op, r1, r2)
            store_result(r2)

        elif kind == 'inc_dec':
            prefix = rng.choice([INC, DEC])
            a.note('  %s' % ('INC' if prefix == INC else 'DEC'))
            if rng.random() < 0.5:
                a.f3(prefix, siz, 1, 0x60 | r2)
            else:
                a.rm(MOV[4], r2, 8)
                a.f3(prefix, siz, 0, 0x60 | 8)
                a.mr(MOV[4], 8, r2)
            store_result(r2)

        elif kind == 'test':
            a.note('  TEST')
            a.f3(TEST, siz, 1, 0x60 | r2)
            store_result(r2)

        elif kind == 'mov_mem':
            disp = rng.choice([None, 0, 1, 2, 3, 5, 0x40])
            a.note('  MOV to memory and back, siz=%d disp=%s' % (siz, disp))
            a.rm(MOV[width], r1, 8, disp)
            a.mr(MOV[width], 8, r2, disp)
            store_result(r2)

        elif kind == 'neg_not':
            name = rng.choice(['NEG', 'NOT'])
            a.note('  %s' % name)
            a.rr(op_of(name, siz), r1, r2)
            store_result(r2)

        # the flags, through GETPSW, so PSW survives into memory too
        a.emit(0xF7, 0x60 | 7)               # GETPSW R7: 1111011m, Format III, m=1
        store_result(7)

    a.note('HALT')
    a.halt()
    return bytes(a.b), a.notes, slot


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    out = sys.argv[2] if len(sys.argv) > 2 else 'lockstep_%d' % seed
    img, notes, slots = gen(seed)
    words = len(img) // 2 + 1
    padded = img + b'\x00' * (words * 2 - len(img))
    with open(out + '.hex', 'w') as f:
        for i in range(words):
            f.write('%04x\n' % (padded[2 * i] | (padded[2 * i + 1] << 8)))
    with open(out + '.lst', 'w') as f:
        for off, text in notes:
            f.write('%06x  %s\n' % (off, text))
    print('seed %d: %d bytes, %d result slots' % (seed, len(img), slots))


if __name__ == '__main__':
    main()
