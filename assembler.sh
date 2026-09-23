#!/bin/bash
# =============================================================================
# assembler.sh - Assembler for the VSC (Very Simple Computer), INFO1112 A1
#
# Usage:  bash assembler.sh <filename.vsc>
#
# Reads a .vsc program and writes its binary equivalent to <filename>.bin
# (same folder, same name, .bin extension). Every message goes to STDOUT.
#
# Exit codes:  0 = .bin file produced
#              1 = error (and no .bin file is produced)
#
# Two program types are accepted (see Figure 3 of the spec + pointers):
#
#   QUIT program              ADD/SUB program
#   ------------              ---------------
#   0                         2
#   QUIT,0,0                  <value 1>        0..127
#                             <value 2>        0..127
#                             <instruction>    e.g. LOAD,0,0
#                             ...              (at most 100 instructions)
#                             QUIT,0,0         conversion stops here
#
# Each instruction is 2 bytes:  [opcode 6 bits][register 2 bits][address 8 bits]
# Static values are 1 byte each. n_values itself is NOT written to the .bin.
# =============================================================================

MAX_INSTRUCTIONS=100      # memory is limited, the whole program must fit
MAX_LINE_LENGTH=11        # longest valid line is e.g. STORE,2,228 (11 chars)

dataArray=()              # bytes of the .bin file, stored as 2-digit hex

# ------------------------------------------------------------------ helpers --

# fail MESSAGE : print MESSAGE to STDOUT and exit with 1 (nothing written).
fail() {
    echo "$1"
    exit 1
}

# dec_to_bin NUMBER BITS : print NUMBER in binary using BITS bits (8 or 2).
# Weighted sum: for each weight from the largest down, write 1 and subtract
# the weight if it fits, otherwise write 0.
#   e.g. 14 -> 00001110   (14 = 8 + 4 + 2)
dec_to_bin() {
    local number=$1
    local weights="128 64 32 16 8 4 2 1"
    if (( $2 == 2 )); then
        weights="2 1"
    fi

    local bits=""
    local weight
    for weight in $weights; do
        if (( number >= weight )); then
            bits="${bits}1"
            number=$(( number - weight ))
        else
            bits="${bits}0"
        fi
    done
    echo "$bits"
}

# bin_to_hex BITS : print an 8-bit binary string as 2 hex digits.
#   2#... means "read this as a base-2 number";  %02x prints it as hex.
#   e.g. 01111111 -> 7f
bin_to_hex() {
    printf '%02x' "$(( 2#$1 ))"
}

# is_number TEXT : true if TEXT is only digits (and not empty).
is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

# opcode_of NAME : print the 6-bit opcode for an instruction name
# (case sensitive), or return 1 if the name is not a valid instruction.
opcode_of() {
    if   [[ $1 == "LOAD"  ]]; then echo "000001"
    elif [[ $1 == "STORE" ]]; then echo "000010"
    elif [[ $1 == "ADD"   ]]; then echo "000011"
    elif [[ $1 == "SUB"   ]]; then echo "000100"
    elif [[ $1 == "QUIT"  ]]; then echo "001000"
    elif [[ $1 == "PRINT" ]]; then echo "001001"
    else return 1
    fi
}

# convert_instruction LINE LINE_NUMBER : check one instruction line and add
# its 2 bytes to dataArray. Stops the whole program if the line is invalid.
convert_instruction() {
    local text=$1
    local lineno=$2

    # Too-long lines are rejected before we even try to split them.
    if (( ${#text} > MAX_LINE_LENGTH )); then
        fail "error: line $lineno: '$text' is too long to be a valid instruction"
    fi

    # Split on commas, e.g. "LOAD,3,100" -> ins=LOAD reg=3 mem=100.
    # Anything after a third comma lands in "extra", which must be empty.
    local ins reg mem extra
    IFS=',' read -r ins reg mem extra <<< "$text"

    if [[ -n $extra ]]; then
        fail "error: line $lineno: '$text' must have the form INSTRUCTION,register,memory"
    fi

    local opcode
    opcode=$(opcode_of "$ins")
    if (( $? != 0 )); then
        fail "error: line $lineno: '$ins' is not a valid instruction"
    fi

    # Register: 0, 1, 2 or 3 - not empty, not a letter, not 4+.
    # (10#$reg reads the number as base 10, so "09" is not treated as octal.)
    if ! is_number "$reg" || (( 10#$reg > 3 )); then
        fail "error: line $lineno: register '$reg' must be 0, 1, 2 or 3"
    fi
    reg=$(( 10#$reg ))

    # Memory address: 0..255 - not empty, not a letter, not negative, not 256+.
    if ! is_number "$mem" || (( 10#$mem > 255 )); then
        fail "error: line $lineno: memory address '$mem' must be in the range [0, 255]"
    fi
    mem=$(( 10#$mem ))

    # PRINT has no memory operand (always 00000000 in Figure 2).
    if [[ $ins == "PRINT" ]] && (( mem != 0 )); then
        fail "error: line $lineno: PRINT must use memory address 0"
    fi

    # Byte 1 = opcode (6 bits) + register (2 bits);  Byte 2 = address (8 bits).
    local byte1 byte2
    byte1="$opcode$(dec_to_bin $reg 2)"
    byte2=$(dec_to_bin $mem 8)
    dataArray+=( "$(bin_to_hex $byte1)" )
    dataArray+=( "$(bin_to_hex $byte2)" )
}

if (( $# == 0 )); then
    fail "usage: no argument is provided"
fi
if (( $# > 1 )); then
    fail "usage: more than one arguments are provided"
fi

input=$1

if [[ ! -f $input ]]; then
    fail "usage: input is not a file or it does not exist"
fi
if [[ $input != *.vsc ]]; then
    fail "usage: input does not have the extension .vsc"
fi

output="${input%.vsc}.bin"          # add.vsc -> add.bin

# ---------------------------------------------------- 2. read the file ---

# Read every line into the array "lines".
# "|| [[ -n $line ]]" keeps a last line that has no newline after it
# (the supplied quit.vsc ends like that).
lines=()
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}              # remove a Windows line ending (\r)
    lines+=( "$line" )
done < "$input"

# The file counts as empty if no line has a non-space character in it.
has_content=0
for line in "${lines[@]}"; do
    if [[ $line =~ [^[:space:]] ]]; then
        has_content=1
    fi
done
if (( has_content == 0 )); then
    fail "usage: the file is empty – no .bin file is produced"
fi