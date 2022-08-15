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

#ifndef __PNA1_P4__
#define __PNA1_P4__

/**
 *   P4-16 declaration of the parts of the Portable NIC Architecture
 *   that are specific to variant PNA1.
 */

#include <core.p4>
//#include <pna_common.p4>
#include "pna_common.p4"


// BEGIN:Programmable_blocks
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

package PNA_NIC_1<MH, M>(
    MainParserT<MH, M> main_parser,
    MainControlT<MH, M> main_control,
    MainDeparserT<MH, M> main_deparser);
// END:Programmable_blocks

#endif   // __PNA1_P4__
