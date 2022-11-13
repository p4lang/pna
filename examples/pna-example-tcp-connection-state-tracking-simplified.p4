Copyright 2022 AMD
/*

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

#include <core.p4>
#include "../pna.p4"


// Sample PNA program demonstrating the use of write back table
// entries. Although a possible syntax is proposed to indicate
// action data that is written back to a table, the purpose of
// this example is not to support that specific syntax, but
// rather the usefulness and advantages of being able to write
// action data back to a table to store state information

// NOTE: this example uses a simplified version of the code in
// pna-example-tcp-connection-tracking.p4 to add entries
// in the TCP connection table (ct_tcp_table).
// Although the same naming is purposedly used for the connection
// table, the removal of entries (due to time out or explicit connection
// tear-down is explicitly not supported for the sake of keeping the code
// simpler and more legible.
// A complete implementation of TCP connection and status tracking
// would require to include such functionalities that can be found in
//  pna-example-tcp-connection-tracking.p4


// NOTE: the code is currently written for a compiler supporting
// if statements within actions. The same functionality could be rewritten
// for a compiler not supporting if statements within actions by using if
// if statements in the control block and a table to set up proper context.


header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLength;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<4>  res;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

// Masks of the bit positions of some bit flags within the TCP flags
// field.
const bit<8> TCP_ACK_MASK = 0x10;
const bit<8> TCP_SYN_MASK = 0x02;

// Define names for different expire time profile id values.

const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_TCP_NOW    = (ExpireTimeProfileId_t) 0;
const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_TCP_NEW    = (ExpireTimeProfileId_t) 1;
const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_TCP_ESTABLISHED = (ExpireTimeProfileId_t) 2;
const ExpireTimeProfileId_t EXPIRE_TIME_PROFILE_TCP_NEVER  = (ExpireTimeProfileId_t) 3;

//////////////////////////////////////////////////////////////////////
// Struct types for holding user-defined collections of headers and
// metadata in the P4 developer's program.
//////////////////////////////////////////////////////////////////////

struct metadata_t {
}

struct headers_t {
    ethernet_t eth;
    ipv4_t     ipv4;
    tcp_t      tcp;
}

parser MainParserImpl(
    packet_in pkt,
    out   headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_parser_input_metadata_t istd)
{
    state start {
        pkt.extract(hdr.eth);
        transition select (hdr.eth.etherType) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select (hdr.ipv4.protocol) {
            6: parse_tcp;
            default: accept;
        }
    }
    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }
}

struct ct_tcp_table_hit_params_t {
    bit<32> n2h_seqNo;
    bit<32> h2n_seqNo;
    bit<32> n2h_ackNo;
    bit<32> h2n_ackNo;
    // other connection state being tracked can be added here
}

control MainControlImpl(
    inout headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_input_metadata_t  istd,
    inout pna_main_output_metadata_t ostd)
{
    action drop () {
        drop_packet();
    }

    // Inputs from previous tables (or actions, or in general other P4
    // code) that can modify the behavior of actions of ct_tcp_table.
    bool do_add_on_miss;
    bool update_aging_info;
    bool update_expire_time;
    ExpireTimeProfileId_t new_expire_time_profile_id;

    // Outputs from actions of ct_tcp_table
    AddEntryErrorStatus_t add_status;


    action ct_tcp_table_hit (
        inout bit<32> n2h_seqNo; // NEW: support for write back entry
        inout bit<32> h2n_seqNo; // NEW: support for write back entry
        inout bit<32> n2h_ackNo; // NEW: support for write back entry
        inout bit<32> h2n_ackNo; // NEW: support for write back entry
        // More action data that is not written back can be here as well
        ) {
        // some table types, e.g., T-CAM-based ones, may not support re-writable
        // entries.
        if ((hdr.tcp.flags & TCP_SYN_MASK) != 0) {
          // the code for handling SYN messages for sessions already in the TCP
          // session table goes here
        } else {
            if (hdr.tcp.ackNo<=SelectByDirection(istd.direction,h2n_seqNo,n2h_seqNo) &
                hdr.tcp.ackNo>=SelectByDirection(istd.direction,n2h_ackNo,h2n_ackNo)) {
                if (istd.direction==PNA_Direction_t.NET_TO_HOST) {
                    n2h_seqNo=hdr.tcp.seqNo; // NEW: support for write back entry
                    n2h_ackNo=hdr.tcp.ackNo; // NEW: support for write back entry
                } else {
                    h2n_seqNo=hdr.tcp.seqNo; // NEW: support for write back entry
                    h2n_ackNo=hdr.tcp.ackNo; // NEW: support for write back entry
                }
                set_entry_expire_time(EXPIRE_TIME_PROFILE_TCP_ESTABLISHED;
              } else
                  drop_packet();
        }
    }

    action ct_tcp_table_miss() {
      // the code for creating entries in the TCP
      // session table goes here
    }

    table ct_tcp_table {
        /* add_on_miss table is restricted to have all exact match fields */
        key = {
            // other key fields also possible, e.g. VRF
            SelectByDirection(istd.direction, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr):
                exact @name("ipv4_addr_0");
            SelectByDirection(istd.direction, hdr.ipv4.dstAddr, hdr.ipv4.srcAddr):
                exact @name("ipv4_addr_1");
            hdr.ipv4.protocol : exact;
            SelectByDirection(istd.direction, hdr.tcp.srcPort, hdr.tcp.dstPort):
                exact @name("tcp_port_0");
            SelectByDirection(istd.direction, hdr.tcp.dstPort, hdr.tcp.srcPort):
                exact @name("tcp_port_1");
        }
        actions = {
            @tableonly   ct_tcp_table_hit;
            @defaultonly ct_tcp_table_miss;
        }

        add_on_miss = true;

        default_idle_timeout_for_data_plane_added_entries = 1;

        idle_timeout_with_auto_delete = true;
        const default_action = ct_tcp_table_miss;
    }

    apply {
        // ct_tcp_table is a bidirectional table
        if (hdr.ipv4.isValid() && hdr.tcp.isValid()) {
            ct_tcp_table.apply();
        }
    }
}

control MainDeparserImpl(
    packet_out pkt,
    in    headers_t hdr,
    in    metadata_t meta,
    in    pna_main_output_metadata_t ostd)
{
    apply {
        pkt.emit(hdr.eth);
    }
}

PNA_NIC(
    MainParserImpl(),
    MainControlImpl(),
    MainDeparserImpl()
    ) main;
