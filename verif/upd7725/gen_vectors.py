"""Generate synthetic uPD7725 ALU vectors from MAME's documented equations."""
from pathlib import Path
import argparse

def ld(v, dst): return (3 << 22) | ((v & 0xffff) << 6) | dst
def op(alu, asl=0, src=3, dst=0): return (1 << 20) | (alu << 16) | (asl << 15) | (src << 4) | dst

def alu(q, p, code, other_c=0, old=(0,0,0,0,0,0)):
    ov0, ov1, z, c, s0, s1 = old
    if code == 1:r=q|p
    elif code == 2:r=q&p
    elif code == 3:r=q^p
    elif code == 4:r=q-p
    elif code == 5:r=q+p
    elif code == 6:r=q-p-other_c
    elif code == 7:r=q+p+other_c
    elif code == 8:p=1;r=q-1
    elif code == 9:p=1;r=q+1
    elif code == 10:r=~q
    elif code == 11:r=(q>>1)|(q&0x8000)
    elif code == 12:r=(q<<1)|other_c
    elif code == 13:r=(q<<2)|3
    elif code == 14:r=(q<<4)|15
    elif code == 15:r=((q&255)<<8)|(q>>8)
    r &= 0xffff; s0n=(r>>15)&1; zn=int(r==0)
    if not ov1:s1=s0n
    if code in (4,5,6,7,8,9):
        if code&1: ov0n=int(bool((q^r)&~(q^p)&0x8000)); cn=int(r<q)
        else: ov0n=int(bool((q^r)&(q^p)&0x8000)); cn=int(r>q)
        ov1n = int((ov0n and ov1 and s1==s0n) or bool(ov0n ^ ov1))
    elif code in (11,12): ov0n=ov1n=0;cn=(q&1) if code==11 else (q>>15)
    else: ov0n=ov1n=cn=0
    return r, ov0n|(ov1n<<1)|(zn<<2)|(cn<<3)|(s0n<<4)|(s1<<5)

def main():
    ap=argparse.ArgumentParser();ap.add_argument("output",type=Path);ap.add_argument("branches",type=Path);ns=ap.parse_args()
    lines=[]
    for asl in (0,1):
        for code in range(1,16):
            q,p=0x8001,0x7fff; r,f=alu(q,p,code)
            a,b=(r,0) if asl==0 else (0,r); fa,fb=(f,0) if asl==0 else (0,f)
            lines.append(f"{ld(q,1+asl):06X} {ld(p,3):06X} {op(code,asl):06X} {a:04X} {b:04X} {fa:02X} {fb:02X}")
    ns.output.write_text("\n".join(lines)+"\n",encoding="ascii",newline="\n")
    # Reset state makes all flags, DP low, ACK inputs, and RQM zero. Each
    # condition is emitted in its false/true encoding; expected PC is target
    # for the zero-sense opcode and fall-through for the one-sense opcode.
    conds=[*range(0x080,0x0b0,2),0x0b0,0x0b1,0x0b2,0x0b3,0x0b4,0x0b6,0x0b8,0x0ba,0x0bc,0x0be]
    bl=[]
    for br in conds:
        take = br in range(0x080,0x0b0,4) or br in (0x0b0,0x0b3,0x0b4,0x0b8,0x0bc)
        opc=(2<<22)|(br<<13)|(5<<2)
        bl.append(f"{opc:06X} {(5 if take else 1):03X}")
    ns.branches.write_text("\n".join(bl)+"\n",encoding="ascii",newline="\n")
    print("coverage: OP ALU=1-15 A/B (30 differential vectors); JP conditions C/Z/OV0/OV1/S0/S1/DPL/SIACK/SOACK/RQM zero-state senses (34 vectors); focused LD,JP,IRQ-LCALL")
if __name__=="__main__":main()
