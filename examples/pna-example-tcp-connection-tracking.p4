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


// Very simple PNA program intended only to demonstrate how to send
// unicast packets to a destination network port, or host vport, based
// upon the destination MAC address in the Ethernet header.


typedef bit<48>  EthernetAddress;
typedef bit<32>  IPv4Address;

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
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
    IPv4Address srcAddr;
    IPv4Address dstAddr;
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

struct ct_tcp_table_hit_params_t {
    FlowId_t flow_id;
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
    bool update_expire_time;
    ExpireTimeProfileId_t new_expire_time;

    // Outputs from actions of ct_tcp_table
    FlowId_t my_flow_id;
    bool add_succeeded;
    
    
    action ct_tcp_table_hit (FlowId_t flow_id) {
        my_flow_id = flow_id;
        if (update_expire_time) {
            // This would be useful for seeing first non-SYN packet, to
            // have different entry expire time for connections still in
            // three-way-handshake, vs. established connections.
            set_entry_expire_time(new_expire_time);
            restart_expire_timer();
        } else {
            // TBD whether this case is useful for TCP connection tracking
            restart_expire_timer();
    }
        // a target might also support additional statements here
    }

    action ct_tcp_table_miss() {
        if (do_add_on_miss) {
            my_flow_id = allocate_flow_id();
            add_succeeded =
                add_entry(action_name = "ct_tcp_table_hit",  // name of action
                          action_params = (ct_tcp_table_hit_params_t)
                                          {flow_id = my_flow_id});
        }
        // a target might also support additional statements here, e.g.
        // mirror the packet
        // update a counter
        // set receive queue
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
        // New PNA table property 'add_on_miss = true' indicates that
        // this table can use extern function add_entry() in its
        // default (i.e. miss) action to add a new entry to the table
        // from the data plane.
        add_on_miss = true;
        // New PNA table property 'idle_timeout_with_auto_delete' is
        // similar to 'idle_timeout' in other architectures, except
        // that entries that have not been matched for their expire
        // time interval will be deleted, without the control plane
        // having to delete the entry.
        idle_timeout_with_auto_delete = true;
        const default_action = ct_tcp_table_miss;
    }

    apply {
        // _Arbitrary_ code here, perhaps looking up one or more tables,
        // in order to help determine the values of these variables that
        // affect how the CT table lookup operation behaves:

        // + do_add_on_miss
        // + update_expire_time
        // + new_expire_time

        do_add_on_miss = false;
        if (hdr.ipv4.isValid() && hdr.tcp.isValid()) {
            if (istd.direction == PNA_Direction_t.HOST_TO_NET) {
                // TBD: fix next line to check for SYN flag == 1
                new_expire_time = EXPIRE_TIME_PROFILE_MEDIUM;
                if (hdr.tcp.flags == 5) {
                    do_add_on_miss = true;
                    new_expire_time = EXPIRE_TIME_PROFILE_LONG;
                    // TBD: fix next line to check for FIN or RST flag == 1
                } else if (hdr.tcp.flags == 9) {
                    new_expire_time = EXPIRE_TIME_PROFILE_NOW;
                }
            }
        }

        // ct_tcp_table is a bidirectional table
        if (hdr.ipv4.isValid() && hdr.tcp.isValid()) {
        if (ct_tcp_table.apply().hit) {
            // do not drop the packet
            if (do_add_on_miss) {
                // Code here to send mirror packet to control plane
                // software with some kind of header or error status
                // indicating that an attempted add_on_miss failed.
            }
        } else {
            if (istd.direction == PNA_Direction_t.
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
