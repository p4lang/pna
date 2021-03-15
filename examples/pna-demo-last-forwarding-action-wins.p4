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


// Very simple PNA program intended only to work through details of
// MEV primitive actions that the P4 compiler can use to ensure that
// the last one of the following actions that is executed, in
// sequential order, takes effect on any given pakcet.

// sent_to_port
// send_to_vport
// drop

// recirculate - should this override drop, or simply delay the effect
// of drop until after the end of the next pass?  It definitely seems
// like it would be nice if it did _not_ override the effects of an
// earlier send_to_port or send_to_vport call.


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

control PreControlImpl(
    in    headers_t  hdr,
    inout metadata_t meta,
    in    pna_pre_input_metadata_t  istd,
    inout pna_pre_output_metadata_t ostd)
{
    apply {
        // No IPsec decryption for this example program, so pre
        // control does nothing.
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
    action my_send_to_vport (VportId_t vport_id) {
        send_to_vport(vport_id);
    }
    action my_mirror0 (MirrorSessionId_t mirror_session_id) {
        // "mirror" and "clone" are synonyms.  No difference is
        // implied anywhere in the PNA spec between these two terms.
        
        // PSA and Tofino only have one "mirror slot" for each pass
        // through the data plane.  The proposal for PNA is that
        // having at least four such "mirror slots" for a single pass
        // through the main control enables multiple different
        // features to make their own independent decisions on whether
        // to create a mirror packet, and if so, where it will be
        // sent.  This aids in developing P4 code where the parts are
        // more independent of each other.
        
        // The first parameter is a "mirror slot id", in the range [0,
        // 3].  Each mirror slot can be set independently from each
        // other while processing a packet.  Before a mirror() call is
        // made for a slot, the slot is initialized NOT to create a
        // mirror for the packet.
        mirror_packet((MirrorSlotId_t) 0, mirror_session_id);

        // ------------------------------------------------------------
        // The control plane code can configure the following
        // properties of each mirror session, independently of other
        // mirror sessions:
        
        // pre-modify / post-modify - If pre-modify, then the mirrored
        // packet's contents will be the same as the original packet
        // as it was when it began the execution of the main control
        // that invoked the mirror_packet() function.

        // If post-modify, then the mirrored packet's contents wil be
        // the same as the original packet, after any modifications
        // made during the execution of the main control that invoked
        // the mirror_packet() function.

        // truncate_mirror - true to limit the length of the mirrored
        // packet to the truncate_length.  false to cause the mirrored
        // packet not to be truncated (and then truncate_length is
        // ignored for this mirror session).
        
        // truncate_length - in units of bytes.  Targets may limit the
        // choices here, e.g. to a multiple of 32 bytes, or perhaps
        // even a subset of those choices.

        // pseudo-random sampling of mirroring, OR software can
        // configure a deterministic hash value from packet, and then
        // apply a mask, and if it is equal to a value.
        
        // mirror rate limiter, a token bucket policer (after
        // random/hash sampling, not before).

        // A hash value is built into hardware early (SEM?), 32-bits
        // wide.  6 bits of that are selected and are used for packet
        // reordering, an "ordering domain".  The hash input fields
        // are configurable per ptype or ptype group.

        // mirror destination - local VSI, or Ethernet port.  This
        // _is_ usable by packets in both directions, and will loop
        // back the mirror copy if necessary.

        // When mirror copy comes back, it will have some metadata
        // indicating it is mirror copy.  We should think about
        // proposing PNA way to recognize such mirror packets.
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
        actions = { my_send_to_port; my_send_to_vport; my_drop; NoAction; }
        default_action = NoAction;
    }
    table t2_rx {
        key = { hdr.eth.dstAddr: exact; }
        actions = { my_send_to_port; my_send_to_vport; my_drop; NoAction; }
        default_action = NoAction;
    }
    table t3_rx {
        key = { hdr.eth.etherType: exact; }
        actions = { my_send_to_port; my_send_to_vport; my_drop; NoAction; }
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
    PreControlImpl(),
    MainParserImpl(),
    MainControlImpl(),
    MainDeparserImpl(),
    // The last arg is optional, but leaving it here for the moment
    MainParserImpl()) main;
