#!/bin/bash

# assembler.sh - Assembler for the VSC, INFO1112 A1
#
# Usage:
#   bash assembler.sh <filename.vsc>
#
# Reads a .vsc program and converts it into its binary equivalent.
# The output is written to a .bin file with the same filename.
#
# Example:
#   add.vsc -> add.bin
#
# Exit codes:
#   0 = program successfully assembled and .bin file produced
#   1 = error and no .bin file produced
#
# Two program types are accepted:
#
#   QUIT program              ADD/SUB program
#   ------------              ---------------
#   0                         2
#   QUIT,0,0                  <value 1>        0..127
#                             <value 2>        0..127
#                             <instruction>    e.g. LOAD,0,0
#                             ...
#                             QUIT,0,0
#
# Each instruction is 2 bytes:
#
#   Byte 1 = [opcode: 6 bits][register: 2 bits]
#   Byte 2 = [memory address: 8 bits]
#
# Static values use 1 byte each.
# n_values itself is NOT written into the .bin file.
#
# Overall pipeline:
#
#   validate input
#        ↓
#   read .vsc file
#        ↓
#   determine program type
#        ↓
#   validate values/instructions
#        ↓
#   convert decimal/instructions to binary
#        ↓
#   convert binary to hexadecimal
#        ↓
#   store bytes in dataArray
#        ↓
#   write bytes into .bin file



# 1. CONSTANTS AND OUTPUT STORAGE
# I defined the program limits first and created an array to store the converted bytes before writing them to the output file.

# Maximum number of instructions allowed.
MAX_INSTRUCTIONS=100

# Maximum valid instruction line length.

MAX_LINE_LENGTH=11

# This array stores all bytes that will eventually be written to the .bin file.
# Each value is stored as two hexadecimal digits, e.g. "7f".
dataArray=()


# 2. HELPER FUNCTIONS


# fail MESSAGE
# I made one error-handling function so every invalid condition prints the required message and exits consistently with status 1
# Prints an error message to STDOUT and terminates the script with exit code 1.

fail() {
    echo "$1"
    exit 1
}


# dec_to_bin NUMBER BITS
#
# Converts a decimal number into either:
#   - an 8-bit binary value
#   - a 2-bit binary value
#
# Because the assembler needs to construct binary machine-code fields,
# I created a reusable decimal-to-binary function for registers, addresses and static values
# 
# The function works by checking each binary place value from largest
# to smallest.

dec_to_bin() {

    # $1 = first argument passed to this function.
    # This is the decimal number being converted.
    local number=$1

    # Binary place values for an 8-bit number.
    local weights="128 64 32 16 8 4 2 1"

    # $2 tells us how many bits are required.
    #
    # Registers only need 2 bits because:
    #
    # 00 = register 0
    # 01 = register 1
    # 10 = register 2
    # 11 = register 3
    if (( $2 == 2 )); then
        weights="2 1"
    fi

    # Start with an empty binary string.
    local bits=""

    local weight

    # Go through each binary place value.
    for weight in $weights; do

        # If the current weight fits into the remaining decimal number,
        # place a 1 in this binary position.
        if (( number >= weight )); then

            bits="${bits}1"

            # Subtract that weight from the remaining number.
            number=$(( number - weight ))

        else

            # Otherwise this binary position is 0.
            bits="${bits}0"

        fi
    done

    # Bash functions normally return values by printing them.
    echo "$bits"
}


# bin_to_hex BITS
#
# Converts an 8-bit binary value to two hexadecimal digits.
# After generating an 8-bit binary byte, I convert it into hexadecimal 
# because that is the required output representation and makes the bytes easier to store and display.
# 
# 2#$1 means:
#   interpret $1 as a base-2 binary number.
#
# %02x means:
#   print as hexadecimal using at least two digits.


bin_to_hex() {
    printf '%02x' "$(( 2#$1 ))"
}


# is_number TEXT
# I validate numeric fields before converting them so invalid strings 
# never reach the arithmetic part of the assembler.
# 
# Checks whether a value contains only digits.
#
# =~ performs a regular-expression check.
#
# ^       = beginning of text
# [0-9]+  = one or more digits
# $       = end of text
#
# Therefore the whole value must consist only of numbers.


