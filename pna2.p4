/* Copyright 2022-present Intel Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#ifndef __PNA2_P4__
#define __PNA2_P4__

/**
 *   P4-16 declaration of the parts of the Portable NIC Architecture
 *   that are specific to variant PNA2.
 */

#include <core.p4>
//#include <pna_common.p4>
#include "pna_common.p4"

struct pna_pre_input_metadata_t {
    PortId_t                 input_port;
    ParserError_t            parser_error;
    PNA_Direction_t          direction;
    PassNumber_t             pass;
    bool                     loopedback;
}

struct pna_pre_output_metadata_t {
    bool                     decrypt;  // TBD: or use said==0 to mean no decrypt?

    // The following things are stored internally within the decrypt
    // block, in a table indexed by said:

    // + The decryption algorithm, e.g. AES256, etc.
    // + The decryption key
    // + Any read-modify-write state in the data plane used to
    //   implement anti-replay attack detection.

    SecurityAssocId_t        said;
    bit<16>                  decrypt_start_offset;  // in bytes?

    // TBD whether it is important to explicitly pass information to a
    // decryption extern in a way visible to a P4 program about where
    // headers were parsed and found.  An alternative is to assume
    // that the architecture saves the pre parser results somewhere,
    // in a way not visible to the P4 program.
}


// BEGIN:Programmable_blocks
parser PreParserT<PH, M>(
    packet_in pkt,
    out   PH pre_hdr,
    inout M  umeta,
    in    pna_main_parser_input_metadata_t istd);

control PreControlT<PH, M>(
    in    PH pre_hdr,
    inout M  umeta,
    in    pna_pre_input_metadata_t  istd,
    inout pna_pre_output_metadata_t ostd);

parser MainParserT<MH, M>(
    packet_in pkt,
    out   MH main_hdr,
    inout M  umeta,
    in    pna_main_parser_input_metadata_t istd);

control MainControlT<MH, M>(
    inout MH main_hdr,
    inout M  umeta,
    in    pna_main_input_metadata_t  istd,
    inout pna_main_output_metadata_t ostd);

control MainDeparserT<MH, M>(
    packet_out pkt,
    in    MH main_hdr,
    in    M  umeta,
    in    pna_main_output_metadata_t ostd);

package PNA_NIC_2<PH, MH, M>(
    PreParserT<PH, M> pre_parser,
    PreControlT<PH, M> pre_control,
    MainParserT<MH, M> main_parser,
    MainControlT<MH, M> main_control,
    MainDeparserT<MH, M> main_deparser);
// END:Programmable_blocks

#endif   // __PNA2_P4__
