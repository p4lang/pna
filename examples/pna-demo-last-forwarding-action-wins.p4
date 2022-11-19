/*
Copyright 2021 Intel Corporation

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


// Very simple PNA program intended only to demonstrate the
// mirror_packet() extern function, and to demonstrate the intended
// behavior that multiple sequential calls to one of the following
// extern functions can be made, and only the last one of the takes
// effect on the packet.

// + sent_to_port
// + drop_packet


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
    action my_drop () {
        drop_packet();
    }
    action my_send_to_port (PortId_t port_id) {
        send_to_port(port_id);
    }
    action my_mirror0 (MirrorSessionId_t mirror_session_id) {
        // "mirror" and "clone" are synonyms.  No difference is
        // implied anywhere in the PNA spec between these two terms.
        
        
        // PSA and Tofino only have one "mirror slot" in the ingress
        // control, restricted to be a "pre-modify" copy, and one in
        // the egress control, restricted to be a "post-modify" copy.
        // The proposal for PNA is to have at least four such "mirror
        // slots" for a single pass through the main control.

        // This enables multiple data plane features to make their own
        // independent decisions on whether to create a mirror packet,
        // and if so, where it will be sent.  This aids in developing
        // P4 code where the parts are more independent of each other.
        
        // The first parameter is a "mirror slot id", in the range [0,
        // 3].  Each mirror slot can be modified independently of the
        // others while processing a packet.  At the beginning of the
        // main control execution, all mirror slots are initialized
        // NOT to create a mirror for the packet.
        mirror_packet((MirrorSlotId_t) 0, mirror_session_id);
    }
    action my_mirror3 (MirrorSessionId_t mirror_session_id) {
        mirror_packet((MirrorSlotId_t) 3, mirror_session_id);
    }

    table mirror_decision_near_ports_rx {
        key = { hdr.eth.srcAddr: exact; }
        actions = { my_mirror0; NoAction; }
        default_action = NoAction;
    }
    table t1_rx {
        key = { hdr.eth.srcAddr: exact; }
        actions = { my_send_to_port; my_drop; NoAction; }
        default_action = NoAction;
    }
    table t2_rx {
        key = { hdr.eth.dstAddr: exact; }
        actions = { my_send_to_port; my_drop; NoAction; }
        default_action = NoAction;
    }
    table t3_rx {
        key = { hdr.eth.etherType: exact; }
        actions = { my_send_to_port; my_drop; NoAction; }
        default_action = NoAction;
    }
    table mirror_decision_near_host_rx {
        key = { hdr.eth.srcAddr: exact; }
        actions = { my_mirror3; NoAction; }
        default_action = NoAction;
    }
    apply {
        if (istd.direction == PNA_Direction_t.NET_TO_HOST) {
            mirror_decision_near_ports_rx.apply();
            t1_rx.apply();
            t2_rx.apply();
            t3_rx.apply();
            mirror_decision_near_host_rx.apply();
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