is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}


# opcode_of NAME
# I separated opcode lookup into its own function so the instruction name could be converted 
# into the correct 6-bit opcode in one place
#
# Converts an instruction name into its 6-bit opcode.
#
# For example:
#
#   ADD -> 000011
#
# Returns 1 if the instruction name is invalid.

opcode_of() {

    if [[ $1 == "LOAD" ]]; then
        echo "000001"

    elif [[ $1 == "STORE" ]]; then
        echo "000010"

    elif [[ $1 == "ADD" ]]; then
        echo "000011"

    elif [[ $1 == "SUB" ]]; then
        echo "000100"

    elif [[ $1 == "QUIT" ]]; then
        echo "001000"

    elif [[ $1 == "PRINT" ]]; then
        echo "001001"

    else
        return 1
    fi
}


# convert_instruction LINE LINE_NUMBER
#
# Converts one instruction such as:
#
#   LOAD,3,100
#
# into two bytes.
#
# Pipeline:
#
#   LOAD,3,100
#       ↓
#   split into:
#       instruction = LOAD
#       register    = 3
#       memory      = 100
#       ↓
#   validate each component
#       ↓
#   find opcode
#       ↓
#   opcode + register = byte 1
#       ↓
#   memory address    = byte 2
#       ↓
#   convert both to hexadecimal
#       ↓
#   append to dataArray


