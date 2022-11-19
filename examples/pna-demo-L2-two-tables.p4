/*
Copyright 2020 Intel Corporation

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


// Very simple PNA program intended only to demonstrate how to send
// unicast packets to a destination network port, or host vport, based
// upon the destination MAC address in the Ethernet header.


typedef bit<48>  EthernetAddress;

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

//////////////////////////////////////////////////////////////////////
// Struct types for holding user-defined collections of headers and
// metadata in the P4 developer's program.
//////////////////////////////////////////////////////////////////////

struct metadata_t {
}

struct headers_t {
    ethernet_t eth;
}

parser MainParserImpl(
    packet_in pkt,
    out   headers_t  hdr,
    inout metadata_t meta,
    in    pna_main_parser_input_metadata_t istd)
{
    state start {
        pkt.extract(hdr.eth);
        transition accept;
    }
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
    action L2_send_to_port (PortId_t port_id) {
        send_to_port(port_id);
    }

    // In this demo program, I have chosen to use the same action
    // names for both of the following tables.  In a similar but
    // different program, one could of course choose for these tables
    // to have different actions from each other.

    table L2_fwd_n2h {
        key = { hdr.eth.dstAddr: exact; }
        actions = { L2_send_to_port; drop; }
        default_action = drop;
    }
    table L2_fwd_h2n {
        key = { hdr.eth.dstAddr: exact; }
        actions = { L2_send_to_port; drop; }
        default_action = drop;
    }
    apply {
        // L2_fwd_n2h and L2_fwd_h2n are two distinct tables, each
        // one used only by packets in a particular direction.

        // The control plane API sees two separate tables, and can
        // add, modify, and/or delete entries in these tables
        // independently of each other.  They need not contain the
        // same keys, and if they do have a key K in common with each
        // other, they need not have the same action names or action
        // parameters.
        if (istd.direction == PNA_Direction_t.NET_TO_HOST) {
            L2_fwd_n2h.apply();
        } else {
            L2_fwd_h2n.apply();
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
