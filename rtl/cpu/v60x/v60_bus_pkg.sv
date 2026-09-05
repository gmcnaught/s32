//============================================================================
//  v60_bus_pkg -- the V60's external bus vocabulary, from the databook.
//
//  Clean-room: every value here is transcribed from NEC's own documents, not
//  from the existing s32_v60_bus.sv, whose ST2-ST0 codes are this project's
//  own invention (its header says so) because the encoding table was not
//  available when it was written.  It is available now.
//
//  Source: NEC_uPD70616_V60_DataBook_1986.pdf S1, databook p.3.233.
//  Cross-checked against NEC_uPD71613_SystemBusController_V60_1986.pdf
//  Table 1, p.6.165.  See docs/v60/BUS-STATUS-ENCODING.md for the full table,
//  the two documents' disagreement on code 000, and the 71613's ST2/ST0/ST1
//  column order -- which will swap two bits of every code if transcribed left
//  to right.
//============================================================================
`ifndef V60_BUS_PKG_SV
`define V60_BUS_PKG_SV

package v60_bus_pkg;

// {MRQ, ST2, ST1, ST0}, in that bit order.
//
// MRQ is the pin level, and the pin is MRQ* -- active low -- so 0 selects the
// MEMORY address space and 1 selects I/O.  The databook's table column and the
// pin level are the same thing; no inversion is applied anywhere below.
typedef enum logic [3:0] {
    BST_MEM_RESERVED_0  = 4'b0000,  // reserved for future use          (single)
    BST_MEM_STRING      = 4'b0001,  // string mode data access          (string)
    BST_MEM_SHORT_PATH  = 4'b0010,  // short path data access           (single)
    BST_MEM_SINGLE      = 4'b0011,  // single mode data access          (single)
    BST_SYS_BASE_TABLE  = 4'b0100,  // system base table access         (single)
    BST_TRANS_TABLE     = 4'b0101,  // translation table access         (single)
    BST_DEMAND_FETCH    = 4'b0110,  // demand mode instruction fetch
    BST_PREFETCH        = 4'b0111,  // instruction prefetch
    BST_IO_RESERVED_0   = 4'b1000,  // reserved for future use          (single)
    BST_IO_STRING       = 4'b1001,  // string mode I/O access           (string)
    BST_IO_RESERVED_2   = 4'b1010,  // reserved for future use
    BST_IO_SINGLE       = 4'b1011,  // single mode I/O access           (single)
    BST_MACHINE_FAULT   = 4'b1100,  // machine fault acknowledge
    BST_HALT_ACK        = 4'b1101,  // halt acknowledge
    BST_INTERRUPT_ACK   = 4'b1110,  // interrupt acknowledge            (single)
    BST_RESERVED_F      = 4'b1111   // reserved for future use
} bus_status_e;

// MRQ is bit 3 and I/O is the 1 level, so this is the pin, not a decode.
function automatic logic bst_is_io(input bus_status_e s);
    return s[3];
endfunction

// "String mode bus accesses occur during bus cycles for variable length data
// types.  All other bus cycles are single mode." -- p.3.233
function automatic logic bst_is_string(input bus_status_e s);
    return (s == BST_MEM_STRING) || (s == BST_IO_STRING);
endfunction

// The three-TI recovery rule is scoped to I/O, and to I/O only:  "three TI
// states are inserted between any consecutive pair of I/O bus cycles"
// -- p.3.291.  A memory cycle following a memory cycle gets no recovery gap.
function automatic logic bst_needs_io_recovery(input bus_status_e s);
    return bst_is_io(s);
endfunction

// ---------------------------------------------------------------------------
// DL1-DL0, the data length / string direction code -- databook p.3.235.
// ---------------------------------------------------------------------------
// The same two pins mean different things depending on whether the cycle is a
// single-mode or a string-mode access, and which of the two it is comes from
// the bus status, not from these bits.  Decode them together or not at all.
typedef enum logic [1:0] {
    DL_BYTE     = 2'b00,   // single mode
    DL_HALFWORD = 2'b01,
    DL_WORD     = 2'b10,
    DL_RESERVED = 2'b11
} dl_single_e;

typedef enum logic [1:0] {
    DLS_INCREMENT = 2'b10,  // string mode: with FAS low, "start increment";
    DLS_DECREMENT = 2'b11   // with FAS high, "address increment/decrement"
} dl_string_e;

// ---------------------------------------------------------------------------
// UBE* + A0 byte lane decode -- databook p.3.236.
// ---------------------------------------------------------------------------
// "UBE* is an active low output and is asserted when the upper byte (D15-D8)
// of the data bus contains valid data.  UBE* is used along with A0 by decoding
// logic to select the even/odd addressed buses."
typedef enum logic [1:0] {
    LANE_HALFWORD   = 2'b00,   // {UBE*, A0}
    LANE_UPPER_BYTE = 2'b01,
    LANE_LOWER_BYTE = 2'b10,
    LANE_RESERVED   = 2'b11
} byte_lane_e;

function automatic byte_lane_e lane_of(input logic ube_n, input logic a0);
    return byte_lane_e'({ube_n, a0});
endfunction

// The seven bus states of databook S4.  A state is one clock period, measured
// rising edge to rising edge (p.3.233), so every "falling edge of Tn" in the
// specification is the MIDPOINT of one of these.
typedef enum logic [2:0] {
    T_TI = 3'd0,   // idle / recovery
    T_T1 = 3'd1,   // address and status out
    T_T2 = 3'd2,   // BMODE sampled at its midpoint
    T_T3 = 3'd3,   // READY sampled at its midpoint
    T_TW = 3'd4,   // wait; READY re-sampled at each midpoint
    T_T4 = 3'd5,   // data latched at its midpoint
    T_TH = 3'd6    // bus hold
} bus_state_e;

endpackage

`endif