convert_instruction() {

    local text=$1
    local lineno=$2

    # Check instruction length.

    # ${#text} returns the number of characters in the string.
    if (( ${#text} > MAX_LINE_LENGTH )); then
        fail "error: line $lineno: '$text' is too long to be a valid instruction"
    fi


    # Split the instruction on commas.

    local ins reg mem extra

    # IFS=',' temporarily tells Bash to treat commas as separators.
    # I split each instruction around the commas so I could validate and convert 
    # the instruction, register and memory address separately
    #
    # read -r puts each section into a variable.
    #
    # Example:
    #
    # LOAD,3,100
    #
    # becomes:
    #
    # ins   = LOAD
    # reg   = 3
    # mem   = 100
    #
    # If there is a fourth part, it goes into "extra".
    IFS=',' read -r ins reg mem extra <<< "$text"


    # If "extra" contains something, there were too many comma-separated parts.
    if [[ -n $extra ]]; then
        fail "error: line $lineno: '$text' must have the form INSTRUCTION,register,memory"
    fi


    # Find instruction opcode.

    local opcode

    # I used the return status of the opcode lookup to detect 
    # unsupported instructions before attempting to assemble them.
    #
    # $(...) runs a command/function and stores what it prints.
    opcode=$(opcode_of "$ins")

    # $? stores the exit status of the previous command.
    #
    # opcode_of returns 1 when the instruction name is invalid.
    if (( $? != 0 )); then
        fail "error: line $lineno: '$ins' is not a valid instruction"
    fi

    # Validate register.

    # The register field is only two bits, so only register numbers 0–3 are valid.
    # Register must:
    #
    #   1. contain only digits
    #   2. be between 0 and 3
    #
    # || means OR.
    #
    # 10#$reg forces Bash to treat the number as decimal/base 10.
    if ! is_number "$reg" || (( 10#$reg > 3 )); then
        fail "error: line $lineno: register '$reg' must be 0, 1, 2 or 3"
    fi

    reg=$(( 10#$reg ))


    # Validate memory address.

    # Memory uses 8 bits.
    #
    # Therefore valid addresses are:
    #
    # 0 to 255
    if ! is_number "$mem" || (( 10#$mem > 255 )); then
        fail "error: line $lineno: memory address '$mem' must be in the range [0, 255]"
    fi

    mem=$(( 10#$mem ))


    # PRINT does not use a memory address.
    # Therefore its memory value must always be 0.
    # After the general validation, I added instruction-specific validation where necessary, 
    # such as requiring PRINT to use memory address 0.
    if [[ $ins == "PRINT" ]] && (( mem != 0 )); then
        fail "error: line $lineno: PRINT must use memory address 0"
    fi


    # Construct the two instruction bytes.
    # Once all three fields were valid, I combined the opcode and register 
    # into the first byte and used the memory address as the second byte.

    local byte1 byte2

    # Byte 1:
    #
    # [6-bit opcode][2-bit register]
    #
    # Example:
    #
    # ADD opcode = 000011
    # register 2 = 10
    #
    # byte1 = 00001110
    byte1="$opcode$(dec_to_bin $reg 2)"


    # Byte 2:
    #
    # [8-bit memory address]
    byte2=$(dec_to_bin $mem 8)


    # Convert each binary byte to hexadecimal and append it to dataArray.
    dataArray+=( "$(bin_to_hex $byte1)" )
    dataArray+=( "$(bin_to_hex $byte2)" )
}

# 3. VALIDATE COMMAND-LINE INPUT
#
# Validation pipeline:
#
#   argument provided?
#        ↓
#   exactly one argument?
#        ↓
#   input exists and is a file?
#        ↓
#   filename ends in .vsc?
#        ↓
#   continue


# $# contains the number of command-line arguments supplied.
#
# Example:
#
# bash assembler.sh
#
# $# = 0
if (( $# == 0 )); then
    fail "usage: no argument is provided"
fi


# The program accepts only one input file.
#
# Example:
#
# bash assembler.sh a.vsc b.vsc
#
# $# = 2
if (( $# > 1 )); then
    fail "usage: more than one arguments are provided"
fi


# $1 means the first command-line argument.
input=$1


# -f checks whether the input exists and is a regular file.
#
# ! means NOT.
if [[ ! -f $input ]]; then
    fail "usage: input is not a file or it does not exist"
fi


# *.vsc is Bash pattern matching.
#
# This makes sure the filename ends in .vsc.
if [[ $input != *.vsc ]]; then
    fail "usage: input does not have the extension .vsc"
fi


# ${input%.vsc} removes ".vsc" from the end of the filename.
# I derive the output filename automatically from the input 
# so the user doesn’t need to provide a separate output name.
# Example:
#
# add.vsc
#   ↓
# add
#   ↓
# add.bin
output="${input%.vsc}.bin"


# 4. READ THE .vsc FILE


# Create an empty array to store every line from the source file.
lines=()


# Read the source file one line at a time.
#
# IFS= prevents Bash from removing leading/trailing whitespace.
#
# read -r prevents backslashes from being treated as special characters.
#
# || [[ -n $line ]] ensures that a final line is still read even if the
# file does not end with a newline character.
while IFS= read -r line || [[ -n $line ]]; do

    # Remove \r if the file uses Windows-style line endings.
    line=${line%$'\r'}

    # Append the line to the array.
    lines+=( "$line" )

done < "$input"


# 5. CHECK WHETHER THE FILE IS EMPTY


# Assume the file has no meaningful content.
has_content=0


# "${lines[@]}" means every element in the lines array.
for line in "${lines[@]}"; do

    # [^[:space:]] means:
    #
    # any character that is NOT whitespace.
    #
    # Therefore, if we find one non-space character,
    # the file is not empty.
    if [[ $line =~ [^[:space:]] ]]; then
        has_content=1
    fi

done


if (( has_content == 0 )); then
    fail "usage: the file is empty – no .bin file is produced"
fi


# 6. DETERMINE PROGRAM TYPE


# Array indexes begin at 0.
#
# Therefore lines[0] is the first line of the .vsc file.
n_values=${lines[0]}


# The first line determines the program structure:
#
#              n_values
#                 |
#         +-------+-------+
#         |               |
#         0               2
#         |               |
#      QUIT           ADD/SUB
#      program        program


# 7A. QUIT PROGRAM


if [[ $n_values == "0" ]]; then

    # A QUIT program must have exactly:
    #
    # 0
    # QUIT,0,0

    if [[ ${lines[1]} != "QUIT,0,0" ]]; then
        fail "error: line 2: a program with 0 values must be exactly QUIT,0,0"
    fi


    echo "It is a QUIT program"


    # Convert QUIT,0,0 into its two-byte instruction.
    convert_instruction "${lines[1]}" 2

# 7B. ADD/SUB PROGRAM


elif [[ $n_values == "2" ]]; then

    # First process the two static values.
    #
    # Array index:
    #
    # lines[0] = 2
    # lines[1] = value 1
    # lines[2] = value 2
    #
    # Therefore loop over indexes 1 and 2.

    for i in 1 2; do

        value=${lines[i]}


        # Each static value must:
        #
        #   - be numeric
        #   - be between 0 and 127
        #
        # >= 128 is rejected.
        if ! is_number "$value" || (( 10#$value >= 128 )); then
            fail "error: line $(( i + 1 )): '$value' must be a whole number in the range [0, 128)"
        fi


        # Convert:
        #
        # decimal
        #    ↓
        # 8-bit binary
        #    ↓
        # hexadecimal

        bits=$(dec_to_bin $(( 10#$value )) 8)


        # Store the converted byte.
        dataArray+=( "$(bin_to_hex "$bits")" )

    done

    # Process instructions.


    # Count how many instructions have been processed.
    count=0


    # Keep track of whether the required QUIT instruction was found.
    #
    # 0 = not found
    # 1 = found
    found_quit=0


    # Start at index 3 because:
    #
    # lines[0] = n_values
    # lines[1] = value 1
    # lines[2] = value 2
    # lines[3] onwards = instructions
    #
    # ${#lines[@]} gives the number of elements in the array.
    for (( i = 3; i < ${#lines[@]}; i++ )); do

        text=${lines[i]}


        # Convert the current instruction.
        #
        # i + 1 is used because:
        #
        # array indexes start at 0
        # file line numbers start at 1
        convert_instruction "$text" $(( i + 1 ))


        # Increase the instruction count.
        count=$(( count + 1 ))

        # Detect the QUIT instruction.

        # QUIT,* uses Bash pattern matching.
        #
        # This means:
        #
        # anything beginning with "QUIT,"
        if [[ $text == QUIT,* ]]; then


            # However, the only valid form is exactly:
            #
            # QUIT,0,0
            if [[ $text != "QUIT,0,0" ]]; then
                fail "error: line $(( i + 1 )): QUIT must be written exactly as QUIT,0,0"
            fi


            # Record that the terminating instruction was found.
            found_quit=1


            # Stop reading instructions.
            #
            # Anything after QUIT is ignored.
            break

        fi


        # Stop programs that exceed the instruction limit.
        if (( count >= MAX_INSTRUCTIONS )); then
            fail "error: more than $MAX_INSTRUCTIONS instructions - the program does not fit in memory"
        fi

    done


    # If the loop ended without finding QUIT, the program is invalid.
    if (( found_quit == 0 )); then
        fail "error: the program does not end with QUIT,0,0"
    fi


    echo "It is an ADD/SUB program"


# 7C. INVALID PROGRAM TYPE


else

    # The specification only allows n_values to be 0 or 2.
    fail "error: line 1: '$n_values' is not valid - it can only be 0 or 2"

fi


# 8. WRITE THE .bin FILE
#
# This section is only reached if every previous validation test succeeded.
#
# Therefore:
#
# invalid program
#      ↓
# fail()
#      ↓
# exit 1
#
# valid program
#      ↓
# reach this section
#      ↓
# produce .bin file


# > creates the file if it does not exist.
#
# If it already exists, this clears its existing contents.
printf "" > "$output"


# Loop through every hexadecimal byte stored in dataArray.
for hex in "${dataArray[@]}"; do

    # \x tells printf that the next two characters represent a hexadecimal byte.
    #
    # Example:
    #
    # hex="7f"
    #
    # printf "\x7f"
    #
    # writes the actual byte 0x7f into the file.
    #
    # >> means append rather than overwrite.
    printf "\x$hex" >> "$output"

done


# 9. DISPLAY THE GENERATED OUTPUT


echo "The content of the .bin file is"


# Print each hexadecimal byte so the user can check the generated program.
for hex in "${dataArray[@]}"; do
    echo "$hex"
done


# 10. COMPLETION
#
# Reaching this line means:
#
#   - argument validation passed
#   - file validation passed
#   - program validation passed
#   - all values/instructions were converted
#   - the .bin file was successfully created
#
# Therefore return exit code 0.

exit 0